; the TRS-80 Model 4 (z80-trs80-m4): a program trs80gp runs itself (with no
; command line) breaks the ENTER key, in the program and in the DOS after it,
; until a reset.  Typed at the DOS prompt the same program is fine.
; See bugs/trs80m4_enter_key.md.
;
;   prog8c-llvm -target llvm16 -triple z80-trs80-m4 -o build/enterkey bugs/trs80m4_enter_key.p8
;
; It prints sys.argc() and the arguments, then the code of each key
; (txt.getkey, @KBD).  BREAK twice quits.
%import textio
%zeropage basicsafe
main {
    sub start() {
        ubyte k
        ubyte last = 0
        uword i
        uword n = sys.argc()
        txt.print("argc ")
        txt.print_uw(n)
        txt.nl()
        i = 0
        while i < n and i < 4 {
            txt.print_uw(i)
            txt.print(": [")
            txt.print(sys.argv(i))
            txt.print("]")
            txt.nl()
            i++
        }
        txt.print("key codes, ENTER should be 13 (BREAK twice quits):")
        txt.nl()
        repeat {
            k = txt.getkey()
            if k != 0 {
                txt.print_ub(k)
                txt.spc()
                if k == 128 and last == 128 {
                    txt.nl()
                    return
                }
                last = k
            }
        }
    }
}
