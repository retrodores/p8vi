; p8vi - a vi for 8-bit computers, written in Prog8.
; the MEGA65 page store build (p8vi-mega65dma): the text in chip RAM banks
; 4 and 5, through DMA (src/mega65dma), and the ROM's character set with
; the ASCII characters PETSCII lacks (src/mega65/font.p8).  The program has
; to end below $c000, so optional features start out off here and go on as
; room allows.  The editor itself is in editor.p8, the full
; version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).  make size checks the room left.
features {
    const bool SPLASH = false   ; the start screen (off: the room went to attic RAM detection)
    const bool ASCII = true    ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true     ; CR LF line endings, :set crlf
    const bool SUBST = false    ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool DOS = true      ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = true ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = true    ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = false      ; :@$ shows the disk directory
    const bool FONT = true      ; the font build: a character set with the ASCII characters (src/mega65/font.p8)
    const bool SWITCH = false    ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
    const bool PREFIX = false    ; :w keeps a drive or path prefix (0:name, //dir/:name) for the safe save (164 bytes)
    const bool CTRL_AT = false    ; @ then a letter is Ctrl + the letter in normal mode (for keyboards without Ctrl)
    const bool MARKS = false    ; ma, 'a, `a: vi's marks a-z (28 buffer marks instead of 2)
}

; features.FONT again, for the assembler (charset.p8's tables).  In main:
; Prog8 leaves the features block out, asm and all (bugs/block_asm_dropped.p8)
main {
    %option merge
    %asm {{
FONT = 1
    }}
}
