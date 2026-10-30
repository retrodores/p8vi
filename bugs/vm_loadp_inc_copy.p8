; A byte copy loop through two uword pointers is wrong on the virtual target
;
;   prog8c-llvm -target virtual -emu bugs/vm_loadp_inc_copy.p8
;
; prints "1 2 3 4 5 6 7 8", should print "2 3 4 5 6 6 7 8" (the c64 code
; is right, and prog8c 12.3.4 prints the right thing on the virtual
; target).  The IR is
;
;   loadp_inc.b r2.b,[main.mb.src]
;   storep_inc.b r2.b,[main.mb.dest]
;
; which looks right, so the VM's loadp_inc / storep_inc seem to be wrong.
; In a bigger program the same loop stopped with "VM error: access of 1
; byte(s) at $c00ac008 is outside the VM's memory" (a 32 bit address).
; Seen with prog8c 14.0-BETA3 (f1ab1ed4).

%import textio
%zeropage basicsafe

main {
    ubyte[16] buf = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]

    sub mb(uword src, uword dest, uword count) {
        repeat count {
            @(dest) = @(src)
            src++
            dest++
        }
    }

    sub start() {
        ubyte i
        mb(&buf as uword + 1, &buf as uword, 5)
        for i in 0 to 7 {
            txt.print_ub(buf[i])
            txt.spc()
        }
        txt.nl()
    }
}
