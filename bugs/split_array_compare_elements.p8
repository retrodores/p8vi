; Comparing two elements of a split uword array with constant indices
; doesn't assemble on the C64
;
;   prog8c-llvm -target c64 -out build bugs/split_array_compare_elements.p8
;
;   error: not defined symbol 'p8v_a'
;
; "a[0] < a[1]" is generated as
;
;   lda  p8v_a_lsb+0
;   ldy  p8v_a_msb+0
;   cmp  p8v_a+2          <- as if a were not split
;   tya
;   sbc  p8v_a+2+1
;
; (with a variable, "x = a[1]" first, it works.)  Seen with prog8c
; 14.0-BETA3 (f1ab1ed4).

%import textio
%zeropage basicsafe

main {
    uword[2] a = [5, 3]

    sub start() {
        if a[0] < a[1]
            txt.print("smaller\n")
        else
            txt.print("not smaller\n")
    }
}
