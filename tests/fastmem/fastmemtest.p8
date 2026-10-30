;
; checks the 6502 fastmem routines (src/fastmem.p8) against plain Prog8 on
; a C64 in VICE: lengths around page boundaries, the value at the start,
; the end or nowhere, and moves overlapping either way.  exit code 0 = ok,
; else the number of failures.   make test-fastmem
;
%import textio
%zeropage basicsafe
%import fastmem

main {
    const uword A = $4000       ; test areas: 4 KB each
    const uword B = $5000
    ubyte failures

    uword[] lengths = [0, 1, 2, 255, 256, 257, 511, 512, 513, 1000]

    sub start() {
        ubyte li
        ubyte k
        uword n
        uword d
        uword[] places = [0, 1, 254, 255, 256, 300, 511, 512, 999]
        uword[] distances = [1, 2, 3, 255, 256, 300]
        txt.print("fastmem test\n")
        for li in 0 to len(lengths) - 1 {
            n = lengths[li]
            ; find / find_back / count: the value nowhere, then at places
            sys.memset(A, 2048, 'a')
            check_scans(n)
            for k in 0 to len(places) - 1 {
                if places[k] < n {
                    @(A + places[k]) = 'x'
                    check_scans(n)
                }
            }
            ; the value just outside: before p and at p + n
            @(A + n) = 'x'
            check_scans(n)
            ; move: apart, and overlapping up and down by a few distances
            for k in 0 to len(distances) - 1 {
                d = distances[k]
                check_move(A + 512, B, n)
                check_move(A + 512, A + 512 + d, n)
                check_move(A + 512 + d, A + 512, n)
            }
        }
        txt.print("failures ")
        txt.print_ub(failures)
        txt.nl()
        repeat 5 sys.waitvsync()
        @($d7ff) = failures
    }

    sub check_scans(uword n) {
        uword i
        uword first = n
        uword last = $ffff
        uword c = 0
        for i in 0 to n - 1 {
            if n == 0
                break
            if @(A + i) == 'x' {
                if first == n
                    first = i
                last = i
                c++
            }
        }
        if fastmem.find(A, n, 'x') != first
            fail("find", n)
        if fastmem.find_back(A, n, 'x') != last
            fail("find_back", n)
        if fastmem.count(A, n, 'x') != c
            fail("count", n)
    }

    ; move n bytes from src to dest and compare with a copy made the slow way
    sub check_move(uword src, uword dest, uword n) {
        uword i
        ; a pattern, and the expected result in $6000
        for i in 0 to 4095
            @(A + i) = lsb(i * 7 + (i >> 8))
        sys.memcopy(A, $6000, 4096)
        if n != 0 {
            for i in 0 to n - 1
                @($7000 + i) = @(src + i)
            for i in 0 to n - 1
                @($6000 + (dest - A) + i) = @($7000 + i)
        }
        fastmem.move(src, dest, n)
        if dest >= A and dest < A + 4096 {
            for i in 0 to 4095 {
                if @(A + i) != @($6000 + i) {
                    fail("move", n)
                    return
                }
            }
        } else {
            for i in 0 to n - 1 {
                if n == 0
                    break
                if @(dest + i) != @($7000 + i) {
                    fail("move apart", n)
                    return
                }
            }
        }
    }

    sub fail(str what, uword n) {
        failures++
        txt.print(what)
        txt.spc()
        txt.print_uw(n)
        txt.nl()
    }
}
