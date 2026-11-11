; p8vi - a vi for 8-bit computers, written in Prog8.
; the CP/M version (CP/M 2.2 and later on a Z80, with a TPA of about 40 KB
; or more): a .com program built with the llvm16 target and the z80-cpm
; profile (llvm-z80 and z88dk), see src/cpm/platform.p8.  The editor
; itself is in editor.p8, the C64 version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).
features {
    const bool SPLASH = true    ; the start screen
    const bool ASCII = false    ; (off: CP/M's text is ASCII already)
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool REPEAT_SUBST = true    ; & and :s on its own repeat the last :s (needs SUBST)
    const bool DOS = false      ; (CBM DOS only) :@ sends a command to the drive
    const bool FINAL_EOL = true ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = true    ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = false      ; (CBM DOS only) :@$ shows the disk directory
    const bool FONT = false     ; the C64 font build: oscii.fnt shows the ASCII characters (src/c64/font.p8)
    const bool ISO = false     ; (the X16) ISO mode: the text, keys and screen in ISO-8859-15, not PETSCII (p8vi-cx16iso)
    const bool NUMBER = true    ; :set number: line numbers in front of the lines (about 750 bytes)
    const bool SWITCH = false   ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
    const bool PREFIX = true    ; :w keeps the drive prefix (B:NAME.TXT) for the safe save: p8vi.tmp goes on that drive
    const bool CTRL_AT = false   ; @ then a letter is Ctrl + the letter in normal mode (off: terminals have Ctrl)
    const bool MARKS = true    ; ma, 'a, `a: vi's marks a-z (28 buffer marks instead of 2)
    const bool Z_VIEW = true    ; zt zz zb: the cursor row at the top, middle or bottom of the screen
    const bool KEYFILE = false  ; (the test build) the keys come from KEYS.TXT first
}
