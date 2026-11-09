; the text stores' byte scans and copies: src/fastmem.p8 is 6502
; assembler, so the gap buffer keeps its own Prog8 loops here (FAST false).
; the names are still there, for the code that FAST leaves out.
fastmem {
    const bool FAST = false
    sub find(uword p, uword n, ubyte value) -> uword {
        return 0
    }
    sub find_back(uword p, uword n, ubyte value) -> uword {
        return 0
    }
    sub count(uword p, uword n, ubyte value) -> uword {
        return 0
    }
    sub move(uword src, uword dest, uword n) {
    }
}
