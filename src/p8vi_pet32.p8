; p8vi - a vi for 8-bit computers, written in Prog8.
; the PET version (a 32 KB PET with BASIC 4: the 4032; Prog8's pet32
; target): the program and the text share $0401-$7fff, so it leaves out
; the features the VIC-20 version leaves out, and ASCII and CR LF files
; too, for room for text.  The editor itself is in editor.p8, the full
; version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).  make size checks the room left.
features {
    const bool SPLASH = false   ; the start screen
    const bool ASCII = false    ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = false     ; CR LF line endings, :set crlf
    const bool SUBST = false    ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool REPEAT_SUBST = false   ; & and :s on its own repeat the last :s (needs SUBST)
    const bool DOS = false      ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = false ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = false    ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = false      ; :@$ shows the disk directory
    const bool FONT = false     ; the C64 font build: oscii.fnt shows the ASCII characters (src/c64/font.p8)
    const bool SWITCH = false    ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
    const bool PREFIX = true     ; :w keeps a drive or path prefix (0:name, //dir/:name) for the safe save (164 bytes)
    const bool CTRL_AT = true     ; @ then a letter is Ctrl + the letter in normal mode (for keyboards without Ctrl)
    const bool MARKS = true     ; ma, 'a, `a: vi's marks a-z (28 buffer marks instead of 2)
    const bool Z_VIEW = true    ; zt zz zb: the cursor row at the top, middle or bottom of the screen
}

; features.FONT again, for the assembler (charset.p8's tables).  In main:
; Prog8 leaves the features block out, asm and all (bugs/block_asm_dropped.p8)
main {
    %option merge
    %asm {{
FONT = 0
    }}
}
