#!/usr/bin/env python3
"""p8vi's file tests on an Amiga 500 in Copperline (the amiga500 build).

    amigatest.py [--prg build/p8vi-amigatest] [--rom ROM] [-j N] [files|screen|number] [name...]
    amigatest.py --resize            (Kickstart 1.3 only)

The suites are tests/vice/edtest.py's file suites, as tests/cpm/cpmtest.py
runs them on CP/M: for each one a directory with t.txt and keys.txt (the
keys, the editor's codes), p8vi's test build plays the keys
(features.KEYFILE) and quits, and the files it wrote are compared with
the expected ones.  Copperline runs it (--run, its directory is the
Amiga's current one) as an A500 with the ROM given, Kickstart 1.3 by
default if it's in ~/Documents/FS-UAE/Kickstarts, else Copperline's own
AROS; --exit-on-return ends the run when p8vi does (--run warps the boot;
p8vi runs at an A500's speed).

endings: a new text's line endings as written (LF), which the other
suites can't see (cpmtest.py's ENDING_CASES).

screen, number: edtest's screen suites (and cpmtest.py's :set number
ones) as cpmtest.py runs them: p8vi's output goes to a file (p8vi.com
>out.log, the CLI's redirection: the keys still come from the window),
tests/cpm/termplay.py plays it back on an 80 x 24 screen, and the screen
after the keys must be the one after a full redraw (Ctrl-L) too.  ANSI
only (the Amiga's console).  This checks what p8vi sends, not how
console.device draws it.

The suites left out are CBM_ONLY's (PETSCII files, CBM DOS commands and
drive prefixes, the C64's graphics keys).

files --own-window: p8vi started with <NIL: as its input, so it opens a
window of its own (CON:), as when it's started from Workbench.

--resize: the window resized while p8vi runs (Kickstart 1.3's first CLI
window, 20 rows): Copperline drags its size gadget with the mouse, then
types L (the screen's last text line), x and :w.  Without the drag line
19 loses its first character; after it (14 rows) line 13 does, which
p8vi only knows from the console's resize report.  The drag's places are
the 1.3 window's, so not on AROS.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'cpm'))
import cpmtest  # noqa: E402

KICKSTART = os.path.expanduser('~/Documents/FS-UAE/Kickstarts/amiga-os-130.rom')
TIMEOUT = 180
# the test build's key buffer (KEY_BUF_SIZE in src/amiga/platform.p8)
KEY_BUF_SIZE = 1024


def copperline(work, *options):
    """run p8vi in work; its output (to out.log: the CLI's redirection), or
    None if it didn't end"""
    # (files --own-window: input from NIL:, so p8vi opens a window of its
    # own, as when started from Workbench)
    run_args = '<NIL:' if ARGS.own_window else '>out.log'
    cmd = ['copperline', '--model', 'A500', '--run', 'p8vi.com', '--run-args', run_args,
           '--exit-on-return']
    if ARGS.rom:
        cmd.append(ARGS.rom)
    try:
        subprocess.run(cmd, cwd=work, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return None
    path = os.path.join(work, 'out.log')
    if ARGS.own_window:
        return b''
    if not os.path.exists(path):
        return None
    with open(path, 'rb') as f:
        return f.read()


ARGS = None

# --resize: the text (one row per line), and the cases: name, Copperline's
# mouse script (none: no drag), the line L goes to
RESIZE_TEXT = b''.join(b'line %02d text\n' % i for i in range(1, 41))
DRAG = ['--mouse-to-after', '10', '690', '404', '--click-after', '16', 'left', '3000',
        '--mouse-to-after', '16.3', '520', '300']
RESIZE_CASES = [('no-resize', [], 19), ('resize', DRAG, 13)]


def run_resize(args, case):
    name, drag, line = case
    work = tempfile.mkdtemp(prefix='amiga-' + name + '-', dir=args.work)
    shutil.copyfile(args.prg, os.path.join(work, 'p8vi.com'))
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(RESIZE_TEXT)
    with open(os.path.join(work, 'keys.txt'), 'wb') as f:
        f.write(b':e t.txt\r')
    cmd = (['copperline', '--model', 'A500', '--run', 'p8vi.com', '--exit-on-return'] + drag +
           ['--type-after', '21', 'Lx:w r1\n:q!\n', args.rom])
    try:
        subprocess.run(cmd, cwd=work, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return name, False, [f'  did not finish in {TIMEOUT} s (files in {work})']
    lines = RESIZE_TEXT.split(b'\n')
    lines[line - 1] = lines[line - 1][1:]
    want = b'\n'.join(lines)
    path = os.path.join(work, 'r1')
    got = open(path, 'rb').read() if os.path.exists(path) else None
    if got != want:
        return name, False, [f'  r1: line {line} should have lost its first character',
                             f'    got  {got!r}', f'  (files in {work})']
    shutil.rmtree(work)
    return name, True, []


def main():
    global ARGS
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('kind', nargs='?', default='files', choices=['files', 'screen', 'number', 'endings'])
    ap.add_argument('names', nargs='*', help='only run these suites')
    ap.add_argument('--prg', default='build/p8vi-amigatest')
    ap.add_argument('--rom', default=KICKSTART if os.path.exists(KICKSTART) else None,
                    help='the Kickstart ROM (default: 1.3 if it is there, else AROS)')
    ap.add_argument('--work', default='build')
    ap.add_argument('-j', type=int, default=4)
    ap.add_argument('--skip', action='append', default=[], metavar='SUITE')
    ap.add_argument('--resize', action='store_true', help='the window resized while p8vi runs (Kickstart 1.3)')
    ap.add_argument('--own-window', action='store_true',
                    help='(files) input from NIL:: p8vi opens a window of its own, as from Workbench')
    args = ap.parse_args()
    if not shutil.which('copperline'):
        sys.exit('copperline not found in PATH')
    args.prg = os.path.abspath(args.prg)
    args.work = os.path.abspath(args.work)
    args.host = False
    ARGS = args
    # cpmtest's set-up and checks, with Copperline for tnylpo
    cpmtest.ARGS = args
    cpmtest.KEY_BUF_SIZE = KEY_BUF_SIZE
    cpmtest.tnylpo = copperline
    if args.resize:
        if not args.rom or '130' not in args.rom:
            sys.exit('--resize needs Kickstart 1.3 (--rom)')
        failed = 0
        with ThreadPoolExecutor(max_workers=args.j) as pool:
            for name, ok, lines in pool.map(lambda c: run_resize(args, c), RESIZE_CASES):
                print(f'{name}: {"ok" if ok else "FAIL"}', flush=True)
                for line in lines:
                    print(line)
                failed += not ok
        print(f'amiga resize: {len(RESIZE_CASES) - failed} of {len(RESIZE_CASES)} passed')
        sys.exit(1 if failed else 0)
    if args.kind == 'endings':
        # (a new text's line endings as written: LF on the Amiga)
        cpmtest.NEW_EOL = b'\n'
        cases = [c for c in cpmtest.ENDING_CASES if not args.names or c[0] in args.names]
        failed = 0
        for name, ok, lines in map(lambda c: cpmtest.run_ending(args, c), cases):
            print(f'{name}: {"ok" if ok else "FAIL"}', flush=True)
            for line in lines:
                print(line)
            failed += not ok
        print(f'amiga endings: {len(cases) - failed} of {len(cases)} passed')
        sys.exit(1 if failed else 0)
    if args.kind != 'files':
        # (the Amiga's console is ANSI only)
        cpmtest.TERMS = ['ansi']
        pool_suites = cpmtest.edtest.SCREEN_SUITES + (cpmtest.NUMBER_SUITES if args.kind == 'number' else [])
        suites = [s for s in pool_suites if (not args.names or s[0] in args.names) and s[0] not in args.skip]
        run = cpmtest.run_screen if args.kind == 'screen' else cpmtest.run_number
        failed = 0
        with ThreadPoolExecutor(max_workers=args.j) as pool:
            for name, ok, lines in pool.map(lambda s: run(args, s), suites):
                print(f'{name}: {"ok" if ok else "FAIL"}', flush=True)
                for line in lines:
                    print(line)
                failed += not ok
        print(f'amiga {args.kind}: {len(suites) - failed} of {len(suites)} passed')
        sys.exit(1 if failed else 0)
    suites = [s for s in cpmtest.edtest.FILE_SUITES
              if (not args.names or s[0] in args.names) and s[0] not in args.skip
              and (args.names or s[0] not in cpmtest.CBM_ONLY)]
    if not suites:
        sys.exit('no such suite')
    failed = 0
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        for name, ok, lines in pool.map(lambda s: cpmtest.run_files(args, s), suites):
            print(f'{name}: {"ok" if ok else "FAIL"}', flush=True)
            for line in lines:
                print(line)
            failed += not ok
    rom = 'Kickstart 1.3' if args.rom and '130' in args.rom else ('AROS' if not args.rom else args.rom)
    print(f'amiga files ({rom}): {len(suites) - failed} of {len(suites)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
