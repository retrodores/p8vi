"""Play p8vi-cpm's terminal output back on an 80 x 24 screen, for the
terminals src/cpm/textio.p8 drives: ansi, vt52 or adm3a.  Only the codes
p8vi sends are known (cursor address, clear screen, clear to end of line);
anything else is an error.

    termplay.py OUTPUT ansi|vt52|adm3a
"""

import re
import sys

W, H = 80, 24

# what p8vi sends to clear the screen (it does when it quits)
CLEAR = {'ansi': b'\x1b[H\x1b[2J', 'vt52': b'\x1bH\x1bJ', 'adm3a': b'\x1a'}


class BadCode(Exception):
    pass


def play(data, term):
    """the screen's rows (trailing spaces off) and the cursor (row, col)"""
    scr = [[' '] * W for _ in range(H)]
    r = c = 0
    i = 0
    while i < len(data):
        b = data[i]
        if b == 27:
            if term == 'ansi':
                m = re.match(rb'\x1b\[([0-9;]*)([A-Za-z])', data[i:])
                if not m:
                    raise BadCode(f'{data[i:i + 6]!r} at {i}')
                args, cmd = m.group(1).decode(), m.group(2).decode()
                i += m.end()
                if cmd == 'H':
                    p = [int(x) for x in args.split(';')] if args else [1, 1]
                    r, c = p[0] - 1, p[1] - 1
                elif cmd == 'J':
                    scr = [[' '] * W for _ in range(H)]
                elif cmd == 'K':
                    scr[r][c:] = [' '] * (W - c)
                else:
                    raise BadCode(f'ESC [ {args} {cmd} at {i}')
                continue
            nxt = data[i + 1:i + 2]
            if term == 'vt52':
                if nxt == b'Y':
                    r, c = data[i + 2] - 32, data[i + 3] - 32
                    i += 4
                    continue
                if nxt == b'H':
                    r = c = 0
                elif nxt == b'J':
                    scr[r][c:] = [' '] * (W - c)
                    for rr in range(r + 1, H):
                        scr[rr] = [' '] * W
                elif nxt == b'K':
                    scr[r][c:] = [' '] * (W - c)
                else:
                    raise BadCode(f'ESC {nxt!r} at {i}')
                i += 2
                continue
            if term == 'adm3a' and nxt == b'=':
                r, c = data[i + 2] - 32, data[i + 3] - 32
                i += 4
                continue
            raise BadCode(f'{data[i:i + 4]!r} at {i}')
        elif b == 0x1a and term == 'adm3a':
            scr = [[' '] * W for _ in range(H)]
            r = c = 0
        elif b == 0:
            pass
        elif b == 13:
            c = 0
        elif b == 10:
            r = min(r + 1, H - 1)
        else:
            if not (0 <= r < H and 0 <= c < W):
                raise BadCode(f'a character at row {r} col {c}, off the screen')
            scr[r][c] = chr(b)
            c = min(c + 1, W - 1)
        i += 1
    return [''.join(x).rstrip() for x in scr], (r, c)


# what the test build sends for a $ff key (src/cpm/platform.p8's get_key)
MARK = b'\0\0\0'


def at_mark(data):
    """the output up to the test build's last mark"""
    k = data.rfind(MARK)
    return data[:k] if k >= 0 else None


def before_quit(data, term):
    """the output up to p8vi's last clear screen (when it quits)"""
    k = data.rfind(CLEAR[term])
    return data[:k] if k > 0 else data


if __name__ == '__main__':
    out = before_quit(open(sys.argv[1], 'rb').read(), sys.argv[2])
    lines, cur = play(out, sys.argv[2])
    for n, line in enumerate(lines):
        print(f'{n:2}|{line}')
    print('cursor', cur)
