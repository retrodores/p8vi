; Compiler bug: x*10 + x is folded into x*11 even when x is a function call
; with side effects, so the second call is dropped
;
; Compiler: prog8c 14.0-BETA3, git commit f1ab1ed4, branch llvm
; Targets:  all (c64, cx16 and the virtual target all print 11)
;
; Build and run:
;   prog8c-llvm -target virtual -emu bugs/side_effect_calls_merged.p8
;   prog8c-llvm -target c64 -out build bugs/side_effect_calls_merged.p8
;
; Expected output: 12   (next() returns 1, then 2: 1*10 + 2)
; Actual output:   11   (next() is called once: 1*11)
;
; Generated 6502 code for the expression:
;
;       jsr  p8b_main.p8s_next
;       jsr  prog8_math.mul_byte_11
;       sta  p8v_r
;
; This breaks the library: diskio.status_code() in shared_cbm_diskio.p8 is
;
;       push( (cbm.CHRIN()-'0') *10 + (cbm.CHRIN()-'0') )
;
; which compiles to one CHRIN and * 11, so the drive status "62, file not
; found" is returned as 66, and "01, files scratched" as 0.

%import textio
%zeropage basicsafe

main {
    ubyte counter

    ; returns 1, 2, 3, ... (a side effect, like reading a byte with CHRIN)
    sub next() -> ubyte {
        counter++
        return counter
    }

    sub start() {
        ; expected 1*10 + 2 = 12
        ubyte r = next() * 10 + next()
        txt.print_ub(r)
        txt.nl()
    }
}
