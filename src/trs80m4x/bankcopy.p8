;
; the TRS-80 Model 4's second 64 KB (a 128 KB machine), for the page store
; (pagemem_platform.p8): copy() copies bytes with one of its two 32 KB
; pages at $0000-$7fff in place of the normal RAM there.  Port $84 bits
; 6-4: 110 the first page, 111 the second (the DOS keeps the port's value
; at $0078; it can't be read).
;
; The copy is a few bytes of Z80 code above $8000 (like the stack): it runs with interrupts off, as the DOS's low memory (its
; interrupt vectors among it) and the program's code below $8000 are banked
; out meanwhile.  So one of src and dest must be in the window ($0000-$7fff,
; the page) and the other at $8000 or above.  (An NMI meanwhile would find
; no handler: the floppy controller's are only during disk work.)
;
bankcopy {
    const uword OPREG_COPY = $0078
    const ubyte ROUTINE_SIZE = 28
    uword routine
    ; (the routine's bytes: careful, a 0 followed by $30-$37 in an array
    ; loses a byte with prog8c-llvm, bugs/z80_array_zero_digit.p8; these
    ; have none)
    ubyte[] code = [
        $c5, $d5, $e5,          ; 0  push bc / push de / push hl
        $f3,                    ; 3  di
        $3e, 0,                 ; 4  ld a,PAGE          (5)
        $d3, $84,               ; 6  out ($84),a
        $21, 0, 0,              ; 8  ld hl,SRC          (9, 10)
        $11, 0, 0,              ; 11 ld de,DEST         (12, 13)
        $01, 0, 0,              ; 14 ld bc,COUNT        (15, 16)
        $ed, $b0,               ; 17 ldir
        $3e, 0,                 ; 19 ld a,BASE          (20)
        $d3, $84,               ; 21 out ($84),a
        $fb,                    ; 23 ei
        $e1, $d1, $c1,          ; 24 pop hl / pop de / pop bc
        $c9 ]                   ; 27 ret

    ; puts the routine at address (ROUTINE_SIZE bytes, above $8000)
    sub init(uword address) {
        ubyte i
        routine = address
        for i in 0 to len(code) - 1
            @(routine + i) = code[i]
    }

    ; copy count bytes (not 0) from src to dest with page 0 or 1 of the
    ; second 64 KB in the window
    sub copy(ubyte page, uword src, uword dest, uword count) {
        ubyte base = @(OPREG_COPY)
        if count == 0
            return
        @(routine + 5) = (base & %10001111) | (if page == 0 $60 else $70)
        @(routine + 9) = lsb(src)
        @(routine + 10) = msb(src)
        @(routine + 12) = lsb(dest)
        @(routine + 13) = msb(dest)
        @(routine + 15) = lsb(count)
        @(routine + 16) = msb(count)
        @(routine + 20) = base
        void call(routine)
    }

    ; is there a second 64 KB?  the window's first bytes, read with page 0
    ; in, are the same as the normal RAM's (the DOS's low memory) on a 64 KB
    ; machine, where port $84's page bits do nothing.  (reading only: a test
    ; write would land on the DOS on a 64 KB machine.)  buf: PROBE bytes,
    ; above $8000.
    const ubyte PROBE = 64
    sub present(uword buf) -> bool {
        ubyte i
        copy(0, $0000, buf, PROBE)
        for i in 0 to PROBE - 1
            if @(buf + i) != @(i)
                return true
        return false
    }
}
