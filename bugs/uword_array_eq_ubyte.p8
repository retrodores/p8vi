; Comparing a uword array element with a ubyte variable reads the byte
; after the ubyte as its high byte (6502 code)
;
;   prog8c-llvm -target c64 -out build bugs/uword_array_eq_ubyte.p8
;   x64sc -default -warp -debugcart -autostartprgmode 1 -autostart build/uword_array_eq_ubyte.prg
;
; prints "found 2" if right.  The generated code for "arr[s] == id" is
;
;   ldy  p8v_s
;   lda  p8v_arr_lsb,y
;   ldx  p8v_arr_msb,y
;   ...
;   cmp  p8v_id
;   bne  +
;   cpy  p8v_id+1        <- id is a ubyte: this is the next variable
;
; so it only matches if the byte after id happens to be 0.  Here it
; prints "found 255": nothing found.  With "arr[s] == id as uword" it
; works.  Seen with prog8c 14.0-BETA3 (f1ab1ed4); found in p8vi's
; src/c64reu/pagemem_platform.p8, where it made the REU cache load a page
; a second time.

%import textio
%zeropage basicsafe

main {
    uword[4] arr = [5, 6, 3, 9]

    sub find(ubyte id) -> ubyte {
        ubyte s
        for s in 0 to 3 {
            if arr[s] == id
                return s
        }
        return 255
    }

    sub start() {
        txt.print("found ")
        txt.print_ub(find(3))
        txt.nl()
        repeat 5 sys.waitvsync()
        @($d7ff) = 0
    }
}
