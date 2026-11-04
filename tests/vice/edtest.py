#!/usr/bin/env python3
"""Editor tests on a C64 in VICE (x64sc with a true-drive 1541), or with
--machine pet on a PET 4032 (xpet with an IEEE-488 2031 drive), or with
--machine plus4 on a Plus/4 (xplus4 with a 1541).

    edtest.py [--prg build/p8vi-c64.prg] [--work build] [-j N] [files|screen] [name...]

files   (default) types vi commands at the editor, saves the text with
        ":w name" after each step, and compares the saved files with the
        expected text.
screen  types keys, dumps screen memory over the VICE remote monitor, does
        the same again with Ctrl-L (a full redraw) at the end, and compares
        the two screens.  Checks that partial redraws leave the screen right.

Every run gets its own disk image, so runs go in parallel.  A run that hits
the cycle limit hung.

--font FNT runs the font build (p8vi-c64font) with its font file on the
disk, and adds its tests.

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

# lines from empty to 2.5 rows long: rows that wrap
WRAPPED = b'\n'.join(b'W%02d ' % i + (b'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' * 3)[:(i % 4) * 32] for i in range(40))

# a mixed case ASCII file, read and written with ASCII <-> PETSCII translation
ASCII = b'Hello World\nsnake_case | a~b\nLAST line'


def petscii(text):
    """ASCII to PETSCII as the editor translates: letters swap case ranges,
    _ | ~ become the PETSCII characters typed for them."""
    out = bytearray()
    for c in text:
        if 0x41 <= c <= 0x5a:
            c += 0x80
        elif 0x61 <= c <= 0x7a:
            c -= 0x20
        else:
            c = {0x5f: 0xa4, 0x7c: 0xdd, 0x7e: 0xde}.get(c, c)
        out.append(c)
    return bytes(out)


# a CRLF file, held with CR line endings in memory
CRLF = b'line one\r\nline two\r\nlast\r\n'

# a 2 KB file for saving to a full disk
FULL = b''.join(b'FULL LINE %03d ABCDEFGHIJ\n' % i for i in range(80))

# a 3.2 KB CRLF file over several 1 KB pages: the first line is 31
# characters and the others 30, so a CR is the last byte of the first and
# the second KB and its LF the first byte of the next (the editor reads a
# page at a time)
BIG_LINES = [b'FIRST LINE OF A BIG FILE 000000'] + \
    [b'LINE %03d ' % i + b'ABCDEFGHIJKLMNOPQRSTU' for i in range(1, 100)]
BIGCRLF = b''.join(l + b'\r\n' for l in BIG_LINES)
assert BIGCRLF[1023] == 13 and BIGCRLF[1024] == 10 and BIGCRLF[2047] == 13

# (name, keys, [(saved file, expected contents)], text of t.txt (SHORT if left out))
FILE_SUITES = [
    ('delete-put', r'dw:w a1\njdd:w a2\np:w a3\n1Gyyp:w a4\n', [
        ('p8vi.tmp', None),     # (the safe save's temporary file is gone)
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
    # typed letters are PETSCII lowercase, so 'hi' is written as ASCII 'hi'.
    # s7 is written as PETSCII, then read back: it has PETSCII capitals, so
    # it is not translated (s8), until :set ascii (s9)
    ('ascii', r':w s1\nx:w s2\nihi \x1b:w s3\n0\xde\xde:w s4\n/orld\nD:w s5\nj$x:w s6\n'
              r':set petscii\n:w s7\n:e s7\n:w s8\n:set ascii\n:w s9\n', [
        ('s1', ASCII),
        ('s2', b'ello World\nsnake_case | a~b\nLAST line'),
        ('s3', b'hi ello World\nsnake_case | a~b\nLAST line'),
        ('s4', b'HI ello World\nsnake_case | a~b\nLAST line'),
        ('s5', b'HI ello W\nsnake_case | a~b\nLAST line'),
        ('s6', b'HI ello W\nsnake_case | a~\nLAST line'),
        ('s7', petscii(b'HI ello W\nsnake_case | a~\nLAST line')),
        ('s8', petscii(b'HI ello W\nsnake_case | a~\nLAST line')),
        ('s9', b'HI ello W\nsnake_case | a~\nLAST line'),
    ], ASCII),
    # c1 round trip, c2 an edit, then other line endings; c5: an LF file
    # read back stays LF; c6 :r of a CRLF file into a CR file
    ('crlf', r':w c1\njdd:w c2\n:set lf\n:w c3\n:set cr\n:w c4\n:e! c3\nx:w c5\n'
             r':set cr\n:r c1\n:w c6\n:set crlf\n:w c7\n', [
        ('c1', CRLF),
        ('c2', b'line one\r\nlast\r\n'),
        ('c3', b'line one\nlast\n'),
        ('c4', b'line one\rlast\r'),
        ('c5', b'ine one\nlast\n'),
        ('c6', b'ine one\rline one\rline two\rlast\rlast\r'),
        ('c7', b'ine one\r\nline one\r\nline two\r\nlast\r\nlast\r\n'),
    ], CRLF),
    # a CRLF file bigger than a page, CR LF pairs split between reads: g1
    # round trip, g2 without the first line, g3 the whole file read in
    # after the (new) first line
    ('big', r':w g1\n1Gdd:w g2\n:r t.txt\n:w g3\n', [
        ('g1', BIGCRLF),
        ('g2', b''.join(l + b'\r\n' for l in BIG_LINES[1:])),
        ('g3', b''.join(l + b'\r\n' for l in BIG_LINES[1:2] + BIG_LINES + BIG_LINES[2:])),
    ], BIGCRLF),
    # :w over the file itself: written to p8vi.tmp, which then replaces it
    ('save-over', r'dd:w\n', [
        ('t.txt', SHORT.split(b'\n', 1)[1]),
        ('p8vi.tmp', None),
    ]),
    # saving to a full disk: the text doubled (read in again) doesn't fit in
    # the 3 blocks left, so the save fails, and the file is as it was (it
    # used to be deleted before writing), with no temporary file left
    ('save-full', r'G:r t.txt\n:w\n', [
        ('t.txt', FULL),
        ('p8vi.tmp', None),
    ], FULL, 3),
    # a line ending at the end of a file ends the last line (vi): G goes to
    # "two", not to an empty line after it, and the line ending is written
    # back.  new: a new text gets one too (a CR, PETSCII)
    ('final-eol', r'Gdd:w e1\nyyp:w e2\nGox\x1b:w e3\nG:r t.txt\n:w e4\n:e! new\nihello\x1b:w\n', [
        ('e1', b'one\n'),
        ('e2', b'one\none\n'),
        ('e3', b'one\none\nx\n'),
        ('e4', b'one\none\nx\none\ntwo\n'),
        ('new', b'HELLO\r'),
    ], b'one\ntwo\n'),
    # :r of a file without a line ending at its end (r0): r1 inside the
    # text gets a line ending after it, r2 at the end of the text doesn't;
    # r3: undo takes the whole :r back
    ('read', r':w r0\n1G:r r0\n:w r1\nG:r r0\n:w r2\nu:w r3\n', [
        ('r0', SHORT),
        ('r1', SHORT.split(b'\n', 1)[0] + b'\n' + SHORT + b'\n' + SHORT.split(b'\n', 1)[1]),
        ('r2', SHORT.split(b'\n', 1)[0] + b'\n' + SHORT + b'\n' + SHORT.split(b'\n', 1)[1] + b'\n' + SHORT),
        ('r3', SHORT.split(b'\n', 1)[0] + b'\n' + SHORT + b'\n' + SHORT.split(b'\n', 1)[1]),
    ]),
    # :r converts the file read to the text's format.  n1: into a new, empty
    # text it takes the file's (ASCII, LF), so dd deletes one line; n2: an
    # LF file into CR text; n4: a CR LF file (n3) into LF text
    ('read-format', r':e new\n:r t.txt\ndd:w n1\n:set cr\n:r t.txt\n:w n2\n'
                    r':set crlf\n:w n3\n:set lf\nG:r n3\n:w n4\n', [
        ('n1', b'two\nthree\n'),
        ('n2', b'two\rone\rtwo\rthree\rthree\r'),
        ('n3', b'two\r\none\r\ntwo\r\nthree\r\nthree\r\n'),
        ('n4', b'two\none\ntwo\nthree\nthree\n' * 2),
    ], b'one\ntwo\nthree\n'),
    # :s and line ranges.  s1 the first match in the cursor line; s2 all of
    # them in all lines; s3 u takes the whole :%s back, s4 u again redoes it;
    # s5 a range, the last delimiter left out; s6 :$ goes to the last line;
    # s7 an empty old is the last search; s8 an empty new deletes; s9 a
    # backwards range; s10 . in a range
    ('subst', r':s/one/1/\n:w s1\n:%s/one/x/g\n:w s2\nu:w s3\nu:w s4\n'
              r':2,3s/two/22\n:w s5\n:$\n:s/four/4 4/\n:w s6\n'
              r'/x\n:s//y/\n:w s7\n:%s/ //g\n:w s8\n:3,2s/x/z/\n:w s9\n'
              r':1\n:.,2s/2/n/g\n:w s10\n', [
        ('s1', b'1 TWO ONE\nTWO ONE TWO\nTHREE ONE\nFOUR'),
        ('s2', b'1 TWO X\nTWO X TWO\nTHREE X\nFOUR'),
        ('s3', b'1 TWO ONE\nTWO ONE TWO\nTHREE ONE\nFOUR'),
        ('s4', b'1 TWO X\nTWO X TWO\nTHREE X\nFOUR'),
        ('s5', b'1 TWO X\n22 X TWO\nTHREE X\nFOUR'),
        ('s6', b'1 TWO X\n22 X TWO\nTHREE X\n4 4'),
        ('s7', b'1 TWO Y\n22 X TWO\nTHREE X\n4 4'),
        ('s8', b'1TWOY\n22XTWO\nTHREEX\n44'),
        ('s9', b'1TWOY\n22ZTWO\nTHREEZ\n44'),
        ('s10', b'1TWOY\nNNZTWO\nTHREEZ\n44'),
    ], b'ONE TWO ONE\nTWO ONE TWO\nTHREE ONE\nFOUR'),
    # :r $ reads the directory below the cursor line, without the drive's
    # padding and control codes (d1); u takes it all back (d2)
    ('read-dir', r'1G:r $\n:w d1\nu:w d2\n', [
        ('d1', lambda args: dir_text(args, SHORT, 1)),
        ('d2', SHORT),
    ]),
    # :@ drive commands: victim is written and scratched, keep is renamed
    # to moved; :@$ shows the directory and a key goes back to the text
    # (d1 still has it)
    ('dos', r':w victim\n:@s:victim\n:w keep\n:@r:moved=keep\n:@$\n :w d1\n', [
        ('victim', None),
        ('keep', None),
        ('moved', SHORT),
        ('d1', SHORT),
    ]),
    # f F t T ; as motions and with d.  f1: T at the start of the text
    # finds nothing (and must not search from the end); f5: T again right
    # after the character skips it
    ('find', r'0Tax:w f1\n$Fax:w f2\n0tax:w f3\n0fb;x:w f4\n$Tb;x:w f5\n0dtc:w f6\n', [
        ('f1', b'bcabcabc'),
        ('f2', b'bcabcbc'),
        ('f3', b'babcbc'),
        ('f4', b'babcc'),
        ('f5', b'bbcc'),
        ('f6', b'cc'),
    ], b'abcabcabc'),
]

# a 6 KB file: more pages than the REU build's 4 cache slots, so pages go
# to the REU and back (REU only: without one that build has 4 KB of text).
# p1 round trip, p2 line 150 deleted, p3 that undone
PAGES_LINES = [b'PAGE LINE %03d ' % i + b'0123456789' * (i % 4) for i in range(200)]
PAGES = b'\n'.join(PAGES_LINES) + b'\n'


# with an REU only (--reu): a 30 KB file, more than main RAM holds, read
# in again after its first line (60 KB), and once more, which is cut short
# where the text reaches 65534 bytes, the most there can be.  (only the
# end result is saved: a 1541 disk holds 168 KB)
HUGE_LINES = [b'HUGE LINE %05d ' % i + b'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[:i % 27] for i in range(1000)]
HUGE = b'\n'.join(HUGE_LINES) + b'\n'
HUGE2 = b'\n'.join(HUGE_LINES[:1] + HUGE_LINES + HUGE_LINES[1:]) + b'\n'
FIRST = len(HUGE_LINES[0]) + 1
# (the text doesn't keep the file's last line ending, so it holds one
# byte more of the file read in; the line ending is written back)
HUGE3 = HUGE2[:FIRST] + HUGE[:65534 - len(HUGE2) + 1] + HUGE2[FIRST:]
REU_SUITES = [
    ('pages', r':w p1\n150Gdd:w p2\nu:w p3\n', [
        ('p1', PAGES),
        ('p2', b'\n'.join(PAGES_LINES[:149] + PAGES_LINES[150:]) + b'\n'),
        ('p3', PAGES),
    ], PAGES),
    # undo and yank bigger than main RAM holds: b1 dG of all 30 KB undone,
    # b2 all of it yanked and put above the first line (60 KB)
    ('bigundo', r'dGu:w b1\n1GyG1GP:w b2\n', [
        ('b1', HUGE),
        ('b2', HUGE + HUGE),
    ], HUGE),
    ('huge', r'1G:r t.txt\n1G:r t.txt\n:w h3\n', [
        ('h3', HUGE3),
    ], HUGE),
]

# the font build (p8vi-c64font, --font): the font shows ASCII's ` { | } ~
# for PETSCII $c0 $db $dc $dd $de, typed with the C64 OS keys (shift + *,
# shift + plus, shift + pound, shift + minus, shift + up arrow), and \ ^ _
# are pound, up arrow and left arrow.  f2 types them all; f3 shift + pound
# is the | command; f4 _ is part of a word; f5 left arrow is the _ command
FONT_TEXT = b'int main(void) {\n  a = b | c ^ ~d;\n  s = "\\n" `x` my_name;\n}\n'
FONT_SUITES = [
    ('font', r':w f1\nA \xa9\xdb\xdd\xde\xc0\x5c\x5e\x5f\x1b:w f2\nj06\xa9x:w f3\nj$bD:w f4\nk\x5fx:w f5\n', [
        ('f1', FONT_TEXT),
        ('f2', FONT_TEXT.replace(b'{\n', b'{ |{}~`\\^_\n', 1)),
        ('f3', FONT_TEXT.replace(b'{\n', b'{ |{}~`\\^_\n', 1).replace(b'a = b', b'a =b')),
        ('f4', FONT_TEXT.replace(b'{\n', b'{ |{}~`\\^_\n', 1).replace(b'a = b', b'a =b')
               .replace(b'my_name;', b'')),
        ('f5', FONT_TEXT.replace(b'{\n', b'{ |{}~`\\^_\n', 1).replace(b'a = b', b' =b')
               .replace(b'my_name;', b'')),
    ], FONT_TEXT),
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
    # one-row scrolls (features.SCROLL): down and up, also over lines that
    # wrap over several rows
    ('scroll-down', LONG, 'j' * 30),
    ('scroll-up', LONG, 'G' + 'k' * 30),
    ('scroll-mixed', LONG, 'j' * 25 + 'k' * 5 + 'j' * 4),
    ('scroll-wrap-down', WRAPPED, 'j' * 25),
    ('scroll-wrap-up', WRAPPED, 'G' + 'k' * 25),
]

EMU = ['x64sc', '-default', '-sounddev', 'dummy', '-warp', '+autostart-warp',
       '-drive8type', '1541']
# a write here (the -debugcart) quits VICE: $d7ff on the C64
EXIT_POKE = 'poke 55295,0'
# where the screen is, for the screen tests
SCREEN_DUMP = 'm 0400 07e7'
# the PET (--machine pet): a 4032 with a 2031, the IEEE-488 drive that
# takes .d64 images like the 1541; its debug cartridge is at $8bff, its
# screen at $8000
PET = {'EMU': ['xpet', '-default', '-model', '4032', '-sounddev', 'dummy', '-warp',
               '+autostart-warp', '-drive8type', '2031'],
       'EXIT_POKE': 'poke 35839,0', 'SCREEN_DUMP': 'm 8000 83e7'}
# the Plus/4 (--machine plus4): its debug cartridge is at $fdcf, its screen
# at $0c00
PLUS4 = {'EMU': ['xplus4', '-default', '-sounddev', 'dummy', '-warp', '+autostart-warp',
                 '-drive8type', '1541'],
         'EXIT_POKE': 'poke 64975,0', 'SCREEN_DUMP': 'm 0c00 0fe7'}


def dir_text(args, text, after):
    """text with the test disk's directory (the program and t.txt) read in
    after line number after, as :r $ does"""
    blocks = -(-os.path.getsize(args.prg) // 254)
    lines = [b'0 "TEST            " 52 2A',
             b'%d%s"P8VI"             PRG' % (blocks, b' ' * (5 - len(str(blocks)))),
             b'1    "T.TXT"            SEQ',
             b'%d BLOCKS FREE.' % (664 - blocks - 1)]
    old = text.split(b'\n')
    return b'\n'.join(old[:after] + lines + old[after:])


# the font file for the font build (--font), put on each disk
FONT = None


def make_disk(d64, prg, text, blocks_free=None):
    txt = d64 + '.txt'
    with open(txt, 'wb') as f:
        f.write(text)
    subprocess.run(['c1541', '-format', 'test,52', 'd64', d64, '-attach', d64,
                    '-write', prg, 'p8vi,p', '-write', txt, 't.txt,s'] +
                   (['-write', FONT, 'p8vi.fnt,p'] if FONT else []),
                   check=True, capture_output=True)
    if blocks_free is not None:
        # a file that fills the disk up to blocks_free blocks
        out = subprocess.run(['c1541', '-attach', d64, '-dir'], capture_output=True, text=True).stdout
        free = int(re.search(r'(\d+) blocks free', out).group(1))
        fill = d64 + '.fill'
        with open(fill, 'wb') as f:
            f.write(b'x' * 254 * (free - blocks_free))
        subprocess.run(['c1541', '-attach', d64, '-write', fill, 'fill,s'],
                       check=True, capture_output=True)


def run_files(args, suite):
    name, keys, expected, *text = suite
    base = os.path.join(args.work, 'vt-' + name)
    d64 = base + '.d64'
    make_disk(d64, args.prg, text[0] if text else SHORT, text[1] if len(text) > 1 else None)
    # :q! back to BASIC, then a write to $d7ff (the -debugcart) quits VICE
    keybuf = ':e t.txt\\n' + keys + ':q!\\n' + EXIT_POKE + '\\n'
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
        if callable(want):
            want = want(args)
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
        # wait in emulated time, so a busy host can't cut the run short.
        # (a monitor that doesn't answer yet, with VICE still starting on a
        # busy host, is asked again: once that ended the check)
        deadline = time.time() + 600
        while time.time() < deadline:
            time.sleep(1)
            reply = monitor(port, ['sw'], 10)
            if reply is None:
                continue
            m = re.search(r'Stopwatch:\s+(\d+)', reply[0])
            if m and int(m.group(1)) >= args.cycles:
                for _ in range(5):
                    # (the font build's screen is at $c800)
                    reply = monitor(port, ['m c800 cbe7' if FONT else SCREEN_DUMP], 10)
                    if reply:
                        return screen_bytes(reply[0])
                return None
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
    ap.add_argument('--prg', default='build/p8vi-c64.prg')
    ap.add_argument('--work', default='build')
    ap.add_argument('-j', type=int, default=os.cpu_count() or 4)
    ap.add_argument('--limit', type=int, default=800_000_000, help='cycle limit per run')
    ap.add_argument('--port', type=int, default=6600, help='first remote monitor port')
    ap.add_argument('--cycles', type=int, default=150_000_000,
                    help='cycles a screen run gets to finish its keys')
    ap.add_argument('--reu', type=int, metavar='KB', help='with an REU of this size')
    ap.add_argument('--skip', action='append', default=[], metavar='SUITE',
                    help='leave this suite out (for builds with little room)')
    ap.add_argument('--font', metavar='FNT', help='the font build: its font file, and its tests')
    ap.add_argument('--machine', default='c64', choices=['c64', 'pet', 'plus4'])
    ap.add_argument('--jiffydos', action='store_true',
                    help="the C64 with JiffyDOS: VICE's jiffykernal and jiffy1541II ROMs (in VICE's ROM directories)")
    ap.add_argument('--paged', action='store_true',
                    help='also the REU suites (more text than main RAM holds) without an REU: the disk build')
    args = ap.parse_args()
    global FONT, EMU, EXIT_POKE, SCREEN_DUMP
    machine = {'pet': PET, 'plus4': PLUS4}.get(args.machine)
    if machine:
        EMU, EXIT_POKE, SCREEN_DUMP = machine['EMU'], machine['EXIT_POKE'], machine['SCREEN_DUMP']
    if args.font:
        FONT = os.path.abspath(args.font)
    if args.reu:
        EMU.extend(['-reu', '-reusize', str(args.reu)])
    if args.jiffydos:
        EMU.extend(['-kernal', 'jiffykernal', '-dos1541', 'jiffy1541II', '-dos1541II', 'jiffy1541II'])
    for tool in (EMU[0], 'c1541'):
        if not shutil.which(tool):
            sys.exit(f'{tool} (VICE) not found in PATH')
    args.prg = os.path.abspath(args.prg)
    args.work = os.path.abspath(args.work)
    os.makedirs(args.work, exist_ok=True)

    if args.kind == 'files':
        suites = [s for s in FILE_SUITES + (REU_SUITES if args.reu or args.paged else []) + (FONT_SUITES if args.font else [])
                  if (not args.names or s[0] in args.names) and s[0] not in args.skip]
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
