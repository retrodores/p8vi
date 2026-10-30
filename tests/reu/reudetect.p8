%import textio
%import reu
%zeropage basicsafe

; REU detection must find the size and leave the REU's memory as it was.
; Writes a pattern at the start and end of all 256 bank numbers (where the
; old detection and the new one write), takes a snapshot, runs reu.init()
; and compares.  Run by tests/reu/reutest.py with VICE's debug cartridge;
; the exit code is
;   0       no REU found, memory unchanged
;   1 to 9  1 + log2 of the number of 64 KB banks found, memory unchanged
;   200     the REU's memory changed
main {
    ; snapshots, 2 KB each
    const uword before = $8000
    const uword after = $8800
    ubyte[16] buf
    ubyte[256] head0
    ubyte[256] head1

    sub snapshot(uword dest, uword headdest) {
        ubyte b = 0
        repeat 256 {
            reu.cmd(dest + (b as uword) * 8, $fff8, 8, b, reu.REU_FETCH)
            b++
        }
        reu.cmd(headdest, 0, 256, 0, reu.REU_FETCH)
    }

    sub same(uword p1, uword p2, uword n) -> bool {
        repeat n {
            if @(p1) != @(p2)
                return false
            p1++
            p2++
        }
        return true
    }

    sub start() {
        ubyte b
        ubyte i
        ubyte code = 0
        uword n
        uword kb
        bool ok
        ; a smaller REU repeats its banks, so later writes win; the snapshot
        ; says what is really there
        b = 0
        repeat 256 {
            for i in 0 to 15
                buf[i] = b ^ (i * 17) ^ $5a
            reu.cmd(buf, $fff8, 8, b, reu.REU_STASH)
            reu.cmd(buf, 0, 16, b, reu.REU_STASH)
            b++
        }
        ; (without an REU nothing is fetched: compare cleared memory)
        sys.memset(before, $1000, 0)
        sys.memset(head0, 256, 0)
        sys.memset(head1, 256, 0)
        snapshot(before, head0)
        kb = reu.init()
        snapshot(after, head1)
        ok = same(before, after, 256 * 8) and same(head0, head1, 256)
        txt.print("size ")
        txt.print_uw(kb)
        txt.print("k banks ")
        txt.print_uw(reu.banks)
        txt.print(" rambanks ")
        txt.print_uw(reu.rambanks)
        txt.nl()
        txt.print(if ok "reu memory unchanged" else "reu memory CHANGED")
        txt.nl()
        if reu.present {
            code = 1
            n = reu.banks
            while n > 1 {
                n >>= 1
                code++
            }
        }
        if not ok
            code = 200
        repeat 5 sys.waitvsync()
        @($d7ff) = code
    }
}
