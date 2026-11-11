#!/usr/bin/env python3
"""The editor's tests for the CP/M version, in tnylpo (a CP/M 2.2 emulator
for the host: the files are the directory's).

    cpmtest.py files [--prg build/p8vi-cpmtest.com] [-j N] [--skip SUITE] [name...]
    cpmtest.py screen [-j N] [name...]
    cpmtest.py --host [files|screen] ...    (the host version, build/p8vi-host)

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

tnylpo is TNYLPO (the path), else on the PATH: without it the tests are
skipped (exit status 0).

--host: the same suites for the host version (make host: llvm64, in a
terminal), with the keys piped to its stdin (it reads them as typed, and
ends when they do).  There is no $ff mark: the screen compared is the one
before :q! clears it, less the status row (which shows :q!).
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


def setup(args, prefix, text, keys):
    """a directory with p8vi.com, t.txt and keys.txt, and a problem (None if
    the keys fit the test build's buffer)"""
    work = tempfile.mkdtemp(prefix=prefix, dir=args.work)
    if not args.host:
        shutil.copyfile(args.prg, os.path.join(work, 'p8vi.com'))
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(text_file(text))
    played = trstest.key_bytes(':e t.txt\\n' + keys + ':q!\\n')
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


def run_files(args, suite):
    name, keys, expected, *text = suite
    start = text[0] if text else edtest.SHORT
    swap = trstest.to_trs if not trstest.looks_ascii(start) else (lambda t: t)
    work, problem = setup(args, 'cpm-' + name + '-', swap(start), keys)
    if problem:
        return name, False, ['  ' + problem]
    lines = []
    if tnylpo(work) is None:
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
    work, problem = setup(args, f'cpms-{name}-{term}-', text, keys)
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


def main():
    ap = argparse.ArgumentParser(description='p8vi-cpm tests in tnylpo, or the host version\'s')
    ap.add_argument('kind', nargs='?', default='files', choices=['files', 'screen'])
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
    else:
        suites = [s for s in edtest.SCREEN_SUITES
                  if (not args.names or s[0] in args.names) and s[0] not in args.skip]
        run = run_screen
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
