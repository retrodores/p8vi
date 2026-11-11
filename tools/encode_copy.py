#!/usr/bin/env python3
"""Copy Prog8 source directories for a build that compiles them another way
than they are written, without a preprocessor:

    encode_copy.py [--encoding NAME] [--wide MODULE,...] OUT DIR...

Each DIR's *.p8 files are copied to OUT/<the DIR's last name>/.

--encoding NAME: the line `%encoding NAME` is appended to each module, so
    the whole program is compiled in that encoding while the library modules
    keep the target's own (bugs/encoding_option.md).  The end keeps the
    copy's line numbers the same as the original's in error messages (the
    compiler moves directives to the top itself).  A module that already has
    an %encoding line is left as it is.

--wide MODULE,...: in the modules named (file names without .p8), uword
    becomes long and peekw/pokew peekl/pokel: the editor core with 32-bit
    positions (src/postype.p8; the wide build has its own postype.p8 in a
    source directory before these).  Line numbers stay the same.

A copy that would be the same as the one already there is not written
again, so make sees no change.  Copies whose original has gone are removed.

    encode_copy.py --encoding iso build/cx16iso src src/cx16
        -> build/cx16iso/src/*.p8, build/cx16iso/cx16/*.p8
"""

import argparse
import os
import re

HAS_ENCODING = re.compile(r'^\s*%encoding\b', re.MULTILINE)
WIDE = [(re.compile(r'\buword\b'), 'long'), (re.compile(r'\bpeekw\b'), 'peekl'),
        (re.compile(r'\bpokew\b'), 'pokel')]


def convert(text, name, args):
    if args.encoding and not HAS_ENCODING.search(text):
        if text and not text.endswith('\n'):
            text += '\n'
        text += f'%encoding {args.encoding}\n'
    if name[:-3] in args.wide:
        for pattern, new in WIDE:
            text = pattern.sub(new, text)
    return text


def copy_dir(src, out, args):
    os.makedirs(out, exist_ok=True)
    names = sorted(n for n in os.listdir(src) if n.endswith('.p8'))
    for name in names:
        with open(os.path.join(src, name), 'r', encoding='utf-8', newline='') as f:
            text = convert(f.read(), name, args)
        path = os.path.join(out, name)
        try:
            with open(path, 'r', encoding='utf-8', newline='') as f:
                if f.read() == text:
                    continue
        except FileNotFoundError:
            pass
        with open(path, 'w', encoding='utf-8', newline='') as f:
            f.write(text)
    for name in os.listdir(out):
        if name.endswith('.p8') and name not in names:
            os.remove(os.path.join(out, name))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--encoding')
    ap.add_argument('--wide', default='', type=lambda s: set(filter(None, s.split(','))))
    ap.add_argument('out')
    ap.add_argument('dirs', nargs='+')
    args = ap.parse_args()
    for src in args.dirs:
        copy_dir(src, os.path.join(args.out, os.path.basename(os.path.normpath(src))), args)


if __name__ == '__main__':
    main()
