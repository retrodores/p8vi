; p8vi - a vi for 8-bit computers, written in Prog8.
; the C128 bank 1 build (p8vi-c128x): src/p8vi_c128.p8 with the text in
; RAM bank 1 (the page store, src/c128bank1), up to about 60 KB.  The page
; store's code is bigger than the gap buffer's: features are left out for
; room (see below).  It is also a font build: p8vi.fnt, if it is on the
; disk, shows the ASCII characters PETSCII lacks (src/c128font/font.p8).

%import editor
%zeropage basicsafe
; the C128 KERNAL changes $92 and $a4 during disk I/O (its tape and serial
; bytes, found by comparing the zero page before and after reading and
; writing files), but Prog8's c128 target hands them out as free
; (bugs/c128_zeropage_kernal_clobbers.p8): p8vi's mode variable at $92
; was overwritten by loading a file.  (in the main module: elsewhere
; %zpreserved has no effect)
%zpreserved $92,$92
%zpreserved $a4,$a4
; and Prog8's c128 basicsafe zero page includes BASIC 7's TEMPPT ($18):
; left at 1 by p8vi, BASIC printed garbage after each string after :q
; (bugs/c128_basicsafe_temppt.p8)
%zpreserved $18,$18

; which optional features the build has (code for the ones that are off
; is left out of the program)
features {
    const bool SPLASH = false   ; the start screen (off: room for page slots)
    const bool ASCII = true     ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool DOS = true       ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = true  ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = true     ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = false      ; :@$ shows the disk directory (off: room for page slots)
    const bool FONT = true      ; the font build: p8vi.fnt shows the ASCII characters (src/c128font/font.p8)
    const bool SWITCH = false    ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
}

; features.FONT again, for the assembler (charset.p8's tables).  In main:
; Prog8 leaves the features block out, asm and all (bugs/block_asm_dropped.p8)
main {
    %option merge
    %asm {{
FONT = 1
    }}
}
