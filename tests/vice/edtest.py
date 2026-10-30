#!/usr/bin/env python3
"""Editor tests on a C64 in VICE (x64sc with a true-drive 1541).

    edtest.py [--prg build/mainc64.prg] [--work build] [-j N] [files|screen] [name...]

files   (default) types vi commands at the editor, saves the text with
        ":w name" after each step, and compares the saved files with the
        expected text.
screen  types keys, dumps screen memory over the VICE remote monitor, does
        the same again with Ctrl-L (a full redraw) at the end, and compares
        the two screens.  Checks that partial redraws leave the screen right.

Every run gets its own disk image, so runs go in parallel.  A run that hits
the cycle limit hung.

Keys use VICE's -keybuf syntax: \\n is RETURN, \\xNN a PETSCII byte (\\x1b Esc,
\\xde pi for ~, \\xdd |, \\xa4 _).  Lowercase letters are PETSCII lowercase,
which is ASCII uppercase in a file, so test texts are in uppercase ASCII.
"""

import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))

SHORT = b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'
LONG = b'\n'.join(b'LINE %02d ' % i + b'ABCDEFGHIJ' * (i % 4) for i in range(1, 61))

# (name, keys, [(saved file, expected contents)]), all starting from SHORT
FILE_SUITES = [
    ('delete-put', r'dw:w a1\njdd:w a2\np:w a3\n1Gyyp:w a4\n', [
        ('a1', b'BETA GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('a2', b'BETA GAMMA\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('a3', b'BETA GAMMA\nTHIRD, WITH PUNCT!\n  SECOND LINE HERE\n\nFIFTH LINE'),
        ('a4', b'BETA GAMMA\nBETA GAMMA\nTHIRD, WITH PUNCT!\n  SECOND LINE HERE\n\nFIFTH LINE'),
    ]),
    ('change-find', r'wcwzzz\x1b:w b1\n$x0fzrq;x:w b2\njJ:w b3\n/fif\nD:w b4\n', [
        ('b1', b'ALPHA ZZZ GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('b2', b'ALPHA QZ GAMM\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('b3', b'ALPHA QZ GAMM\n  SECOND LINE HERE THIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('b4', b'ALPHA QZ GAMM\n  SECOND LINE HERE THIRD, WITH PUNCT!\n\n'),
    ]),
    ('edits', r'3x:w c1\nwde:w c2\n0yeP:w c3\njI--\x1bA!\x1bjonew\x1b:w c4\n1G\xde\xde\xde:w c5\n2G2dd:w c6\nGdd:w c7\n1GRab\x1b:w c8\n$Fmx:w c9\njSnope\x1b:w c10\n', [
        ('c1', b'HA BETA GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('c2', b'HA  GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('c3', b'HAHA  GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('c4', b'HAHA  GAMMA\n  --SECOND LINE HERE!\nTHIRD, WITH PUNCT!\nNEW\n\nFIFTH LINE'),
        ('c5', b'\xc8\xc1\xc8A  GAMMA\n  --SECOND LINE HERE!\nTHIRD, WITH PUNCT!\nNEW\n\nFIFTH LINE'),
        ('c6', b'\xc8\xc1\xc8A  GAMMA\nNEW\n\nFIFTH LINE'),
        ('c7', b'\xc8\xc1\xc8A  GAMMA\nNEW\n'),
        ('c8', b'AB\xc8A  GAMMA\nNEW\n'),
        ('c9', b'AB\xc8A  GAMA\nNEW\n'),
        ('c10', b'AB\xc8A  GAMA\nNOPE\n'),
    ]),
    ('operators', r'jjd2w:w d1\neX:w d2\n0tcx:w d3\nkyyjP:w d4\n?alp\nwcwx\x1b:w d5\nGdk:w d6\n1Gdj:w d7\n2p:w d8\n', [
        ('d1', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nWITH PUNCT!\n\nFIFTH LINE'),
        ('d2', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nWIH PUNCT!\n\nFIFTH LINE'),
        ('d3', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nWIH PUCT!\n\nFIFTH LINE'),
        ('d4', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\n  SECOND LINE HERE\nWIH PUCT!\n\nFIFTH LINE'),
        ('d5', b'ALPHA X GAMMA\n  SECOND LINE HERE\n  SECOND LINE HERE\nWIH PUCT!\n\nFIFTH LINE'),
        ('d6', b'ALPHA X GAMMA\n  SECOND LINE HERE\n  SECOND LINE HERE\nWIH PUCT!'),
        ('d7', b'  SECOND LINE HERE\nWIH PUCT!'),
        ('d8', b'  SECOND LINE HERE\nALPHA X GAMMA\n  SECOND LINE HERE\nALPHA X GAMMA\n  SECOND LINE HERE\nWIH PUCT!'),
    ]),
    ('undo', r'dwu:w u1\nu:w u2\nujddu:w u3\nihello\x1bu:w u4\noxyz\x1buu:w u5\n03xju:w u6\n', [
        ('u1', SHORT),
        ('u2', b'BETA GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('u3', SHORT),
        ('u4', SHORT),
        ('u5', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nXYZ\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('u6', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nXYZ\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
    ]),
    ('repeat', r'dw.:w p1\njwcwnew\x1bw.:w p2\nj0x3.:w p3\nu:w p4\nA!\x1bk.:w p5\n2Gd2w.:w p6\n3Gd2w1.:w p7\nyw.:w p8\n', [
        ('p1', b'GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('p2', b'GAMMA\n  NEW NEW HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('p3', b'GAMMA\n  NEW NEW HERE\nD, WITH PUNCT!\n\nFIFTH LINE'),
        ('p4', b'GAMMA\n  NEW NEW HERE\nHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('p5', b'GAMMA\n  NEW NEW HERE!\nHIRD, WITH PUNCT!!\n\nFIFTH LINE'),
        ('p6', b'GAMMA\n  \nHIRD, WITH PUNCT!!\n\nFIFTH LINE'),
        ('p7', b'GAMMA\n  \nPUNCT!!\n\nFIFTH LINE'),
        ('p8', b'GAMMA\n  \n!!\n\nFIFTH LINE'),
    ]),
    ('repeat-arrows', r'Gi12\x1d\x1dab\x1b0.:w q1\n', [
        ('q1', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nAB12FIABFTH LINE'),
    ]),
    ('g-cmds', r'Gggdw3ggx$gex:w g3\n2G>><j1GgJ:w g6\n1G$\xa4x5\xddx:w g8\nGo(a[b]c)\x1b0%x0f[%x4Gw*D:w g11\n3ia\x1b2ox\x1bAone two\x17\x15zz\x1b:w g14\n', [
        ('g3', b'BETA GAMMA\n  SECOND LINE HERE\nHIRD, WITH PUNC!\n\nFIFTH LINE'),
        ('g6', b'BETA GAMMA  SECOND LINE HERE\nHIRD, WITH PUNC!\n\nFIFTH LINE'),
        ('g8', b'ETA AMMA  SECOND LINE HERE\nHIRD, WITH PUNC!\n\nFIFTH LINE'),
        ('g11', b'ETA AMMA  SECOND \nHIRD, WITH PUNC!\n\nFIFTH LINE\n(A[BC'),
        ('g14', b'ETA AMMA  SECONDAAA \nX\nXZZ\nHIRD, WITH PUNC!\n\nFIFTH LINE\n(A[BC'),
    ]),
    ('indent', r'2G>>:w h1\n3G>>k<<:w h2\n4Gdgg:w h3\nyypw#x:w h4\njyy2p:w h5\n', [
        ('h1', b'ALPHA BETA GAMMA\n      SECOND LINE HERE\nTHIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('h2', b'ALPHA BETA GAMMA\n  SECOND LINE HERE\n    THIRD, WITH PUNCT!\n\nFIFTH LINE'),
        ('h3', b'FIFTH LINE'),
        ('h4', b'FIFTH INE\nFIFTH LINE'),
        ('h5', b'FIFTH INE\nFIFTH LINE\nFIFTH LINE\nFIFTH LINE'),
    ]),
]

# (name, text, keys)
SCREEN_SUITES = [
    ('x', SHORT, r'x'),
    ('mixed', SHORT, r'A and some more text to wrap past the edge\x1bjJ3Gddoa new line\x1b1G>>j$xup'),
    ('wrap-insert', SHORT, r'jjIone two three four five six seven eight\x1b'),
    ('dd-end', SHORT, r'G2ddkdd'),
    ('replace-indent', SHORT, r'Rxyz\x1bj2>>'),
    ('undo-lines', SHORT, r'Gofoo\nbar\x1buu'),
    ('wrap-twice', SHORT, r'jA this is long enough to wrap and wrap again past the edge of the row\x1b0x'),
    ('long-dd-last', LONG, r'Gdd'),
    ('long-dd-mid', LONG, r'30Gdd'),
    ('long-insert', LONG, r'30Giinserted words here\x1b'),
    ('long-page', LONG, r'\x06x'),
    ('long-join', LONG, r'40GJ'),
    ('long-dG', LONG, r'G3kdG'),
]

EMU = ['x64sc', '-default', '-sounddev', 'dummy', '-warp', '+autostart-warp',
       '-drive8type', '1541']


def make_disk(d64, prg, text):
    txt = d64 + '.txt'
    with open(txt, 'wb') as f:
        f.write(text)
    subprocess.run(['c1541', '-format', 'test,52', 'd64', d64, '-attach', d64,
                    '-write', prg, 'main,p', '-write', txt, 't.txt,s'],
                   check=True, capture_output=True)


def run_files(args, suite):
    name, keys, expected = suite
    base = os.path.join(args.work, 'vt-' + name)
    d64 = base + '.d64'
    make_disk(d64, args.prg, SHORT)
    # :q! back to BASIC, then a write to $d7ff (the -debugcart) quits VICE
    keybuf = ':e t.txt\\n' + keys + ':q!\\npoke 55295,0\\n'
    with open(base + '.log', 'wb') as log:
        subprocess.run(EMU + ['-debugcart', '-8', d64, '-autostart', d64,
                              '-keybuf', keybuf, '-limitcycles', str(args.limit),
                              '-exitscreenshot', base + '.png'],
                       stdout=log, stderr=subprocess.STDOUT, cwd=args.work)
    lines = []
    ok = True
    if b'cycle limit' in open(base + '.log', 'rb').read():
        ok = False
        lines.append('  hung: hit the cycle limit')
    for fname, want in expected:
        out = base + '_' + fname
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(['c1541', '-attach', d64, '-read', fname + ',s', out],
                       capture_output=True)
        got = open(out, 'rb').read() if os.path.exists(out) else None
        if got != want:
            ok = False
            lines.append(f'  {fname}: FAIL\n    want {want!r}\n    got  {got!r}')
    return name, ok, lines


def monitor(port, cmds, timeout):
    """Connect to VICE's remote monitor, send the commands one at a time, then
    "x" to let the emulator run on.  Returns the list of replies, or None."""
    end = time.time() + timeout
    while True:
        try:
            s = socket.create_connection(('127.0.0.1', port), timeout=2)
            break
        except OSError:
            if time.time() > end:
                return None
            time.sleep(0.5)
    def until_prompt():
        # a reply ends with the next prompt, "(C:$xxxx) "
        reply = b''
        # entering the monitor sends a prompt of its own first
        while not re.search(rb'\S.*\(C:\$[0-9a-f]{4}\) $', reply, re.S) or \
                re.fullmatch(rb'\(C:\$[0-9a-f]{4}\) ', reply):
            try:
                d = s.recv(65536)
            except socket.timeout:
                if time.time() > end + 30:
                    return None
                continue
            if not d:
                return None
            reply += d
        return reply.decode('latin-1')

    replies = []
    with s:
        s.settimeout(0.5)
        for cmd in cmds:
            s.sendall((cmd + '\n').encode())
            reply = until_prompt()
            if reply is None:
                return None
            replies.append(reply)
        s.sendall(b'x\n')
        time.sleep(0.2)
    return replies


def screen_bytes(reply):
    b = bytearray()
    for line in reply.splitlines():
        m = re.match(r'.*>C:([0-9a-f]{4})\s+((?:[0-9a-f]{2}\s+)+)', line)
        if m:
            b += bytes.fromhex(m.group(2).replace(' ', ''))
    return bytes(b[:1000])


def screen_after(args, base, port, text, keys):
    """Type keys, let the emulator run args.cycles cycles, dump the screen."""
    d64 = base + '.d64'
    make_disk(d64, args.prg, text)
    with open(base + '.log', 'wb') as log:
        p = subprocess.Popen(EMU + ['-remotemonitor', '-remotemonitoraddress',
                                    f'ip4://127.0.0.1:{port}', '-8', d64,
                                    '-autostart', d64, '-keybuf', ':e t.txt\\n' + keys,
                                    '-limitcycles', '40000000000'],
                             stdout=log, stderr=subprocess.STDOUT, cwd=args.work)
    try:
        # wait in emulated time, so a busy host can't cut the run short
        deadline = time.time() + 600
        while time.time() < deadline:
            time.sleep(1)
            reply = monitor(port, ['sw'], 10)
            if reply is None:
                return None
            m = re.search(r'Stopwatch:\s+(\d+)', reply[0])
            if m and int(m.group(1)) >= args.cycles:
                reply = monitor(port, ['m 0400 07e7'], 10)
                return screen_bytes(reply[0]) if reply else None
        return None
    finally:
        p.kill()
        p.wait()


def run_screen(args, job):
    i, (name, text, keys) = job
    base = os.path.join(args.work, 'vs-' + name)
    port = args.port + 2 * i
    a = screen_after(args, base + '-a', port, text, keys)
    b = screen_after(args, base + '-b', port + 1, text, keys + r'\x0c')
    if a is None or b is None or len(a) != 1000 or len(b) != 1000:
        return name, False, ['  no screen dump (VICE monitor did not answer)']
    # both must be the editor in nav mode, which shows "line,col" in the
    # status row, or the run didn't get through its keys
    for scr in (a, b):
        status = bytes(c & 0x7f for c in scr[960:])
        if not re.search(rb'[0-9],[0-9]', status):
            return name, False, ['  the editor is not on the screen (raise --cycles?)']
    # bit 7 is the reverse-video cursor
    diff = [i for i in range(1000) if (a[i] ^ b[i]) & 0x7f]
    lines = [f'  row {i // 40} col {i % 40}: partial {a[i]:02x} full {b[i]:02x}'
             for i in diff[:10]]
    if diff:
        lines.insert(0, f'  {len(diff)} cells differ from a full redraw')
    return name, not diff, lines


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('kind', nargs='?', default='files', choices=['files', 'screen'])
    ap.add_argument('names', nargs='*', help='only run these suites')
    ap.add_argument('--prg', default='build/mainc64.prg')
    ap.add_argument('--work', default='build')
    ap.add_argument('-j', type=int, default=os.cpu_count() or 4)
    ap.add_argument('--limit', type=int, default=800_000_000, help='cycle limit per run')
    ap.add_argument('--port', type=int, default=6600, help='first remote monitor port')
    ap.add_argument('--cycles', type=int, default=150_000_000,
                    help='cycles a screen run gets to finish its keys')
    args = ap.parse_args()
    for tool in ('x64sc', 'c1541'):
        if not shutil.which(tool):
            sys.exit(f'{tool} (VICE) not found in PATH')
    args.prg = os.path.abspath(args.prg)
    args.work = os.path.abspath(args.work)
    os.makedirs(args.work, exist_ok=True)

    if args.kind == 'files':
        suites = [s for s in FILE_SUITES if not args.names or s[0] in args.names]
        work = lambda s: run_files(args, s)
    else:
        suites = list(enumerate(s for s in SCREEN_SUITES if not args.names or s[0] in args.names))
        work = lambda s: run_screen(args, s)
    if not suites:
        sys.exit('no such suite')

    failed = 0
    with ThreadPoolExecutor(max_workers=args.j) as pool:
        for name, ok, lines in pool.map(work, suites):
            print(f'{name}: {"ok" if ok else "FAIL"}')
            for line in lines:
                print(line)
            failed += not ok
    print(f'{args.kind}: {len(suites) - failed} of {len(suites)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
