#!/usr/bin/env python3
"""The editor's tests for the CP/M version, in tnylpo (a CP/M 2.2 emulator
for the host: the files are the directory's).

    cpmtest.py files [--prg build/p8vi-cpmtest.com] [-j N] [--skip SUITE] [name...]
    cpmtest.py screen [-j N] [name...]
    cpmtest.py number | lines [-j N] [name...]
    cpmtest.py --host [files|screen|number|lines|big] ...    (the host version, build/p8vi-host)

Both use the test build (make cpm-test: features.KEYFILE), which plays the
keys in KEYS.TXT before it reads the console.  For each suite, in a
directory of its own, keys.txt gets ":e t.txt", the suite's keys and ":q!"
as the editor's key codes, t.txt the text, and tnylpo -b (line mode: the
console is stdin and stdout) runs p8vi.com.

files:  tests/vice/edtest.py's file suites; the files left are compared
        with the suite's (CR LF and CR as LF; a file ends at its first ^Z)
screen: edtest's screen suites, on each of the terminals (-t ansi, vt52,
        adm3a): tests/cpm/termplay.py plays p8vi's output back, and the
        screen after the keys must be the same as after a full redraw
        (Ctrl-L), and the same on the three terminals.  The test build
        sends the screen before each key it plays (as it does before
        reading the console), and the key $ff marks where the suite's keys
        end: the screen there is the one compared.

number: the screen suites again with :set number first (features.NUMBER),
        and NUMBER_SUITES: a line split or joined that leaves the rows
        after it where they were, but with other numbers.
lines:  :[range]d and :[range]y (features.LINE_CMDS) against the
        normal-mode keys that do the same (LINES_PAIRS): the text after
        each, and an x for the cursor's place, must be the same.
big:    (--host) the wide build's 32-bit positions: a 4.5 MB file of
        120000 lines, edited on both sides of line 65535 (search, dd, x, yy
        and p, u, :set number, :100000, a :s range); each :w is compared.

tnylpo is TNYLPO (the path), else on the PATH: without it the tests are
skipped (exit status 0).

--host: the same suites for the host version (make host: llvm64, in a
terminal), with the keys piped to its stdin (it reads them as typed, and
ends when they do), the arrow keys as the terminal's escape sequences
(ANSI ESC [ A, VT52 ESC A; the file suites are ANSI).  There is no $ff mark: the screen compared is the one
before :q! clears it, less the status row (which shows :q!).
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'trs80'))
sys.path.insert(0, os.path.join(HERE, '..', 'vice'))
import edtest  # noqa: E402
import trstest  # noqa: E402  (the key file format, the case swap)
import termplay  # noqa: E402

TNYLPO = os.environ.get('TNYLPO') or shutil.which('tnylpo')
TIMEOUT = 120
TERMS = ['ansi', 'vt52', 'adm3a']
# the test build's key buffer (KEY_BUF_SIZE in src/cpm/platform.p8)
KEY_BUF_SIZE = 256
# the suites for CBM things (trstest's list): PETSCII and ASCII files, the
# C64's graphics keys, CBM DOS commands and drive prefixes, a full disk
CBM_ONLY = trstest.CBM_ONLY
ARGS = None     # the command line (main)


def text_file(text):
    """a suite's text as the CP/M text file: CR LF line endings"""
    return text.replace(b'\r\n', b'\n').replace(b'\r', b'\n').replace(b'\n', b'\r\n')


# (--host) the arrow keys as the terminal sends them: the suites' CBM codes
# become escape sequences, which p8vi reads back (txt.escape_key).  ADM-3A
# has none: there the codes go as they are.
ARROWS = {'ansi': {0x91: b'\x1b[A', 0x11: b'\x1b[B', 0x1d: b'\x1b[C', 0x9d: b'\x1b[D'},
          'vt52': {0x91: b'\x1bA', 0x11: b'\x1bB', 0x1d: b'\x1bC', 0x9d: b'\x1bD'},
          'adm3a': {}}


# (--host) the escape sequences themselves, typed as they are (and the
# terminal, -t, they are for): name, keys, files, text.  (the runtime
# decodes ANSI's arrows itself; Home, the page keys, F5 and VT52's arrows
# are p8vi's txt.escape_key)  F5 (ESC [ 15 ~)
# must be dropped (its 15~ would change the case of 15 characters); ESC
# then A on ANSI is a lone Escape and A (append), on VT52 the up arrow.
ARROW_TEXT = b'alpha beta gamma\n  second line here\nthird, with punct!\n\nfifth line'
HOST_SUITES = [
    ('ansi-keys', 'ansi', r'\x1b[B\x1b[B\x1b[C\x1b[Cx\x1b[Ax\x1b[Hx\x1b[15~\x1b[6~\x1b[5~gg\x1b[D'
                          r'ione\x1bAtwo\x1b:w q\n', [
        ('q', b'onealpha beta gammatwo\n econd line here\nthrd, with punct!\n\nfifth line'),
    ], ARROW_TEXT),
    ('vt52-keys', 'vt52', r'\x1bB\x1bB\x1bC\x1bCx\x1bAx\x1b[1~x\x1bDiz\x1b:w q\n', [
        ('q', b'alpha beta gamma\nz econd line here\nthrd, with punct!\n\nfifth line'),
    ], ARROW_TEXT),
]

# (number) name, text, keys: more screen suites for :set number.  The
# 100-character line takes 2 rows at 74 columns, and split at 73 still
# does: the rows after it stay where they were, with their numbers one
# higher (main.view.drawn_num).  Joined, the same the other way.
LONG_LINE = b'first\n' + b'a' * 100 + b'\nthird\nfourth\n'
NUMBER_SUITES = [
    ('split-same-rows', LONG_LINE, r'j073li\n\x1b'),
    ('join-same-rows', b'first\n' + b'a' * 73 + b'\n' + b'b' * 27 + b'\nthird\nfourth\n', 'jJ'),
    ('toggle-off', LONG_LINE, r'jx:set nonumber\nx'),
    ('page-down', b'b' * 300 + b'\nlast\n', r'\x06x'),
]

# (lines) range command, the normal-mode keys that do the same
LINES_PAIRS = [
    (r':2,4d\n', '2G3dd'),
    (r':3y\nGp', '3GyyGp'),
    (r':$d\n', 'Gdd'),
    (r'j:.,$d\n', 'j4dd'),
    (r':%d\n', 'gg5dd'),
    (r':%y\nGp', 'gg5yyGp'),
    (r':4,2d\n', ''),              # backwards: bad range, nothing changes
    (r':9d\n', ''),                # past the end
    (r':3,99d\n', '3G3dd'),        # stops at the last line
    (r'jj:d\n', 'jjdd'),
    (r'jj:y\nP', 'jjyyP'),
    (r':2,4d\nu', '2G3ddu'),       # undone (the cursor where the change was)
    (r':1,2y\n:5\np', '1G2yy5Gp'),
]


def as_typed(keys, term):
    return b''.join(ARROWS[term].get(k, bytes([k])) for k in keys)


def setup(args, prefix, text, keys, term='ansi'):
    """a directory with p8vi.com, t.txt and keys.txt, and a problem (None if
    the keys fit the test build's buffer)"""
    work = tempfile.mkdtemp(prefix=prefix, dir=args.work)
    if not args.host:
        shutil.copyfile(args.prg, os.path.join(work, 'p8vi.com'))
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(text_file(text))
    played = trstest.key_bytes(':e t.txt\\n' + keys + ':q!\\n')
    if args.host:
        played = as_typed(played, term)
    if len(played) > KEY_BUF_SIZE and not args.host:
        return work, f'{len(played)} bytes of keys, the test build holds {KEY_BUF_SIZE}'
    with open(os.path.join(work, 'keys.txt'), 'wb') as f:
        f.write(played)
    return work, None


def tnylpo(work, *options):
    """run p8vi in work: its console output, or None if it didn't end"""
    if ARGS.host:
        # (the host version: the keys on its stdin)
        path = os.path.join(work, 'keys.txt')
        with open(path, 'rb') as f:
            keys = f.read()
        os.remove(path)
        try:
            r = subprocess.run([ARGS.prg] + list(options), cwd=work, input=keys, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            return None
        return r.stdout
    try:
        r = subprocess.run([TNYLPO, '-b', 'p8vi'] + list(options), cwd=work, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return None
    return r.stdout


def run_files(args, suite, term='ansi'):
    name, keys, expected, *text = suite
    start = text[0] if text else edtest.SHORT
    swap = trstest.to_trs if not trstest.looks_ascii(start) else (lambda t: t)
    work, problem = setup(args, 'cpm-' + name + '-', swap(start), keys, term)
    if problem:
        return name, False, ['  ' + problem]
    lines = []
    if tnylpo(work, *(['-t', term] if term != 'ansi' else [])) is None:
        lines.append(f'  tnylpo did not finish in {TIMEOUT} s')
    for fname, want in expected:
        path = os.path.join(work, fname)
        got = None
        if os.path.exists(path):
            with open(path, 'rb') as f:
                got = f.read()
            got = trstest.lf_endings(got.split(b'\x1a')[0])
        if want is not None:
            want = trstest.lf_endings(want)
            want = trstest.to_trs(want) if (name, fname) in trstest.NEW_TEXTS else swap(want)
        if got != want:
            lines += [f'  {fname}: FAIL', f'    want {want!r}', f'    got  {got!r}']
    if lines:
        lines.append(f'  (files in {work})')
    else:
        shutil.rmtree(work)
    return name, not lines, lines


def screen_of(args, name, text, keys, term):
    """the screen after the keys on a terminal, or a problem (a string)"""
    if args.host:
        keys = keys.replace(r'\xff', '')
    work, problem = setup(args, f'cpms-{name}-{term}-', text, keys, term)
    if problem:
        return problem
    out = tnylpo(work, '-t', term)
    if out is None:
        return f'{term}: p8vi did not finish in {TIMEOUT} s (files in {work})'
    if args.host:
        # (the screen before :q! clears it; its status row shows :q!)
        out = termplay.before_quit(out, term)
    else:
        # (the screen when the suite's keys are done: the $ff key's mark)
        out = termplay.at_mark(out)
    if out is None:
        return f'{term}: the keys did not get to the end (files in {work})'
    try:
        scr, _ = termplay.play(out, term)
    except termplay.BadCode as e:
        return f'{term}: {e} (files in {work})'
    shutil.rmtree(work)
    return scr[:-1] if args.host else scr


def run_screen(args, suite):
    name, text, keys = suite
    text = trstest.to_trs(text)
    screens = {}
    lines = []
    for term in TERMS:
        for redraw in (False, True):
            scr = screen_of(args, name, text, keys + (r'\x0c' if redraw else '') + r'\xff', term)
            if isinstance(scr, str):
                return name, False, ['  ' + scr]
            screens[term, redraw] = scr
    base = screens['ansi', True]
    for (term, redraw), scr in screens.items():
        diff = [r for r in range(len(base)) if scr[r] != base[r]]
        if diff:
            what = f'{term}' + (' (redrawn)' if redraw else '') + ' differs from ansi (redrawn)'
            lines.append(f'  {what} in rows {diff[:8]}')
            for r in diff[:3]:
                lines += [f'    {r:2} want {base[r]!r}', f'    {r:2} got  {scr[r]!r}']
    return name, not lines, lines


def run_number(args, suite):
    name, text, keys = suite
    return run_screen(args, (name, text, r':set number\n' + keys))


def lines_text(args, keys):
    """the text after keys and an x, as :w wrote it"""
    work, problem = setup(args, 'cpml-', trstest.to_trs(edtest.SHORT), keys + r'x:w out\n')
    if problem:
        return problem
    tnylpo(work)
    path = os.path.join(work, 'out')
    if not os.path.exists(path):
        return f'no file written (files in {work})'
    with open(path, 'rb') as f:
        got = f.read().split(b'\x1a')[0]
    shutil.rmtree(work)
    return got


def run_lines(args, pair):
    a, b = pair
    got_a, got_b = lines_text(args, a), lines_text(args, b)
    ok = got_a == got_b and isinstance(got_a, bytes)
    lines = [] if ok else [f'  {a!r}: {got_a!r}', f'  {b!r}: {got_b!r}']
    return a, ok, lines


# (size, --host) the screen the terminal window's size, in a pty: name,
# the window's size at the start, the steps (keys to type, or a new
# window size), and the screen's size at the end; it must show the same
# as a run with -s of that size and the same keys, the size changes left
# out.  (pipe and clamp: not a pty)
SIZE_TEXT = b'\n'.join(b'line %02d ' % i + b'abcdefghij' * (i % 15) for i in range(1, 61)) + b'\n'
SIZE_CASES = [
    ('start', (100, 30), [b':e t.txt\r10Gx'], (100, 30)),
    # bigger, then a key: the screen is laid out again
    ('grow', (80, 24), [b':e t.txt\r10G', (120, 40), b'x'], (120, 40)),
    # bigger with no key after it: laid out again while waiting
    ('idle', (80, 24), [b':e t.txt\r10G', (120, 40)], (120, 40)),
    # smaller, with the cursor far down: the view scrolls to it
    ('shrink', (80, 24), [b':e t.txt\r20G', (50, 12), b'x'], (50, 12)),
    # in :set number
    ('number', (80, 24), [b':e t.txt\r:set nu\r3G', (132, 30), b'x'], (132, 30)),
    # bigger than the screen p8vi keeps: 250 x 200 of it
    ('huge', (300, 250), [b':e t.txt\rx'], (250, 200)),
    # stdout not a terminal: 80 x 24
    ('pipe', None, [b':e t.txt\r10Gx'], (80, 24)),
    # -s is kept within 20 x 4 and 250 x 200
    ('clamp', None, [b':e t.txt\rx'], (20, 4)),
]


def size_screen(args, name, options, keys, size):
    """the screen p8vi shows before it quits, keys piped in, or a problem
    (a string)"""
    work = tempfile.mkdtemp(prefix=f'cpmz-{name}-', dir=args.work)
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(SIZE_TEXT)
    try:
        r = subprocess.run([args.prg] + options, cwd=work, input=keys + b':q!\r', stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return f'did not finish in {TIMEOUT} s (files in {work})'
    return played(r.stdout, size, work)


def played(out, size, work):
    try:
        scr, _ = termplay.play(termplay.before_quit(out, 'ansi'), 'ansi', *size)
    except termplay.BadCode as e:
        return f'{e} (files in {work})'
    shutil.rmtree(work)
    return scr


def set_window(fd, cols, rows):
    import fcntl
    import struct
    import termios
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', rows, cols, 0, 0))


def pty_screen(args, name, window, steps, size):
    """(size) the screen p8vi shows before it quits, run in a pty of the
    window's size, or a problem"""
    import pty
    import select
    work = tempfile.mkdtemp(prefix=f'cpmz-{name}-', dir=args.work)
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(SIZE_TEXT)
    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(work)
        set_window(0, *window)
        os.execv(args.prg, [args.prg])
    out = bytearray()

    def settle(longest=5.0):
        """read the output until it stops for a while"""
        end = time.time() + longest
        quiet = time.time() + 0.4
        while time.time() < min(end, quiet):
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    return
                out.extend(data)
                quiet = time.time() + 0.4

    settle()
    for step in steps + [b':q!\r']:
        if isinstance(step, tuple):
            set_window(fd, *step)
        else:
            os.write(fd, step)
        settle()
    try:
        _, status = os.waitpid(pid, 0)
    finally:
        os.close(fd)
    return played(bytes(out), size, work)


def run_size(args, case):
    name, window, steps, (w, h) = case
    keys = b''.join(s for s in steps if isinstance(s, bytes))
    if name == 'clamp':
        # (played on 80 x 24: nothing past 20 columns and 4 rows)
        got = size_screen(args, name, ['-s', '1x1'], keys, (80, 24))
        ok = isinstance(got, list) and got[0] and all(len(r) <= w for r in got) and not any(got[h:])
        return name, ok, [] if ok else [f'  {got!r}']
    if window is None:
        got = size_screen(args, name, [], keys, (w, h))
    else:
        got = pty_screen(args, name, window, steps, (w, h))
    want = size_screen(args, name + '-ref', ['-s', f'{w}x{h}'], keys, (w, h))
    for scr in (got, want):
        if isinstance(scr, str):
            return name, False, ['  ' + scr]
    # (the status row: the pty's shows the keys' last command at times)
    diff = [r for r in range(h - 1) if got[r] != want[r]]
    lines = [f'  differs in rows {diff[:8]}'] if diff else []
    for r in diff[:3]:
        lines += [f'    {r:2} want {want[r]!r}', f'    {r:2} got  {got[r]!r}']
    return name, not lines, lines


def run_big(args, _):
    """(--host) the 32-bit positions on a big file"""
    import random
    work = tempfile.mkdtemp(prefix='cpmbig-', dir=args.work)
    random.seed(2)
    text = ('\n'.join(f'line {i:06d} ' + 'x' * random.randint(0, 50) for i in range(1, 120001)) + '\n').encode()
    with open(os.path.join(work, 'big.txt'), 'wb') as f:
        f.write(text)
    keys = (':e big.txt\r' 'G:w g1\r' '/line 100000\rdd:w g2\r' 'ggx:w g3\r' '5Gyy' 'Gp:w g4\r' 'u:w g5\r'
            ':100002\rdd:w g6\r' 'u:99998,100001s/line/LINE/\r:w g7\r' 'u:set number\r:99999\r' ':q!\r')
    try:
        r = subprocess.run([args.prg], cwd=work, input=keys.encode(), stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return 'big', False, [f'  did not finish in {TIMEOUT} s (files in {work})']
    lines = text.split(b'\n')        # lines[n - 1] is line n
    l2 = lines[:99999] + lines[100000:]
    l3 = [l2[0][1:]] + l2[1:]
    want = {'g1': lines, 'g2': l2, 'g3': l3, 'g4': l3[:-1] + [l3[4], b''], 'g5': l3,
            'g6': l3[:100001] + l3[100002:],
            'g7': l3[:99997] + [x.replace(b'line', b'LINE') for x in l3[99997:100001]] + l3[100001:]}
    problems = []
    for name, want_lines in want.items():
        path = os.path.join(work, name)
        got = open(path, 'rb').read() if os.path.exists(path) else None
        if got != b'\n'.join(want_lines):
            problems.append(f'  {name}: not the text it should be')
    scr, _ = termplay.play(termplay.before_quit(r.stdout, 'ansi'), 'ansi')
    if not any(row.startswith('   99999 line 099999 ') for row in scr):
        problems.append('  :set number: no row starts with line 99999 and its number')
    if problems:
        problems.append(f'  (files in {work})')
    else:
        shutil.rmtree(work)
    return 'big', not problems, problems


def main():
    ap = argparse.ArgumentParser(description='p8vi-cpm tests in tnylpo, or the host version\'s')
    ap.add_argument('kind', nargs='?', default='files', choices=['files', 'screen', 'number', 'lines', 'big', 'size'])
    ap.add_argument('names', nargs='*', help='only run these suites')
    ap.add_argument('--prg', help='the program (build/p8vi-cpmtest.com, with --host build/p8vi-host)')
    ap.add_argument('--host', action='store_true', help='the host version, the keys on its stdin')
    ap.add_argument('--work', default='build')
    ap.add_argument('-j', type=int, default=4)
    ap.add_argument('--skip', action='append', default=[], metavar='SUITE')
    args = ap.parse_args()
    global ARGS
    ARGS = args
    if not args.prg:
        args.prg = 'build/p8vi-host' if args.host else 'build/p8vi-cpmtest.com'
    if not TNYLPO and not args.host:
        print('tnylpo not found (set TNYLPO): the CP/M tests are skipped')
        return
    args.prg = os.path.abspath(args.prg)
    args.work = os.path.abspath(args.work)
    if args.kind == 'files':
        suites = [s for s in edtest.FILE_SUITES
                  if (not args.names or s[0] in args.names) and s[0] not in args.skip
                  and (args.names or s[0] not in CBM_ONLY)]
        run = run_files
        if args.host:
            # (and the escape sequences: HOST_SUITES)
            hosts = [(n, k, e, t) for n, term, k, e, t in HOST_SUITES if not args.names or n in args.names]
            terms = {n: term for n, term, *_ in HOST_SUITES}
            suites = [s for s in suites if s[0] not in terms] + hosts
            run = lambda a, s: run_files(a, s, terms.get(s[0], 'ansi'))
    elif args.kind == 'screen':
        suites = [s for s in edtest.SCREEN_SUITES
                  if (not args.names or s[0] in args.names) and s[0] not in args.skip]
        run = run_screen
    elif args.kind == 'number':
        suites = [s for s in edtest.SCREEN_SUITES + NUMBER_SUITES
                  if (not args.names or s[0] in args.names) and s[0] not in args.skip]
        run = run_number
    elif args.kind == 'lines':
        suites = LINES_PAIRS
        run = run_lines
    elif args.kind == 'size':
        if not args.host:
            sys.exit('size is for the host version (--host)')
        suites = [c for c in SIZE_CASES if not args.names or c[0] in args.names]
        run = run_size
    else:
        if not args.host:
            sys.exit('big is for the host version (--host)')
        suites = [None]
        run = run_big
    if not suites:
        sys.exit('no such suite')
    failed = 0
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        for name, ok, lines in pool.map(lambda s: run(args, s), suites):
            print(f'{name}: {"ok" if ok else "FAIL"}', flush=True)
            for line in lines:
                print(line)
            failed += not ok
    print(f'{"host " if args.host else ""}{args.kind}: {len(suites) - failed} of {len(suites)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
