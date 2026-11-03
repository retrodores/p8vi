; the text stores' byte scans and copies: in 6502 assembler (src/fastmem.p8).
; the page store needs them (on the PET and VIC-20 the gap buffer has its
; own Prog8 loops instead)
%import fastmem

fastmem {
%option merge
    const bool FAST = true
}
