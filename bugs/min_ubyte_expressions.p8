; Compiler bug: min() of two ubyte expressions returns the second operand
;
; Compiler: prog8c 14.0-BETA3, git commit f1ab1ed4, branch llvm
; Targets:  6502 (seen on c64 and cx16); the virtual target is correct
;
; Build and run:
;   prog8c-llvm -target c64 -out build bugs/min_ubyte_expressions.p8
;   then run build/min_ubyte_expressions.prg (x64sc, or romdev's c64 core)
;
; Expected output: 16
; Actual output:   53
;
; The generated code pushes the second operand, computes the first one into
; A, then pla overwrites A before the compare, so both sides of the compare
; are the second operand:
;
;       ; A = b (from the line before)
;       sec
;       sbc  #2                 ; A = b - 2, the second operand
;       sta  P8ZP_SCRATCH_B1
;       pha                     ; saved on the stack
;       lda  p8b_main.p8v_a
;       clc
;       adc  #1                 ; A = 1 + a, the first operand...
;       pla                     ; ...lost: A = b - 2 again
;       sta  P8ZP_SCRATCH_B1
;       cmp  P8ZP_SCRATCH_B1    ; compares b - 2 with itself
;       bcc  +
;       lda  P8ZP_SCRATCH_B1
; +     sta  p8v_r              ; always b - 2
;
; Found in src/main.p8 (now src/editor.p8) as  view.column = min(1 + cmdlen, SCREEN_WIDTH - 2) ,
; which always put the command line cursor at SCREEN_WIDTH - 2.

%import textio
%zeropage basicsafe

main {
    ubyte @shared a
    ubyte @shared b

    sub start() {
        a = @($c000) & 15   ; runtime values so nothing is constant folded
        a |= 1              ; a = 15 on a C64 ($c000 is $ff after power on)
        b = a + 40          ; 55
        ; expected 16 (1 + a), the 6502 code prints 53 (b - 2)
        ubyte r = min(1 + a, b - 2)
        txt.print_ub(r)
        txt.nl()
    }
}
