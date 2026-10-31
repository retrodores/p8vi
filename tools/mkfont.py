#!/usr/bin/env python3
"""Make p8vi.fnt, the font of the C64 font build (src/c64/font.p8): a
2 KB character set as a PRG file with load address $f800.

    python3 tools/mkfont.py FONT OUT

FONT is the character set as `.byte` lines (64tass or a Prog8 %asm
block, the first 2048 bytes are used), or a binary file: 2048 bytes, or
2050 with a load address in front (a .64c file).
"""
import re
import sys

SIZE = 2048
LOAD = 0xf800


def read_font(path):
    data = open(path, 'rb').read()
    if len(data) in (SIZE, SIZE + 2) and not data[:SIZE].isascii():
        return data[-SIZE:]
    out = []
    for line in data.decode(errors='replace').splitlines():
        m = re.match(r'\s*(?:\w+\s+)?\.byte\s+(.*?)\s*(;.*)?$', line)
        if not m:
            continue
        for v in m.group(1).split(','):
            v = v.strip()
            out.append(int(v[1:], 16) if v.startswith('$') else
                       int(v[1:], 2) if v.startswith('%') else int(v))
    if len(out) < SIZE:
        sys.exit(f'{path}: {len(out)} bytes of font, need {SIZE}')
    return bytes(out[:SIZE])


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    font = read_font(sys.argv[1])
    with open(sys.argv[2], 'wb') as f:
        f.write(bytes([LOAD & 0xff, LOAD >> 8]) + font)


if __name__ == '__main__':
    main()
