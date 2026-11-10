; llvm16 / z80 profiles: a ubyte array with a 0 followed by a byte $30-$37
; (an ASCII digit 0-7) loses a byte in the binary: 0, $31 becomes 1.
; Probably the array is written to the assembler as a string, the 0 as "\0",
; and "\0" + "1" is read as the octal escape \01.  See
; bugs/z80_array_zero_digit.md.
;
;   prog8c-llvm -target llvm16 -triple z80-test -emu bugs/z80_array_zero_digit.p8
;
; prints:
;   got:  11 01 01 07 02 00 38 03 00 00 04 67 6f 74
;   want: 11 00 31 01 00 37 02 00 38 03 00 00 30 04
; (there is no ok/FAIL check: LLVM folds data[i] to the initial values
; wherever it can, so only a loop like this one reads the real bytes; and a
; second array to compare with would be damaged the same way)
%import textio
%zeropage basicsafe
main {
    ubyte[] data = [$11, $00, $31, $01, $00, $37, $02, $00, $38, $03, $00, $00, $30, $04]
    sub start() {
        ubyte i
        txt.print("got:  ")
        for i in 0 to len(data) - 1 {
            txt.print_ubhex(data[i], false)
            txt.spc()
        }
        txt.nl()
        txt.print("want: 11 00 31 01 00 37 02 00 38 03 00 00 30 04")
        txt.nl()
    }
}
