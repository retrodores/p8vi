; extended memory: 8 KB banks that appear one at a time at $a000-$bfff.
; On the Commander X16 these are its banked RAM: selecting one is a single
; write.  Bank 0 belongs to the KERNAL and a reset changes the first byte
; of bank 1 (docs/XMEM-DESIGN.md), so the banks start at RAM bank 2.
; Bank numbers are from 0 to init()-1 on every platform.
xmem {
    const ubyte FIRST = 2

    ; find the extended memory, returns the number of banks (0: none)
    sub init() -> uword {
        return cx16.numbanks() - FIRST
    }

    ; make bank n appear at $a000-$bfff
    sub select(ubyte n) {
        cx16.rambank(n + FIRST)
    }
}
