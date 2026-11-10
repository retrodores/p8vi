"""DMK floppy images (trs80gp's): list, extract the sectors to a raw image (by
track, then sector ID), and write a raw image's sectors back (CRCs
recomputed).  With cpmtools this puts files on a CP/M disk for trs80gp:

    python3 tools/cpm/dmk.py info disk.dsk
    python3 tools/cpm/dmk.py extract disk.dsk disk.raw
    cd tools/cpm && cpmcp -f mm4ss ../../disk.raw ../../build/p8vi-cpm.com 0:p8vi.com
    python3 tools/cpm/dmk.py insert disk.dsk disk.raw

(the image keeps its track layout; only the sectors' data and CRCs change)
"""
import sys, struct

def crc16(data, crc=0xffff):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xffff
    return crc

class Dmk:
    def __init__(self, path):
        self.path = path
        self.img = bytearray(open(path, 'rb').read())
        self.tracks = self.img[1]
        self.tlen = struct.unpack_from('<H', self.img, 2)[0]
        self.sides = 1 if self.img[4] & 0x10 else 2

    def sectors(self):
        """(cyl, side, sec, size, data_offset, dd) for every sector, in track order"""
        out = []
        for t in range(self.tracks * self.sides):
            base = 16 + t * self.tlen
            for i in range(64):
                p = struct.unpack_from('<H', self.img, base + 2 * i)[0]
                if p == 0:
                    break
                dd = bool(p & 0x8000)
                idam = base + (p & 0x3fff)
                cyl, side, sec, sz = self.img[idam + 1:idam + 5]
                size = 128 << sz
                # the data address mark: after the ID's CRC, within ~60 bytes
                j = idam + 7
                while self.img[j] not in (0xfb, 0xf8):
                    j += 1
                out.append((cyl, side, sec, size, j + 1, dd))
        return out

    def raw(self):
        secs = sorted(self.sectors(), key=lambda s: (s[0], s[1], s[2]))
        return b''.join(bytes(self.img[s[4]:s[4] + s[3]]) for s in secs)

    def put_raw(self, raw):
        secs = sorted(self.sectors(), key=lambda s: (s[0], s[1], s[2]))
        pos = 0
        for cyl, side, sec, size, off, dd in secs:
            data = raw[pos:pos + size]
            pos += size
            if bytes(self.img[off:off + size]) == data:
                continue
            self.img[off:off + size] = data
            mark = self.img[off - 1]
            crc = crc16(bytes([0xa1, 0xa1, 0xa1, mark]) + data) if dd else crc16(bytes([mark]) + data)
            struct.pack_into('>H', self.img, off + size, crc)
        open(self.path, 'wb').write(self.img)

if __name__ == '__main__':
    cmd, path = sys.argv[1], sys.argv[2]
    d = Dmk(path)
    if cmd == 'info':
        secs = d.sectors()
        print(f'{d.tracks} tracks, {d.sides} side(s), track length {d.tlen}, {len(secs)} sectors')
        for t in (0, 1, 2, d.tracks - 1):
            row = [s for s in secs if s[0] == t]
            print(f'  track {t}: ids {[s[2] for s in row]} sizes {sorted(set(s[3] for s in row))} dd {sorted(set(s[5] for s in row))}')
    elif cmd == 'extract':
        open(sys.argv[3], 'wb').write(d.raw())
    elif cmd == 'insert':
        d.put_raw(open(sys.argv[3], 'rb').read())
