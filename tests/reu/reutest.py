#!/usr/bin/env python3
"""REU tests in VICE (x64sc in the PATH), for src/c64/reu.p8.

detect: tests/reu/reudetect.p8 with every REU size and without an REU: the
        size found must be right and the REU's memory unchanged.
reset:  tests/reu/reureset.p8 writes a pattern into the REU, VICE is reset
        through its monitor (like the reset button), and the program, started
        again from a CBM80 hook in RAM, must find the pattern.

    python3 tests/reu/reutest.py [--build build] [detect] [reset]

The .prg files are built by "make test-reu".
"""

import argparse
import os
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'vice'))
import edtest  # noqa: E402  (its monitor client)

SIZES = [128, 256, 512, 1024, 2048, 4096, 8192, 16384]
EMU = ['x64sc', '-default', '-sounddev', 'dummy', '-warp', '-debugcart',
       '-autostartprgmode', '1']


def exit_code(log):
    m = re.search(r'DBGCART: exit\((\d+)\)', log)
    return int(m.group(1)) if m else None


def run_detect(args, size):
    reu = ['-reu', '-reusize', str(size)] if size else []
    out = subprocess.run(EMU + reu + ['-autostart', os.path.join(args.build, 'reudetect.prg'),
                                      '-limitcycles', '300000000'],
                         capture_output=True, text=True, errors='replace')
    got = exit_code(out.stdout + out.stderr)
    # 1 + log2 of the 64 KB banks, 0 without an REU
    want = (size // 64).bit_length() if size else 0
    name = f'{size} KB' if size else 'no REU'
    if got == want:
        return True, f'  {name}: ok'
    if got == 200:
        return False, f'  {name}: FAIL, the REU memory changed'
    return False, f'  {name}: FAIL, exit code {got}, want {want}'


def monitor(port, cmd):
    """One command to VICE's remote monitor (then "x"): the reply, or ''."""
    replies = edtest.monitor(port, [cmd], 5)
    return replies[0] if replies else ''


def run_reset(args):
    port = 6512
    log = open(os.path.join(args.build, 'reureset.log'), 'w')
    emu = subprocess.Popen(EMU + ['-reu', '-reusize', '512', '-remotemonitor',
                                  '-remotemonitoraddress', f'ip4://127.0.0.1:{port}',
                                  '-autostart', os.path.join(args.build, 'reureset.prg'),
                                  '-limitcycles', '2000000000'],
                           stdout=log, stderr=subprocess.STDOUT)
    try:
        # wait for "pattern written" (screen codes) at the top of the screen.
        # (not at once: stopping VICE in the monitor during its autostart
        # can stop the program from being started)
        time.sleep(5)
        written = bytes.fromhex('1001141405120e201712091414050e')
        end = time.time() + 60
        while time.time() < end:
            reply = monitor(port, 'm 0400 040e')
            m = re.search(r'>C:0400\s+((?:[0-9a-f]{2}\s+)+)', reply)
            if m and bytes.fromhex(m.group(1).replace(' ', '')) == written:
                break
            time.sleep(2)
        else:
            return False, '  reset: FAIL, the first run never finished'
        monitor(port, 'reset 0')
        emu.wait(timeout=60)
    except subprocess.TimeoutExpired:
        return False, '  reset: FAIL, the second run never finished'
    finally:
        if emu.poll() is None:
            emu.kill()
        log.close()
    got = exit_code(open(os.path.join(args.build, 'reureset.log'), errors='replace').read())
    if got == 0:
        return True, '  reset: ok, the REU kept its memory'
    return False, f'  reset: FAIL, exit code {got}'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--build', default='build')
    ap.add_argument('tests', nargs='*', default=['detect', 'reset'])
    args = ap.parse_args()
    results = []
    if 'detect' in args.tests:
        with ThreadPoolExecutor(4) as pool:
            results += pool.map(lambda size: run_detect(args, size), SIZES + [0])
    if 'reset' in args.tests:
        results.append(run_reset(args))
    for ok, line in results:
        print(line)
    failed = sum(not ok for ok, line in results)
    print(f'{len(results) - failed} of {len(results)} passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
