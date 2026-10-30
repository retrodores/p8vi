#!/usr/bin/env python3
"""Recovery after a reset, for the C64 REU build (x64sc and c1541 in PATH).

crash: edit a file with an REU, wait until the text is synced, reset VICE
       (like the reset button), load and run p8vi again, :rec and save: the
       file is the edited text.
clean: the same, but quit with :q! instead of the reset: then there is
       nothing to recover (the file saved after :rec is the empty text,
       which a 1541 gives back as one CR).

    python3 tests/vice/rectest.py --prg build/p8vi-c64reu.prg
"""

import argparse
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import edtest  # noqa: E402  (its disk and monitor helpers)

TEXT = b'one\ntwo\nthree\nfour\n'
EDITED = b'two\nthree\nnew line\nfour\n'
# dd, then a line after "three"
KEYS = r'ddjonew line\x1b'


def symbol(listing, name):
    """The address of variable name (block.var) in a 64tass listing."""
    block, var = name.split('.')
    in_block = False
    for line in open(listing, errors='replace'):
        if re.match(r'^[.>]?[0-9a-f]*\s+p8b_' + block + r'\b', line) or 'p8b_' + block + '\t' in line:
            in_block = True
        m = re.match(r'^>([0-9a-f]{4})\s+p8v_' + var + r'\s', line)
        if in_block and m:
            return int(m.group(1), 16)
        m = re.match(r'^=(\d+)\s+p8v_' + var + r'\s', line)
        if in_block and m:
            return int(m.group(1))
    raise SystemExit(f'{name} not found in {listing}')


def peekw(port, addr):
    reply = edtest.monitor(port, [f'm {addr:04x} {addr + 1:04x}'], 10)
    if not reply:
        return None
    m = re.search(r'>C:[0-9a-f]{4}\s+([0-9a-f]{2})\s+([0-9a-f]{2})', reply[0])
    return int(m.group(2) + m.group(1), 16) if m else None


def run(args, name, crash):
    base = os.path.join(args.work, 'rt-' + name)
    d64 = base + '.d64'
    edtest.make_disk(d64, args.prg, TEXT)
    listing = os.path.splitext(args.prg)[0] + '.list'
    changes = symbol(listing, 'buffer.changes')
    synced = symbol(listing, 'buffer.synced_changes')
    port = args.port
    log = open(base + '.log', 'wb')
    keys = ':e t.txt\\n' + KEYS + ('' if crash else ':q!\\n')
    emu = subprocess.Popen(edtest.EMU + ['-reu', '-reusize', '512', '-debugcart',
                                         '-remotemonitor', '-remotemonitoraddress', f'ip4://127.0.0.1:{port}',
                                         '-8', d64, '-autostart', d64, '-keybuf', keys,
                                         '-limitcycles', '3000000000', '-exitscreenshot', base + '.png'],
                           stdout=log, stderr=subprocess.STDOUT, cwd=args.work)
    try:
        time.sleep(5)
        if crash:
            # wait until the editor has changed the text and synced it
            end = time.time() + 60
            while time.time() < end:
                c, sc = peekw(port, changes), peekw(port, synced)
                if c and c == sc:
                    break
                time.sleep(1)
            else:
                return False, f'  {name}: FAIL, the text was never synced'
            edtest.monitor(port, ['reset 0'], 10)
        time.sleep(3)
        edtest.monitor(port, ['keybuf load"p8vi",8\\nrun\\n:rec\\n:w r1\\n:q!\\npoke 55295,0\\n'], 10)
        emu.wait(timeout=120)
    except subprocess.TimeoutExpired:
        return False, f'  {name}: FAIL, did not finish'
    finally:
        if emu.poll() is None:
            emu.kill()
        log.close()
    out = base + '_r1'
    if os.path.exists(out):
        os.remove(out)
    subprocess.run(['c1541', '-attach', d64, '-read', 'r1,s', out], capture_output=True)
    got = open(out, 'rb').read() if os.path.exists(out) else None
    want = EDITED if crash else b'\r'
    if got == want:
        return True, f'  {name}: ok'
    return False, f'  {name}: FAIL\n    want {want!r}\n    got  {got!r}'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--prg', default='build/p8vi-c64reu.prg')
    ap.add_argument('--work', default='build')
    ap.add_argument('--port', type=int, default=6640)
    args = ap.parse_args()
    args.prg = os.path.abspath(args.prg)
    args.work = os.path.abspath(args.work)
    results = [run(args, 'crash', True), run(args, 'clean', False)]
    for ok, line in results:
        print(line)
    failed = sum(not ok for ok, line in results)
    print(f'{len(results) - failed} of {len(results)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
