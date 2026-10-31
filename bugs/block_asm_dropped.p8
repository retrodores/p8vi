; A block with only consts and an %asm block is left out of the program,
; with its assembler, when main is in another module (here
; block_asm_dropped_main.p8).  %option force_output doesn't keep it.
;
;   prog8c-llvm -srcdirs bugs -target c64 -out build bugs/block_asm_dropped.p8
;
; fails in 64tass: "not defined symbol 'p8b_settings'".  With main in this
; file (move block_asm_dropped_main.p8's main block here) the block and its
; LEVEL symbol are in the program and it prints 7.  Seen with prog8c
; 14.0-BETA3 (f1ab1ed4); found in p8vi, where each toplevel's features
; block defines FONT for charset.p8's assembler tables.

%import block_asm_dropped_main
%zeropage basicsafe

settings {
    %option force_output
    const ubyte LEVEL = 7
    %asm {{
LEVEL = 7
    }}
}
