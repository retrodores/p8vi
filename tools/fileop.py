#!/usr/bin/env python3
"""The Makefile's file commands on Windows, where copy, del and mkdir take
a / in a path for an option ("The syntax of the command is incorrect"):

    fileop.py cp SRC... DST     copy, keeping the time (cp -p); globs too, and
                                with more than one source DST is a directory
    fileop.py rm PATH...        remove files and directories, globs too (rm -fr)
    fileop.py mkdir DIR...      make directories, parents too (mkdir -p)

Paths take / or \\.  Elsewhere the Makefile uses cp, rm and mkdir.
"""

import glob
import os
import shutil
import sys


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    op, paths = argv[0], argv[1:]
    if op == 'cp' and len(paths) >= 2:
        sources = [s for pattern in paths[:-1] for s in (sorted(glob.glob(pattern)) or [pattern])]
        if len(sources) > 1 and not os.path.isdir(paths[-1]):
            sys.exit(f'fileop.py cp: {paths[-1]} is not a directory')
        for source in sources:
            shutil.copy2(source, paths[-1])
    elif op == 'rm':
        for pattern in paths:
            for path in glob.glob(pattern) or [pattern]:
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path, ignore_errors=True)
                elif os.path.lexists(path):
                    os.remove(path)
    elif op == 'mkdir':
        for path in paths:
            os.makedirs(path, exist_ok=True)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
