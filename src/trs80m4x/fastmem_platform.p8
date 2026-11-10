; the text stores' byte scans and copies for the TRS-80 Model 4 128 KB build
; (p8vi-trs80m4x): src/fastmem.p8 is 6502 assembler, and the page store
; uses these routines whatever FAST says (the gap buffer, src/trs80, has
; loops of its own), so here they are in Prog8.
fastmem {
    const bool FAST = true

    ; the offset of the first value in the n bytes at p, or n if none
    sub find(uword p, uword n, ubyte value) -> uword {
        uword i = 0
        while i != n {
            if @(p + i) == value
                return i
            i++
        }
        return n
    }

    ; the offset of the last value in the n bytes at p, or $ffff if none
    sub find_back(uword p, uword n, ubyte value) -> uword {
        while n != 0 {
            n--
            if @(p + n) == value
                return n
        }
        return $ffff
    }

    ; how many times value is in the n bytes at p
    sub count(uword p, uword n, ubyte value) -> uword {
        uword c = 0
        while n != 0 {
            n--
            if @(p + n) == value
                c++
        }
        return c
    }

    ; copy n bytes from src to dest, also when they overlap
    sub move(uword src, uword dest, uword n) {
        if n == 0 or src == dest
            return
        if dest < src {
            sys.memcopy(src, dest, n)
            return
        }
        ; (dest after src: from the end, so src isn't overwritten first)
        while n != 0 {
            n--
            @(dest + n) = @(src + n)
        }
    }
}
