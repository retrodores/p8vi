#!/usr/bin/env python3
"""p8vi's file tests on an Amiga 500 in Copperline (the amiga500 build).

    amigatest.py [--prg build/p8vi-amigatest] [--rom ROM] [-j N] [name...]

The suites are tests/vice/edtest.py's file suites, as tests/cpm/cpmtest.py
runs them on CP/M: for each one a directory with t.txt and keys.txt (the
keys, the editor's codes), p8vi's test build plays the keys
(features.KEYFILE) and quits, and the files it wrote are compared with
the expected ones.  Copperline runs it (--run, its directory is the
Amiga's current one) as an A500 with the ROM given, Kickstart 1.3 by
default if it's in ~/Documents/FS-UAE/Kickstarts, else Copperline's own
AROS; --exit-on-return ends the run when p8vi does (--run warps the boot;
p8vi runs at an A500's speed).  The screen suites need the screen's output, which Copperline
doesn't give the host: not here.

The suites left out are CBM_ONLY's (PETSCII files, CBM DOS commands and
drive prefixes, the C64's graphics keys).
"""

import argparse
import os
import shutil
import subprocess
import sys
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
    """run p8vi in work; its output (none: Copperline keeps the screen), or
    None if it didn't end"""
    cmd = ['copperline', '--model', 'A500', '--run', 'p8vi.com', '--exit-on-return']
    if ARGS.rom:
        cmd.append(ARGS.rom)
    try:
        subprocess.run(cmd, cwd=work, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return None
    return b''


ARGS = None


def main():
    global ARGS
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('names', nargs='*', help='only run these suites')
    ap.add_argument('--prg', default='build/p8vi-amigatest')
    ap.add_argument('--rom', default=KICKSTART if os.path.exists(KICKSTART) else None,
                    help='the Kickstart ROM (default: 1.3 if it is there, else AROS)')
    ap.add_argument('--work', default='build')
    ap.add_argument('-j', type=int, default=4)
    ap.add_argument('--skip', action='append', default=[], metavar='SUITE')
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
