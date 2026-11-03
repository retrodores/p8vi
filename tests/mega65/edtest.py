#!/usr/bin/env python3
"""Editor tests on a MEGA65 in Xemu (xmega65), through tools/m65harness.py.

    edtest.py [--prg build/p8vi-mega65.prg] [--work build] [files|screen] [name...]

The suites are the ones of tests/vice/edtest.py, typed as the same PETSCII
codes through the MEGA65's virtual keyboard (the harness's PETSCII table):

files   (default) types vi commands at the editor, saves the text with
        ":w name" after each step, and compares the saved files on the .d81
        with the expected text.
screen  types keys, reads screen memory, does the same again after Ctrl-L
        (a full redraw), and compares the two screens (not the cursor, which
        blinks).

Runs go one at a time: several Xemus started at once fight over one config
file in the preferences directory (see the harness).  After every RETURN
the runner waits for the screen to stop changing, so keys typed while a
file is read or written aren't lost.

Differences from the VICE runner's suites (MEGA65 below):
- read-dir: the directory of a .d81, and the MEGA65's DOS ends it with
  "BLOCKS FREE" (a 1541: "BLOCKS FREE.").
- dos: the rename is sent as r0:new=0:old; the MEGA65's DOS answers
  r:new=old with 79, SINGLE DRIVE D0 ONLY.
- big is left out (--all runs it): its g3 is 6.3 KB of text, more than the
  6 KB this build has ($c000 minus the program, the yank buffer and the
  undo log), so the :r stops with "buffer full".
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools'))
sys.path.insert(0, os.path.join(HERE, '..', 'vice'))
import m65harness as h  # noqa: E402
import edtest as vice  # noqa: E402

# the 80 column screen of MEGA65 mode, lower case characters, the cursor a
# reversed character
SCREEN = h.Screen(at=0x0800, rows=25, row_bytes=80, lowercase=True, plain_reverse=True)
STATUS_ROW = 24
# how long the screen must stay the same to count as finished
QUIET = 0.5
RETURN = 0x0D
CTRL_L = 0x0C
D81_FREE = 3160         # blocks free on an empty .d81


def petscii(keys):
    """VICE -keybuf text as PETSCII: \\n is RETURN, \\xNN a code, a-z are
    the unshifted letters ($41-$5A), A-Z the shifted ones ($C1-$DA)."""
    out = bytearray()
    i = 0
    while i < len(keys):
        c = keys[i]
        if keys.startswith('\\n', i):
            out.append(RETURN)
            i += 2
            continue
        if keys.startswith('\\x', i):
            out.append(int(keys[i + 2:i + 4], 16))
            i += 4
            continue
        if c == '\n':
            out.append(RETURN)
        elif 'a' <= c <= 'z':
            out.append(ord(c) - 0x20)
        elif 'A' <= c <= 'Z':
            out.append(ord(c) + 0x80)
        else:
            out.append(ord(c))
        i += 1
    return bytes(out)


def dir_text(args, text, after):
    """text with the test disk's directory read in after line number after,
    as :r $ does (the .d81 version of the VICE runner's)"""
    blocks = -(-os.path.getsize(args.prg) // 254)
    lines = [b'0 "TEST            " 52 3D',
             b'%d%s"P8VI"             PRG' % (blocks, b' ' * (5 - len(str(blocks)))),
             b'1    "T.TXT"            SEQ',
             b'%d BLOCKS FREE' % (D81_FREE - blocks - 1)]
    old = text.split(b'\n')
    return b'\n'.join(old[:after] + lines + old[after:])


def make_disk(d81, prg, text, blocks_free=None):
    txt = d81 + '.txt'
    with open(txt, 'wb') as f:
        f.write(text)
    subprocess.run(['c1541', '-format', 'test,52', 'd81', d81, '-attach', d81,
                    '-write', prg, 'p8vi,p', '-write', txt, 't.txt,s'],
                   check=True, capture_output=True)
    if blocks_free is not None:
        out = subprocess.run(['c1541', '-attach', d81, '-dir'], capture_output=True, text=True).stdout
        free = int(re.search(r'(\d+) blocks free', out).group(1))
        fill = d81 + '.fill'
        with open(fill, 'wb') as f:
            f.write(b'x' * 254 * (free - blocks_free))
        subprocess.run(['c1541', '-attach', d81, '-write', fill, 'fill,s'],
                       check=True, capture_output=True)


# suites that need more text memory than the MEGA65 build has
TOO_BIG = ['big']


def mega65_suite(suite):
    """a VICE suite with the MEGA65's DOS command syntax"""
    if suite[0] == 'dos':
        return (suite[0], suite[1].replace('@r:moved=keep', '@r0:moved=0:keep')) + tuple(suite[2:])
    return suite


def started(shot):
    """p8vi is up: the position on its status line"""
    return '1,1' in shot.text(STATUS_ROW)


def type_keys(m, keys, timeout):
    """keys typed in pieces up to each RETURN, waiting for the screen to
    settle after each"""
    for piece in re.split(b'(?<=\r)', keys):
        if piece:
            m.type_petscii(piece)
            m.settled(timeout, QUIET)


def edit(args, d81, keys):
    """p8vi started, t.txt edited with keys; yields the machine"""
    return h.launch(args.emulator, args.prg, prgmode='65', screen=SCREEN,
                    extra=['-8', d81], ready=started, timeout=args.timeout)


def run_files(args, suite):
    name, keys, expected, *text = suite
    base = os.path.join(args.work, 'mt-' + name)
    d81 = base + '.d81'
    make_disk(d81, args.prg, text[0] if text else vice.SHORT, text[1] if len(text) > 1 else None)
    lines = []
    ok = True
    try:
        with edit(args, d81, keys) as m:
            type_keys(m, petscii(':e t.txt\\n' + keys), args.timeout)
            # (not type_keys: at READY the cursor blinks, so the screen
            # never stays the same)
            m.type_petscii(petscii(':q!\\n'))
            m.wait_until(lambda s: 'ready.' in s.whole().lower(), args.timeout, 'no READY. after :q!')
    except h.Failure as failed:
        ok = False
        lines.append(f'  {failed}')
        if failed.shown:
            lines.append('  screen:\n    ' + failed.shown.replace('\n', '\n    '))
    for fname, want in expected:
        out = base + '_' + fname
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(['c1541', '-attach', d81, '-read', fname + ',s', out], capture_output=True)
        got = open(out, 'rb').read() if os.path.exists(out) else None
        if callable(want):
            want = want(args)
        if got != want:
            ok = False
            lines.append(f'  {fname}: FAIL\n    want {want!r}\n    got  {got!r}')
    return name, ok, lines


def run_screen(args, suite):
    name, text, keys = suite
    d81 = os.path.join(args.work, 'ms-' + name + '.d81')
    make_disk(d81, args.prg, text)
    try:
        with edit(args, d81, keys) as m:
            type_keys(m, petscii(':e t.txt\\n'), args.timeout)
            m.type_petscii(petscii(keys))
            partial = m.settled(args.timeout, QUIET)
            m.type_petscii(bytes([CTRL_L]))
            full = m.settled(args.timeout, QUIET)
    except h.Failure as failed:
        return name, False, [f'  {failed}']
    # both must be the editor in its normal mode, with "line,col" on the
    # status line, or the run didn't get through its keys
    for shot in (partial, full):
        if not re.search(r'[0-9],[0-9]', shot.text(STATUS_ROW)):
            return name, False, ['  the editor is not on the screen:\n    '
                                 + shot.whole().replace('\n', '\n    ')]
    # bit 7 is the reversed (blinking) cursor
    lines = []
    for r in range(SCREEN.rows):
        a, b = partial.codes(r), full.codes(r)
        cols = [c for c in range(len(a)) if (a[c] ^ b[c]) & 0x7F]
        if cols:
            lines.append(f'  row {r:2} cols {cols[:10]}: {partial.text(r).rstrip()!r}\n'
                         f'  redrawn: {full.text(r).rstrip()!r}')
    return name, not lines, lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('kind', nargs='?', default='files', choices=['files', 'screen'])
    ap.add_argument('names', nargs='*', help='only run these suites')
    ap.add_argument('--prg', default='build/p8vi-mega65.prg')
    ap.add_argument('--work', default='build')
    ap.add_argument('--emulator', default='xmega65')
    ap.add_argument('--timeout', type=float, default=60.0, help='seconds for one step')
    ap.add_argument('--skip', action='append', default=[], metavar='SUITE',
                    help='leave this suite out')
    ap.add_argument('--all', action='store_true', help='also the suites too big for this build')
    ap.add_argument('--font', action='store_true',
                    help='the font build: also the font suite (no font file: it uses the ROM\'s)')
    ap.add_argument('--paged', action='store_true',
                    help='the page store build: also the REU suites (more text than main RAM holds)')
    args = ap.parse_args()
    for tool in (args.emulator, 'c1541'):
        if not shutil.which(tool):
            sys.exit(f'{tool} not found in PATH')
    args.prg = os.path.abspath(args.prg)
    if not os.path.exists(args.prg):
        sys.exit(f'{args.prg}: no such program')
    args.work = os.path.abspath(args.work)
    os.makedirs(args.work, exist_ok=True)
    # the read-dir suite, with this disk's directory
    vice.dir_text = dir_text

    if args.kind == 'files':
        suites = [mega65_suite(s) for s in vice.FILE_SUITES + (vice.REU_SUITES if args.paged else [])
                  + (vice.FONT_SUITES if args.font else [])
                  if args.all or args.paged or args.names or s[0] not in TOO_BIG]
        work = run_files
    else:
        suites = vice.SCREEN_SUITES
        work = run_screen
    suites = [s for s in suites if (not args.names or s[0] in args.names) and s[0] not in args.skip]
    if not suites:
        sys.exit('no such suite')

    failed = 0
    for suite in suites:
        start = time.time()
        name, ok, lines = work(args, suite)
        print(f'{name}: {"ok" if ok else "FAIL"} ({time.time() - start:.0f}s)', flush=True)
        for line in lines:
            print(line)
        failed += not ok
    print(f'{args.kind}: {len(suites) - failed} of {len(suites)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
