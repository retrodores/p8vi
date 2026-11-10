#!/usr/bin/env python3
"""p8vi-cpm on a TRS-80 Model 4 with Montezuma Micro CP/M 2.2, in trs80gp:
a smoke test of the real thing (tests/cpm/cpmtest.py runs the suites in
tnylpo).

    m4test.py [--disk build/cpm222_work.dsk] [--prg build/p8vi-cpm.com]

It needs the CP/M system disk (a DMK image of Montezuma's 170K SSDD disk:
CPM_DISK, else build/cpm222_work.dsk), trs80gp and cpmtools; without any
of them it is skipped (exit status 0).  The disk is not changed: a copy gets
p8vi.com and t.txt (tools/cpm/dmk.py and cpmcp; MBASIC.COM, ASM.COM and
DUMP.ASM are deleted from the copy for room), trs80gp boots it, and types
on its keyboard matrix (-ik: its paste never ends once a program polls the
keyboard):

  CAPS (Montezuma gives capitals until it is pressed), p8vi -t adm3a,
  :e t.txt, a pause (keys typed while the floppy is read are lost),
  j i "added " BREAK (Montezuma's Escape) :w, then the screen is dumped

The screen must be p8vi's (the text, ~ rows, the status line after :w),
and t.txt, read back off the disk, the edited text with CR LF and ^Z.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.join(HERE, '..', '..', 'tools', 'cpm')
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.join(HERE, '..', 'trs80'))
import dmk  # noqa: E402
import trstest  # noqa: E402  (trs80gp's path)

TIMEOUT = 300
TEXT = b'hello from the host\r\nsecond line\r\n\x1a'
WANT = b'hello from the host\r\nadded second line\r\n'
# room on the system disk (it's full)
DELETE = ['mbasic.com', 'asm.com', 'dump.asm']

# the keyboard matrix: row, bit for each key typed here
ROWS = ['@abcdefg', 'hijklmno', 'pqrstuvw', 'xyz', '01234567', '89:;,-./']
SPECIAL = {'\n': (6, 0x01), ' ': (6, 0x80), '\x1b': (6, 0x04)}   # ENTER, space, BREAK
CAPS = (7, 0x08)


def press(row, mask, hold=15, gap=15):
    return ['-ik', str(row), '%x' % mask, '-id', str(hold), '-ik', str(row), '0', '-id', str(gap)]


def typed(text):
    out = []
    for c in text:
        if c == '|':
            out += ['-id', '600']        # 10 s
            continue
        if c in SPECIAL:
            out += press(*SPECIAL[c])
            continue
        for r, keys in enumerate(ROWS):
            if c in keys:
                out += press(r, 1 << keys.index(c))
                break
        else:
            raise ValueError(f'no key for {c!r}')
    return out


def cpmtools(work, *args):
    return subprocess.run(list(args), cwd=work, capture_output=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--disk', default=os.environ.get('CPM_DISK', 'build/cpm222_work.dsk'))
    ap.add_argument('--prg', default='build/p8vi-cpm.com')
    ap.add_argument('--work', default='build')
    args = ap.parse_args()
    missing = [what for what, ok in [(args.disk, os.path.exists(args.disk)),
                                     ('trs80gp', os.path.exists(trstest.TRS80GP)),
                                     ('cpmtools', shutil.which('cpmcp'))] if not ok]
    if missing:
        print(f'Montezuma CP/M test skipped: no {", ".join(missing)}')
        return
    work = tempfile.mkdtemp(prefix='cpm-m4-', dir=os.path.abspath(args.work))
    shutil.copyfile(os.path.join(TOOLS, 'diskdefs'), os.path.join(work, 'diskdefs'))
    shutil.copyfile(args.prg, os.path.join(work, 'p8vi.com'))
    with open(os.path.join(work, 't.txt'), 'wb') as f:
        f.write(TEXT)
    disk = os.path.join(work, 'd0.dsk')
    shutil.copyfile(args.disk, disk)
    d = dmk.Dmk(disk)
    with open(os.path.join(work, 'd0.raw'), 'wb') as f:
        f.write(d.raw())
    cpmtools(work, 'cpmrm', '-f', 'mm4ss', 'd0.raw', *['0:' + n for n in DELETE])
    r = cpmtools(work, 'cpmcp', '-f', 'mm4ss', 'd0.raw', 'p8vi.com', 't.txt', '0:')
    if r.returncode != 0:
        sys.exit(f'cpmcp failed: {r.stderr.decode().strip()} (files in {work})')
    d.put_raw(open(os.path.join(work, 'd0.raw'), 'rb').read())

    keys = (['-id', '1500'] + press(*CAPS) + typed('p8vi -t adm3a\n|:e t.txt\n|jiadded \x1b:w\n') +
            ['-id', '1500', '-it', '-ix'])
    command = [trstest.TRS80GP, '-ee', '-batch', '-turbo', '-m4', '-mem', '64', '-d0', 'd0.dsk',
               '-itime', '0'] + keys
    lines = []
    try:
        subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        lines.append(f'  trs80gp did not finish in {TIMEOUT} s')
    screen = []
    path = os.path.join(work, 'trs80-text-0.bin')
    if os.path.exists(path):
        s = open(path, 'rb').read()
        # (bit 7: the cursor's character shows in reverse)
        screen = [bytes(b & 0x7f for b in s[i:i + 80]).decode('latin1').rstrip('\0 ')
                  for i in range(0, 24 * 80, 80)]
    if not (len(screen) == 24 and screen[0] == 'hello from the host' and screen[1] == 'added second line'
            and screen[2] == '~' and screen[23].startswith('t.txt ')):
        lines.append('  the screen is not p8vi\'s after the edit:')
        lines += [f'    {n:2}|{row}' for n, row in enumerate(screen) if row]
    with open(os.path.join(work, 'after.raw'), 'wb') as f:
        f.write(dmk.Dmk(disk).raw())
    cpmtools(work, 'cpmcp', '-f', 'mm4ss', 'after.raw', '0:t.txt', 'after.txt')
    got = None
    if os.path.exists(os.path.join(work, 'after.txt')):
        got = open(os.path.join(work, 'after.txt'), 'rb').read().split(b'\x1a')[0]
    if got != WANT:
        lines += ['  t.txt on the disk:', f'    want {WANT!r}', f'    got  {got!r}']
    print(f'Montezuma CP/M: {"ok" if not lines else "FAIL"}')
    for line in lines:
        print(line)
    if lines:
        print(f'  (files in {work})')
        sys.exit(1)
    shutil.rmtree(work)


if __name__ == '__main__':
    main()
