; llvm16: the mc6809-coco build's code is 1333 bytes, the z80-trs80-cmd
; build's 565: everything is inlined into main on the 6809, which halves
; with -mllvm -inline-threshold=0 (703 bytes).  bugs/mc6809_code_size.md.
; plain byte and word loops, no library calls past txt.
%zeropage basicsafe
%import textio

main {
    ubyte[200] data

    sub start() {
        fill(&data, 200, 7)
        data[150] = 42
        txt.print_uw(find(&data, 200, 42))
        txt.nl()
        txt.print_uw(find_back(&data, 200, 7))
        txt.nl()
        txt.print_uw(sum(&data, 200))
        txt.nl()
        txt.print_ub(count(&data, 200, 7))
        txt.nl()
    }

    sub fill(pointer p, uword n, ubyte value) {
        while n != 0 {
            @(p) = value
            p++
            n--
        }
    }

    sub find(pointer p, uword n, ubyte value) -> uword {
        uword i
        for i in 0 to n - 1 {
            if p[i] == value
                return i
        }
        return $ffff
    }

    sub find_back(pointer p, uword n, ubyte value) -> uword {
        while n != 0 {
            n--
            if p[n] == value
                return n
        }
        return $ffff
    }

    sub sum(pointer p, uword n) -> uword {
        uword total = 0
        while n != 0 {
            total += @(p)
            p++
            n--
        }
        return total
    }

    sub count(pointer p, uword n, ubyte value) -> ubyte {
        ubyte c = 0
        while n != 0 {
            if @(p) == value
                c++
            p++
            n--
        }
        return c
    }
}
