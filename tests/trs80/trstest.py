#!/usr/bin/env python3
"""The editor's file tests on a TRS-80 Model III with LDOS, or a Model 4
with LS-DOS 6.3 (--model 4), in trs80gp.

    trstest.py [--model 3|4] [--prg build/p8vi-trs80test.cmd] [-j N] [--skip SUITE] [name...]

Runs tests/vice/edtest.py's file suites with the TRS-80 test build
(make trs80-test: features.KEYFILE), which plays the keys in KEYS/TXT
before it reads the keyboard.  trs80gp's own ways of typing don't work for
this: its paste (-i) only reaches programs that wait for a key through
LDOS, and after a key typed on the keyboard matrix (-ik) the next file open
hangs.  So, for each suite, in a directory of its own:

  - keys.txt gets ":e t.txt", the suite's keys and ":q!" as the editor's
    key codes (edtest's: \\n RETURN, \\x1b Escape, ...), t.txt the text
  - trs80gp boots LDOS (-ld) with its LDOS utility disk in drive 1 (:lu3,
    which has FreHD's IMPORT2 and EXPORT2; on the Model 4 LS-DOS 6.3 and
    :lu4, the same for it) and the directory as the FreHD's
    (-frehd_dir), and types, at the LDOS prompt, where its paste works:
    IMPORT2 of the program, the text and the keys to drive 1, P8VI, and
    after p8vi has quit, EXPORT2 of each file the suite checks
  - the files that came back are compared with the suite's (CR as LF)

trs80gp is TRS80GP (the path of its binary), else on the PATH.  It opens a
window for each run (it can't be hidden).
"""

import argparse
import codecs
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'vice'))
import edtest  # noqa: E402

TRS80GP = os.environ.get('TRS80GP') or shutil.which('trs80gp') or \
    os.path.expanduser('~/Applications/trs80gp.app/Contents/MacOS/trs80gp')
TIMEOUT = 600
# the test build's key buffer (KEY_BUF_SIZE in src/trs80/platform.p8)
KEY_BUF_SIZE = 256


def key_bytes(keys):
    """edtest's -keybuf syntax (\\n RETURN, \\xNN a byte) to the bytes"""
    b = codecs.decode(keys, 'unicode_escape').encode('latin-1')
    return b.replace(b'\n', b'\r')


def looks_ascii(text):
    """as p8vi's charset.looks_ascii: more lowercase than uppercase letters.
    the CBM builds take such a file as ASCII and keep typed letters ASCII,
    so its case isn't swapped"""
    lower = sum(1 for c in text if 0x61 <= c <= 0x7a)
    upper = sum(1 for c in text if 0x41 <= c <= 0x5a)
    return lower > upper


def lf_endings(text):
    """CR LF and CR as LF"""
    return text.replace(b'\r\n', b'\n').replace(b'\r', b'\n')


def to_trs(text):
    """a suite's text (in the CBM builds' terms) as it is on the TRS-80.  On
    the CBM machines a typed letter is PETSCII, which a file shows in the
    other case: typed zzz is ZZZ in the file, the text's ALPHA is alpha on
    the screen (and /alpha finds it).  The TRS-80 keeps typed letters as
    they are, so the text and the files expected swap case: A-Z <-> a-z,
    and PETSCII's capitals $c1-$da are A-Z."""
    out = bytearray()
    for c in text:
        if 0x41 <= c <= 0x5a or 0x61 <= c <= 0x7a:
            c ^= 0x20
        elif 0xc1 <= c <= 0xda:
            c -= 0x80
        out.append(c)
    return bytes(out)


# files from a new text (:e! new), which the CBM builds keep as PETSCII
# whatever the suite's text: their case is swapped
NEW_TEXTS = {('final-eol', 'new')}

# the suites for CBM things: PETSCII and ASCII files, the C64's graphics
# keys, CBM DOS commands and drive prefixes, a disk filled with c1541
CBM_ONLY = ['ascii', 'g-cmds', 'read-dir', 'dos', 'prefix', 'save-full']
# and what the Model III build leaves out for room (features.MARKS, Z_VIEW;
# the Model 4 has them)
NO_ROOM = ['marks', 'zview']

# per model: trs80gp's machine, its utility disk (IMPORT2, EXPORT2), the
# test build, and the suites left out for room
MODELS = {
    '3': ('-m3', ':lu3', 'build/p8vi-trs80test.cmd', NO_ROOM),
    '4': ('-m4', ':lu4', 'build/p8vi-trs80m4test.cmd', []),
}


def trs_name(name):
    """a test's file name as LDOS has it: t.txt is T/TXT"""
    return name.upper().replace('.', '/')


def run_suite(args, suite):
    name, keys, expected, *text = suite
    work = tempfile.mkdtemp(prefix='trs-' + name + '-', dir=args.work)
    shutil.copyfile(args.prg, os.path.join(work, 'p8vi.cmd'))
    start = text[0] if text else edtest.SHORT
    swap = to_trs if not looks_ascii(start) else (lambda t: t)
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        # (LF line endings to CR, CR LF stays CR LF)
        f.write(swap(start).replace(b'\r\n', b'\0').replace(b'\n', b'\r').replace(b'\0', b'\r\n'))
    played = key_bytes(':e t.txt\\n' + keys + ':q!\\n')
    if len(played) > KEY_BUF_SIZE:
        return name, False, [f'  {len(played)} bytes of keys, the test build holds {KEY_BUF_SIZE}']
    with open(os.path.join(work, 'keys.txt'), 'wb') as f:
        f.write(played)
    typed = ['-iw', 'Ready', '-id', '60',
             '-i', 'IMPORT2 p8vi.cmd P8VI/CMD:1\\r', '-id', '900',
             '-i', 'IMPORT2 t.txt T/TXT:1\\r', '-id', '300',
             '-i', 'IMPORT2 keys.txt KEYS/TXT:1\\r', '-id', '300',
             # p8vi clears the screen at the start and at the end; LDOS
             # says Ready again when it has quit
             '-i', 'P8VI\\r', '-id', '600', '-iw', 'Ready', '-id', '60']
    for fname, _ in expected:
        typed += ['-i', f'EXPORT2 {trs_name(fname)} {fname}.out\\r', '-id', '300']
    # (the last EXPORT2 may still be running)
    typed += ['-id', '900', '-ics', '-ix']
    # (drive 0, LDOS's, has 10.5K free, a few files: write-protected, the
    # new files go to drive 1)
    machine, disk, _, _ = MODELS[args.model]
    command = [TRS80GP, '-ee', '-batch', '-turbo', '-im', 'wp', '0', 'on', machine, '-ld',
               '-d1', disk, '-frehd', '-frehd_dir', work, '-itime', '0'] + typed
    lines = []
    try:
        subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        lines.append(f'  trs80gp did not finish in {TIMEOUT} s (see {work})')
    for fname, want in expected:
        path = os.path.join(work, fname + '.out')
        got = None
        if os.path.exists(path):
            with open(path, 'rb') as f:
                got = lf_endings(f.read())
        if want is not None:
            want = lf_endings(want)
            want = to_trs(want) if (name, fname) in NEW_TEXTS else swap(want)
        if got != want:
            lines += [f'  {fname}: FAIL', f'    want {want!r}', f'    got  {got!r}']
    if lines:
        lines.append(f'  (files in {work})')
    else:
        shutil.rmtree(work)
    return name, not lines, lines


def main():
    ap = argparse.ArgumentParser(description='p8vi file tests on a TRS-80 in trs80gp')
    ap.add_argument('names', nargs='*', help='only run these suites')
    ap.add_argument('--model', default='3', choices=sorted(MODELS),
                    help='the Model III (LDOS) or the Model 4 (LS-DOS 6.3)')
    ap.add_argument('--prg', help='the test build (the model\'s by default)')
    ap.add_argument('--work', default='build')
    ap.add_argument('-j', type=int, default=1)
    ap.add_argument('--skip', action='append', default=[], metavar='SUITE')
    args = ap.parse_args()
    if not os.path.exists(TRS80GP):
        sys.exit('trs80gp not found: set TRS80GP to its path')
    _, _, prg, no_room = MODELS[args.model]
    args.prg = os.path.abspath(args.prg or prg)
    args.work = os.path.abspath(args.work)
    suites = [s for s in edtest.FILE_SUITES
              if (not args.names or s[0] in args.names) and s[0] not in args.skip
              and (args.names or s[0] not in CBM_ONLY + no_room)]
    if not suites:
        sys.exit('no such suite')
    failed = 0
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        for name, ok, lines in pool.map(lambda s: run_suite(args, s), suites):
            print(f'{name}: {"ok" if ok else "FAIL"}', flush=True)
            for line in lines:
                print(line)
            failed += not ok
    print(f'files: {len(suites) - failed} of {len(suites)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
