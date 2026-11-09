#!/usr/bin/env python3
"""Recovery after a reset, for the C64 REU build (x64sc and c1541 in PATH),
or with --machine c128 / c128-80 the C128's paged builds (x128): with an
REU, or with --no-reu the text in RAM bank 1 (p8vi-c128x, or p8vi-c128reu
without an REU).

crash: edit a file with an REU, wait until the text is synced, reset VICE
       (like the reset button), load and run p8vi again, :rec and save: the
       file is the edited text.
clean: the same, but quit with :q! instead of the reset: then there is
       nothing to recover (the file saved after :rec is the empty text,
       which a 1541 gives back as one CR).

    python3 tests/vice/rectest.py --prg build/p8vi-c64reu.prg
    python3 tests/vice/rectest.py --prg build/p8vi-c64font.prg --font build/oscii.fnt
    python3 tests/vice/rectest.py --machine c128 --prg build/p8vi-c128reu.prg
    python3 tests/vice/rectest.py --machine c128 --no-reu --prg build/p8vi-c128x.prg
"""

import argparse
import os
import re
import socket
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


def reset(port):
    """Reset VICE's machine (like the reset button) through the monitor.
    (on its own connection: after a reset the monitor comes back, and the
    replies don't follow the usual pattern; an x after a pause leaves it)"""
    s = socket.create_connection(('127.0.0.1', port), timeout=0.5)
    with s:
        for cmd in (b'reset 0\n', b'x\n'):
            s.sendall(cmd)
            time.sleep(1)
            try:
                while s.recv(65536):
                    pass
            except socket.timeout:
                pass


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
    reu = [] if args.no_reu else ['-reu', '-reusize', '512']
    emu = subprocess.Popen(edtest.EMU + reu + ['-debugcart',
                                               '-remotemonitor', '-remotemonitoraddress', f'ip4://127.0.0.1:{port}',
                                               '-8', d64, '-autostart', d64] +
                           ([] if edtest.MONITOR_KEYS else ['-keybuf', keys]) +
                           ['-limitcycles', '3000000000', '-exitscreenshot', base + '.png'],
                           stdout=log, stderr=subprocess.STDOUT, cwd=args.work)
    try:
        time.sleep(5)
        if edtest.MONITOR_KEYS:
            # (x128: see edtest.C128) type once the editor is up
            if not edtest.wait_for_editor(port):
                return False, f'  {name}: FAIL, the editor did not come up'
            edtest.monitor(port, ['keybuf ' + keys], 10)
        if crash:
            # wait until the editor has changed the text and synced it
            end = time.time() + 60
            while time.time() < end:
                c, sc = peekw(port, changes), peekw(port, synced)
                os.environ.get("RT_DEBUG") and print("DBG", c, sc, flush=True)
                if c and c == sc:
                    break
                time.sleep(1)
            else:
                return False, f'  {name}: FAIL, the text was never synced'
            reset(port)
        time.sleep(3)
        after = ':rec\\n:w r1\\n:q!\\npoke 55295,0\\n'
        if edtest.MONITOR_KEYS:
            edtest.monitor(port, ['keybuf load"p8vi",8\\nrun\\n'], 10)
            time.sleep(3)
            if not edtest.wait_for_editor(port):
                return False, f'  {name}: FAIL, the editor did not come up again'
            edtest.monitor(port, ['keybuf ' + after], 10)
        else:
            edtest.monitor(port, ['keybuf load"p8vi",8\\nrun\\n' + after], 10)
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
    ap.add_argument('--font', metavar='FNT', help='the font build: its font file')
    ap.add_argument('--jiffydos', action='store_true', help="the C64 with JiffyDOS (edtest.py's --jiffydos)")
    ap.add_argument('--machine', default='c64', choices=['c64', 'c128', 'c128-80'])
    ap.add_argument('--no-reu', action='store_true', help='without an REU (the C128: the text in bank 1)')
    args = ap.parse_args()
    machine = {'c128': edtest.C128, 'c128-80': edtest.C128_80}.get(args.machine)
    if machine:
        edtest.EMU, edtest.EXIT_POKE, edtest.SCREEN_DUMP = machine['EMU'], machine['EXIT_POKE'], machine['SCREEN_DUMP']
        edtest.COLUMNS = machine.get('COLUMNS', 40)
        edtest.MONITOR_KEYS = machine.get('MONITOR_KEYS', False)
    if args.jiffydos:
        edtest.EMU.extend(edtest.JIFFYDOS)
    if args.font:
        edtest.FONT = os.path.abspath(args.font)
        edtest.SCREEN_DUMP = (machine or {}).get('FONT_DUMP', 'm c800 cbe7')
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
