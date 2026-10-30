%import reu

; extended memory: 8 KB banks that appear one at a time at $a000-$bfff.
; On the C64 they are in an REU; selecting a bank copies the current one
; back to the REU and the new one in (about 18 ms, see reu.p8).
; Bank numbers are from 0 to init()-1 on every platform.
xmem {
    ; find the extended memory, returns the number of banks (0: none)
    sub init() -> uword {
        void reu.init()
        return reu.rambanks
    }

    ; make bank n appear at $a000-$bfff
    sub select(ubyte n) {
        reu.bank(n)
    }
}
