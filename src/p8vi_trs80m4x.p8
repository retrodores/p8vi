; p8vi - a vi for 8-bit computers, written in Prog8.
; the TRS-80 Model 4 128 KB version (p8vi-trs80m4x): src/p8vi_trs80m4.p8
; with the text in the second 64 KB (the page store, src/trs80m4x), up to
; about 62 KB.  On a 64 KB Model 4 the text is in main RAM, less of it
; than with p8vi-trs80m4.  The page store's code is bigger than the gap
; buffer's: features are left out for room (see below).  The editor itself is in editor.p8, the C64
; version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).
features {
    const bool SPLASH = false   ; the start screen (off: room for page slots)
    const bool ASCII = false    ; (off: the TRS-80's text is ASCII already)
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool REPEAT_SUBST = true    ; & and :s on its own repeat the last :s (needs SUBST)
    const bool DOS = false      ; (CBM DOS only) :@ sends a command to the drive
    const bool FINAL_EOL = true ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = false   ; scroll the screen one row when the cursor goes just off it (off: room for page slots; drawing it all again is quick here)
    const bool DIR = false      ; (CBM DOS only) :@$ shows the disk directory
    const bool FONT = false     ; the C64 font build: oscii.fnt shows the ASCII characters (src/c64/font.p8)
    const bool ISO = false     ; (the X16) ISO mode: the text, keys and screen in ISO-8859-15, not PETSCII (p8vi-cx16iso)
    const bool SWITCH = false   ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
    const bool PREFIX = false   ; (CBM DOS only) :w keeps a drive or path prefix (0:name, //dir/:name) for the safe save
    const bool CTRL_AT = false   ; @ then a letter is Ctrl + the letter in normal mode (off: the Model 4 has a CTRL key)
    const bool MARKS = false   ; ma, 'a, `a: vi's marks a-z (28 buffer marks instead of 2) (off: room for page slots)
    const bool Z_VIEW = false   ; zt zz zb: the cursor row at the top, middle or bottom of the screen (off: room for page slots)
    const bool KEYFILE = false  ; (the test build, src/p8vi_trs80test.p8) the keys come from KEYS/TXT first
}
