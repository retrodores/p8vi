#!/usr/bin/env python3
"""How long one line of scrolling takes in the editor (j at the bottom of
the screen), in C64 cycles, in VICE: load a 100 line file, go down 22
lines to the bottom row, reset the monitor's stopwatch, go down 60 more
(each one scrolls) and read it.  Typing the keys is part of it.

    python3 tests/bench/viewbench.py --prg build/p8vi-c64.prg [--reu]
"""

import argparse
import os
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'vice'))
import edtest  # noqa: E402
import rectest  # noqa: E402

TEXT = b''.join(b'LINE %03d OF THE TEXT, ABCDEFGHIJKLMNOPQRS\n' % i for i in range(100))
SCROLLS = 60


def wait_line(port, addr, line):
    end = time.time() + 120
    while time.time() < end:
        if rectest.peekw(port, addr) == line:
            return
        time.sleep(0.1)
    sys.exit(f'cursor never got to line {line}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--prg', default='build/p8vi-c64.prg')
    ap.add_argument('--work', default='build')
    ap.add_argument('--reu', action='store_true')
    ap.add_argument('--port', type=int, default=6650)
    ap.add_argument('--profile', metavar='LABELS', help="VICE's profile of the scrolling (a .vice-mon-list of the same build)")
    args = ap.parse_args()
    prg = os.path.abspath(args.prg)
    work = os.path.abspath(args.work)
    d64 = os.path.join(work, 'vb.d64')
    edtest.make_disk(d64, prg, TEXT)
    cur_line = rectest.symbol(os.path.splitext(prg)[0] + '.list', 'main.cur_line')
    port = args.port
    reu = ['-reu', '-reusize', '512'] if args.reu else []
    # (not in warp: the stopwatch is read after polling, which must not
    # count for much emulated time)
    emu = subprocess.Popen(edtest.EMU + reu + ['+warp', '-remotemonitor', '-remotemonitoraddress', f'ip4://127.0.0.1:{port}',
                                               '-8', d64, '-autostart', d64, '-keybuf', ':e t.txt\\n',
                                               '-limitcycles', '4000000000'],
                           stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, cwd=work)
    try:
        # (not into the monitor during the autostart: the program would not
        # start) then wait for the editor's status line ("t.txt ...")
        time.sleep(15)
        end = time.time() + 120
        while time.time() < end:
            reply = edtest.monitor(port, ['m 07c0 07c4'], 10)
            if reply and '142e141814' in reply[0].replace(' ', ''):
                break
            time.sleep(2)
        else:
            sys.exit('the editor never loaded t.txt')
        edtest.monitor(port, ['keybuf ' + 'j' * 22], 10)
        wait_line(port, cur_line, 22)
        time.sleep(1)
        start = ['sw reset']
        if args.profile:
            start = ['ll "' + os.path.abspath(args.profile) + '"', 'prof on'] + start
        edtest.monitor(port, start + ['keybuf ' + 'j' * SCROLLS], 30)
        wait_line(port, cur_line, 22 + SCROLLS)
        reply = edtest.monitor(port, ['sw'], 10)
        if args.profile:
            print(edtest.monitor(port, ['prof off', 'prof flat 30'], 30)[1])
    finally:
        emu.kill()
    # (read a little after the last key: at most the polling interval more)
    m = re.search(r'Stopwatch:\s+(\d+)', reply[0]) if reply else None
    if not m:
        sys.exit('no stopwatch reading')
    per = int(m.group(1)) / SCROLLS
    print(f'{os.path.basename(prg)}: one line of scrolling about {per:.0f} cycles ({per / 985248 * 1000:.0f} ms)')


if __name__ == '__main__':
    main()
