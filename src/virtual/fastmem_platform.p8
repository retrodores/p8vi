; fastmem for the virtual target (the store tests): the routines of
; src/fastmem.p8 in Prog8, which does the same as the 6502 assembler there.

fastmem {
    ; the stores use these routines
    const bool FAST = true

    ; the offset of the first value in the n bytes at p, or n if none
    sub find(uword p, uword n, ubyte value) -> uword {
        uword i
        for i in 0 to n - 1 {
            if n == 0
                break
            if @(p + i) == value
                return i
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
        uword i
        for i in 0 to n - 1 {
            if n == 0
                break
            if @(p + i) == value
                c++
        }
        return c
    }

    ; copy n bytes from src to dest, also when they overlap
    sub move(uword src, uword dest, uword n) {
        uword i
        if dest < src {
            for i in 0 to n - 1 {
                if n == 0
                    break
                @(dest + i) = @(src + i)
            }
        } else if dest > src {
            while n != 0 {
                n--
                @(dest + n) = @(src + n)
            }
        }
    }
}
