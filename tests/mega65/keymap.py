#!/usr/bin/env python3
"""Measure which key presses give which PETSCII codes on a MEGA65.

    keymap.py [--prg build/keyecho.prg] [--device /dev/cu.usbserial-...] [--json out.json]

Runs tests/mega65/keyecho.p8 (make test-mega65-keymap builds it), presses
every keyboard matrix position alone and with shift, ctrl and MEGA through
the virtual key slots at $D615, and reads what the KERNAL's GETIN gave from
keyecho's buffer.  Prints the PETSCII table of tools/m65harness.py: for each
code the key and modifier that give it, the key alone first, then ctrl,
shift and MEGA.

In Xemu by default; --device uses a real MEGA65 over its serial monitor,
with keyecho already running on it.
"""

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
import m65harness as h  # noqa: E402

COUNT, READY, KEYS = 0x7000, 0x7001, 0x7100
MODS = {'': h.NO_KEY, 'ctrl': h.CTRL, 'shift': h.SHIFT, 'mega': h.MEGA}
MODIFIERS = {0x0F, 0x34, 0x3A, 0x3D}    # left shift, right shift, ctrl, MEGA


def combinations():
    for code in range(0x00, 0x48):
        if code in MODIFIERS:
            continue
        for name in MODS:
            # $40 and up only alone or with shift: MEGA with TAB opens the
            # matrix mode debugger, and some other modifier with $40/$41
            # stopped all keys from $42 up
            if code >= 0x40 and name not in ('', 'shift'):
                continue
            yield code, name


def measure(m):
    deadline = time.time() + 30
    while m.read(READY, 1)[0] != 0xA5:
        if time.time() > deadline:
            raise h.Failure('keyecho never started')
        time.sleep(0.1)
    found = {}
    for code, name in combinations():
        before = m.read(COUNT, 1)[0]
        m._press_code(code, MODS[name])
        got = []
        end = time.time() + 0.6
        while time.time() < end:
            if m.read(COUNT, 1)[0] != before:
                time.sleep(0.15)        # a key can give several codes
                n = (m.read(COUNT, 1)[0] - before) & 0xFF
                keys = m.read(KEYS, 256)
                got = [keys[(before + i) & 0xFF] for i in range(n)]
                break
            time.sleep(0.05)
        found[(code, name)] = got
        print(f'{code:02x} {name:5s} {" ".join("%02x" % g for g in got)}', file=sys.stderr, flush=True)
    return found


def table(found):
    best = {}
    for mod in MODS:
        for (code, name), got in sorted(found.items()):
            if name == mod and len(got) == 1 and got[0] not in best:
                best[got[0]] = (code, mod)
    names = {'': 'NO_KEY', 'ctrl': 'CTRL', 'shift': 'SHIFT', 'mega': 'MEGA'}
    items = [f'0x{p:02X}: (0x{c:02X}, {names[m]})' for p, (c, m) in sorted(best.items())]
    return '\n'.join('    ' + ', '.join(items[i:i + 4]) + ',' for i in range(0, len(items), 4))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--prg', default='build/keyecho.prg')
    ap.add_argument('--emulator', default='xmega65')
    ap.add_argument('--device', help='a real MEGA65 serial port, keyecho running')
    ap.add_argument('--json', help='also save every measurement here')
    args = ap.parse_args()
    try:
        if args.device:
            with h.attach(args.device) as m:
                found = measure(m)
        else:
            with h.launch(args.emulator, args.prg, prgmode='65') as m:
                found = measure(m)
    except h.Failure as failed:
        sys.exit(h.report_failure(failed))
    if args.json:
        with open(args.json, 'w') as f:
            json.dump({f'{c:02x}{"+" + n if n else ""}': g for (c, n), g in found.items()}, f, indent=0)
    print(table(found))


if __name__ == '__main__':
    main()
