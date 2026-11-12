#!/usr/bin/env python3
"""Make p8vi's Workbench icons: .info files in the classic (Kickstart 1.3)
format, which every Workbench reads.

    mkicon.py tool OUT.info                    p8vi's own icon (a tool)
    mkicon.py project OUT.info TOOL            a text file's icon, opened with TOOL

The format (big endian, the ROM Kernel Manual's DiskObject):

  DiskObject   78 bytes: magic $E310, version 1, a Gadget (its size, the
               image's flag, GadgetRender non-zero: an image follows), the
               type (3 tool, 4 project), the default tool and tool types
               (non-zero: they follow), no position, the stack size
  Image        20 bytes: size, depth 2, ImageData non-zero, PlanePick 3
  image data   2 bitplanes, each row a whole number of 16-bit words
  default tool (projects) a long, the length with its 0, then the string

The picture is 2 bitplanes in Workbench 1.3's colors: 0 the background
(blue), 1 white, 2 black, 3 orange.  p8vi's: a small terminal with "vi"
on its screen; the project icon: a page with lines of text.
"""

import struct
import sys

# the pictures, a character per pixel: . background, W white, B black, O orange
TOOL = """
..WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW....
..WBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WBBOOBBBBBOOBBOOBBBBBBBBBBBBBBBBBW....
..WBBOOBBBBBOOBBBBBBBBBBBBBBBBBBBBBW....
..WBBBOOBBBOOBBBOOBBBBBBBBBBBBBBBBBW....
..WBBBOOBBBOOBBBOOBBBBBBBBBBBBBBBBBW....
..WBBBBOOBOOBBBBOOBBBBBBBBBBBBBBBBBW....
..WBBBBOOBOOBBBBOOBBBBBBBBBBBBBBBBBW....
..WBBBBBOOOBBBBBOOBBBBBBBBBBBBBBBBBW....
..WBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WBBWWWWWWWBBWWWWWBBBWWWWWWWWBBBBBW....
..WBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WBBWWWWBBBWWWWWWWWWWBBWWWWWBBBBBBW....
..WBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WBBOOBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBW....
..WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW....
............WWWWWWWWWWWW................
.......WWWWWWWWWWWWWWWWWWWWWW...........
"""

PROJECT = """
....WWWWWWWWWWWWWWWWWWWWWW......
....WBBBBBBBBBBBBBBBBBBBBBWW....
....WBWWWWWWWWWWWWWWWWWWWBWBW...
....WBWBBBBBBBBWBBBBBBWWWBWWBW..
....WBWWWWWWWWWWWWWWWWWWWBBBBBW.
....WBWBBBBBWBBBBBBBBBBBWWWWWBW.
....WBWWWWWWWWWWWWWWWWWWWWWWWBW.
....WBWBBBBBBBBBBWBBBBBBBBBWWBW.
....WBWWWWWWWWWWWWWWWWWWWWWWWBW.
....WBWBBBBBBWBBBBBBBBWWWWWWWBW.
....WBWWWWWWWWWWWWWWWWWWWWWWWBW.
....WBWBBBBBBBBBBBBWBBBBBBWWWBW.
....WBWWWWWWWWWWWWWWWWWWWWWWWBW.
....WBWBBBBBWBBBBBBBBBBBBWWWWBW.
....WBWWWWWWWWWWWWWWWWWWWWWWWBW.
....WBBBBBBBBBBBBBBBBBBBBBBBBBW.
....WWWWWWWWWWWWWWWWWWWWWWWWWWW.
"""

COLORS = {'.': 0, 'W': 1, 'B': 2, 'O': 3}
WBTOOL = 3
WBPROJECT = 4
NO_ICON_POSITION = 0x80000000
STACK = 8192


def bitplanes(picture):
    rows = [r for r in picture.strip('\n').split('\n')]
    width = max(len(r) for r in rows)
    height = len(rows)
    words = (width + 15) // 16
    planes = []
    for plane in range(2):
        data = bytearray()
        for r in rows:
            bits = 0
            for x in range(words * 16):
                c = COLORS[r[x]] if x < len(r) else 0
                bits = (bits << 1) | ((c >> plane) & 1)
            data += bits.to_bytes(words * 2, 'big')
        planes.append(bytes(data))
    return width, height, b''.join(planes)


def info(kind, default_tool=None):
    width, height, data = bitplanes(TOOL if kind == WBTOOL else PROJECT)
    gadget = struct.pack('>IhhhhHHHIIIiIHI',
                         0,                         # NextGadget
                         0, 0, width, height + 1,   # LeftEdge, TopEdge, Width, Height
                         0x0005,                    # Flags: GADGIMAGE | GADGHBOX
                         0x0003,                    # Activation: RELVERIFY | GADGIMMEDIATE
                         0x0001,                    # GadgetType: BOOLGADGET
                         1,                         # GadgetRender: an image follows
                         0, 0, 0, 0,                # SelectRender, GadgetText, MutualExclude, SpecialInfo
                         0,                         # GadgetID
                         1)                         # UserData: the icon revision (WB_DISKREVISION)
    disk = struct.pack('>HH', 0xE310, 1) + gadget + struct.pack(
        '>BBIIiiIII', kind, 0,
        1 if default_tool else 0,                   # DefaultTool: a string follows
        0,                                          # ToolTypes: none
        NO_ICON_POSITION - (1 << 32), NO_ICON_POSITION - (1 << 32),
        0, 0,                                       # DrawerData, ToolWindow
        STACK)
    assert len(disk) == 78, len(disk)
    image = struct.pack('>hhhhhIBBI', 0, 0, width, height, 2, 1, 3, 0, 0)
    assert len(image) == 20
    out = disk + image + data
    if default_tool:
        s = default_tool.encode('latin-1') + b'\0'
        out += struct.pack('>I', len(s)) + s
    return out


def main(argv):
    if len(argv) == 2 and argv[0] == 'tool':
        data = info(WBTOOL)
    elif len(argv) == 3 and argv[0] == 'project':
        data = info(WBPROJECT, argv[2])
    else:
        sys.exit(__doc__)
    with open(argv[1], 'wb') as f:
        f.write(data)


if __name__ == '__main__':
    main(sys.argv[1:])
