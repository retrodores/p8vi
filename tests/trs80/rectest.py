"""Recovery after a reset, for the TRS-80 Model 4 128 KB build
(p8vi-trs80m4x) in trs80gp, as tests/vice/rectest.py does for the C64 REU:

crash: edit a file, wait until the text is synced (when no key came for
       a moment), reset the machine (trs80gp's -ictl reset, like the reset
       button: the second 64 KB keeps its contents), run p8vi again, :rec
       and save: the file is the edited text.
clean: the same, but quit with :q! instead of the reset: then there is
       nothing to recover (the file saved after :rec is the empty text,
       one CR).

    python3 -B tests/trs80/rectest.py
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import trstest  # noqa: E402  (trs80gp, the key file format)

TEXT = b'one\rtwo\rthree\rfour\r'
EDITED = b'two\rthree\rnew line\rfour\r'
KEYS = r'ddjonew line\x1b'
TIMEOUT = 600


def run(args, mode):
    work = tempfile.mkdtemp(prefix='rec-' + mode + '-', dir=args.work)
    shutil.copyfile(args.prg, os.path.join(work, 'p8vi.cmd'))
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(TEXT)
    first = r':e t.txt\n' + KEYS + (r':q!\n' if mode == 'clean' else '')
    with open(os.path.join(work, 'keys1.txt'), 'wb') as f:
        f.write(trstest.key_bytes(first))
    with open(os.path.join(work, 'keys2.txt'), 'wb') as f:
        f.write(trstest.key_bytes(r':rec\n:w r.txt\n:q!\n'))
    typed = ['-iw', 'Ready', '-id', '60',
             '-i', 'IMPORT2 p8vi.cmd P8VI/CMD:1\\r', '-id', '900',
             '-i', 'IMPORT2 t.txt T/TXT:1\\r', '-id', '300',
             '-i', 'IMPORT2 keys1.txt KEYS/TXT:1\\r', '-id', '300',
             '-i', 'P8VI\\r']
    if mode == 'clean':
        typed += ['-id', '1500', '-iw', 'Ready', '-id', '60']
    else:
        # the edit on the screen, then idle long enough for the sync (30
        # ticks without a key), then the reset; LS-DOS boots again
        typed += ['-iw', 'new line', '-id', '300', '-ictl', 'reset', '-iw', 'Ready', '-id', '60']
    # (the wait for Ready after P8VI only after a pause: before p8vi
    # clears the screen the prompt is still there)
    typed += ['-i', 'IMPORT2 keys2.txt KEYS/TXT:1\\r', '-id', '300',
              '-i', 'P8VI\\r', '-id', '1500', '-iw', 'Ready', '-id', '60',
              '-i', 'EXPORT2 R/TXT r.out\\r', '-id', '600', '-ix']
    command = [trstest.TRS80GP, '-ee', '-batch', '-turbo', '-m4', '-mem', '128', '-ld',
               '-d1', ':lu4', '-frehd', '-frehd_dir', work, '-itime', '0'] + typed
    lines = []
    try:
        subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        lines.append(f'  trs80gp did not finish in {TIMEOUT} s')
    out = os.path.join(work, 'r.out')
    got = open(out, 'rb').read() if os.path.exists(out) else None
    want = EDITED if mode == 'crash' else b'\r'
    if got != want:
        lines += [f'  want {want!r}', f'  got  {got!r}', f'  (files in {work})']
    else:
        shutil.rmtree(work)
    return not lines, lines


def main():
    ap = argparse.ArgumentParser(description='p8vi-trs80m4x: :rec after a reset, in trs80gp')
    ap.add_argument('modes', nargs='*', default=['crash', 'clean'], choices=['crash', 'clean'])
    ap.add_argument('--prg', default='build/p8vi-trs80m4xtest.cmd')
    ap.add_argument('--work', default='build')
    args = ap.parse_args()
    if not os.path.exists(trstest.TRS80GP):
        sys.exit('trs80gp not found: set TRS80GP to its path')
    args.prg = os.path.abspath(args.prg)
    args.work = os.path.abspath(args.work)
    failed = 0
    for mode in args.modes:
        ok, lines = run(args, mode)
        print(f'rec {mode}: {"ok" if ok else "FAIL"}', flush=True)
        for line in lines:
            print(line)
        failed += not ok
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
