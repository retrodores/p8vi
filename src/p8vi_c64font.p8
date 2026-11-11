; p8vi - a vi for 8-bit computers, written in Prog8.
; the C64 font build (p8vi-c64font): the C64 REU build with a font loaded
; from oscii.fnt that has the ASCII characters PETSCII lacks (\ ^ _ ` { | } ~),
; for editing ASCII text.  An experiment, see src/c64/font.p8.  The editor
; itself is in editor.p8, the plain C64 version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program)
features {
    const bool SPLASH = true    ; the start screen
    const bool ASCII = true     ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool REPEAT_SUBST = true    ; & and :s on its own repeat the last :s (needs SUBST)
    const bool DOS = true       ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = true  ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = true     ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = true       ; :@$ shows the disk directory
    const bool FONT = true      ; the C64 font build: oscii.fnt shows the ASCII characters (src/c64/font.p8)
    const bool ISO = false     ; (the X16) ISO mode: the text, keys and screen in ISO-8859-15, not PETSCII (p8vi-cx16iso)
    const bool NUMBER = true    ; :set number: line numbers in front of the lines (about 750 bytes)
    const bool SWITCH = false    ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
    const bool PREFIX = true     ; :w keeps a drive or path prefix (0:name, //dir/:name) for the safe save (164 bytes)
    const bool CTRL_AT = false    ; @ then a letter is Ctrl + the letter in normal mode (for keyboards without Ctrl)
    const bool MARKS = false    ; ma, 'a, `a: vi's marks a-z (28 buffer marks instead of 2)
    const bool Z_VIEW = false   ; zt zz zb: the cursor row at the top, middle or bottom of the screen (off: the REU slots would not fit)
}

; features.FONT again, for the assembler (charset.p8's tables).  In main:
; Prog8 leaves the features block out, asm and all (bugs/block_asm_dropped.p8)
main {
    %option merge
    %asm {{
FONT = 1
    }}
}
