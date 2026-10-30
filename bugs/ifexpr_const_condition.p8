; An if expression whose condition is a compile-time constant is not folded.
;
; compiler: prog8c 14.0-BETA3 (commit f1ab1ed4, branch llvm)
; targets:  c64 (6502 code generator; vic20 and cx16 the same)
; build:    prog8c-llvm -target c64 -asmlist -out build bugs/ifexpr_const_condition.p8
;
; expected: x = f(n), with no test and no code for g(n): FLAG is a constant,
;           the way an if statement with a constant condition is folded
;           (that one also warns "condition is always true").
; actual:   the constant is tested at run time and both values are compiled:
;               lda  #1
;               beq  p8_label_gen_..._ifexpr_false
;               ... jsr p8s_f ...
;               jmp  p8_label_gen_..._ifexpr_end
;           p8_label_gen_..._ifexpr_false
;               ... jsr p8s_g ...
;           so g() and its string stay in the program.
;
; why it matters: a const bool in another block works as a feature switch
; (src/p8vi.p8 and src/p8vi_vic20.p8 set them for the editor), and the if
; expression is the one way to write such a switch without a warning.

%import textio
%zeropage basicsafe

main {
    const bool FLAG = true
    uword @shared n = 5

    sub start() {
        uword x = if FLAG f(n) else g(n)
        txt.print_uw(x)
    }

    sub f(uword v) -> uword {
        return v + 1
    }

    sub g(uword v) -> uword {
        txt.print("never called")
        return v - 1
    }
}
