#!/usr/bin/env python3
"""Make a CP/M data disk for the TRS-80 Model 4's Montezuma Micro CP/M in
trs80gp, with files on it: a copy of the system disk's DMK image (for its
format) with everything after the boot tracks emptied ($E5: no files), and
the files copied on with cpmtools.

    m4disk.py SYSTEM.dsk OUT.dsk FILE[:NAME] ...

The system disk isn't changed.  A file goes on as its own name in lower
case (cut to 8.3), or as NAME.  In CP/M: B:P8VI -T ADM3A, and :e b:sample.txt.
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dmk  # noqa: E402

FORMAT = 'mm4ss'          # tools/cpm/diskdefs
BOOT = 2 * 18 * 256       # its boot tracks


def make(system, out, files):
    shutil.copyfile(system, out)
    d = dmk.Dmk(out)
    raw = bytearray(d.raw())
    raw[BOOT:] = b'\xe5' * (len(raw) - BOOT)
    with tempfile.TemporaryDirectory() as work:
        shutil.copyfile(os.path.join(HERE, 'diskdefs'), os.path.join(work, 'diskdefs'))
        image = os.path.join(work, 'disk.raw')
        with open(image, 'wb') as f:
            f.write(raw)
        for spec in files:
            path, _, name = spec.partition(':')
            name = (name or os.path.basename(path)).lower()
            # (8.3: cpmtools would cut a longer name and lose the extension)
            stem, dot, ext = name.partition('.')
            name = stem[:8] + dot + ext[:3]
            r = subprocess.run(['cpmcp', '-f', FORMAT, image, os.path.abspath(path), '0:' + name],
                               cwd=work, capture_output=True)
            if r.returncode != 0:
                sys.exit(f'cpmcp {name}: {r.stderr.decode().strip()}')
        d.put_raw(open(image, 'rb').read())


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    make(sys.argv[1], sys.argv[2], sys.argv[3:])
