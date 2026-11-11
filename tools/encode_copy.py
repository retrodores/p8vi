#!/usr/bin/env python3
"""Copy Prog8 source directories with a default text encoding added to each
module: the whole program compiled in another encoding, with the library
modules left in the target's own (bugs/encoding_option.md).

    encode_copy.py ENCODING OUT DIR...

Each DIR's *.p8 files are copied to OUT/<the DIR's last name>/, with the
line `%encoding ENCODING` appended at the end.  The end keeps the copy's
line numbers the same as the original's in error messages (the compiler
moves directives to the top itself).  A module that already has an
%encoding line is copied unchanged.  A copy that would be the same as the
one already there is not written again, so make sees no change.  Copies
whose original has gone are removed.

    encode_copy.py iso build/cx16iso src src/cx16
        -> build/cx16iso/src/*.p8, build/cx16iso/cx16/*.p8
"""

import os
import re
import sys

HAS_ENCODING = re.compile(r'^\s*%encoding\b', re.MULTILINE)


def copy_dir(encoding, src, out):
    os.makedirs(out, exist_ok=True)
    names = sorted(n for n in os.listdir(src) if n.endswith('.p8'))
    for name in names:
        with open(os.path.join(src, name), 'r', encoding='utf-8', newline='') as f:
            text = f.read()
        if not HAS_ENCODING.search(text):
            if text and not text.endswith('\n'):
                text += '\n'
            text += f'%encoding {encoding}\n'
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
    if len(sys.argv) < 4:
        sys.exit(__doc__.split('\n\n')[1])
    encoding, out = sys.argv[1], sys.argv[2]
    for src in sys.argv[3:]:
        copy_dir(encoding, src, os.path.join(out, os.path.basename(os.path.normpath(src))))


if __name__ == '__main__':
    main()
