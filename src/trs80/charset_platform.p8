; charset (src/charset.p8 is 6502 assembler) in Prog8, for the TRS-80.
; Its text is ASCII already, with CR line endings like the CBM machines,
; so only the line endings are translated: features.ASCII is off.
charset {
    ; the modes of translate()
    const ubyte TO_PETSCII = 0
    const ubyte TO_ASCII = 1
    const ubyte SWAP_EOL = 2      ; CR <-> LF, nothing else

    ; translate count bytes at p in place: CR <-> LF (every mode, as the
    ; ASCII one leaves the letters alone)
    sub translate(uword p, uword count, ubyte mode) {
        while count != 0 {
            if @(p) == $0d
                @(p) = $0a
            else if @(p) == $0a
                @(p) = $0d
            p++
            count--
        }
    }

    ; remove the LF of each CR LF pair in the count bytes at p.
    ; returns the number of bytes left.
    sub crlf_to_cr(uword p, uword count) -> uword {
        uword start = p
        uword d = p
        ubyte before = 0
        ubyte c
        while count != 0 {
            c = @(p)
            if c != $0a or before != $0d {
                @(d) = c
                d++
            }
            before = c
            p++
            count--
        }
        return d - start
    }

    ; (features.ASCII) the text is ASCII
    sub looks_ascii(uword p, uword count, bool lf) -> bool {
        return true
    }
}
