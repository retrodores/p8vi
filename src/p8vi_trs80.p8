; p8vi - a vi for 8-bit computers, written in Prog8.
; the TRS-80 Model III version, for LDOS: a .cmd program built with the
; llvm16 target and the z80-trs80-cmd profile (llvm-z80 and z88dk), see
; src/trs80/platform.p8.  The editor itself is in editor.p8, the C64
; version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).
features {
    const bool SPLASH = true    ; the start screen
    const bool ASCII = false    ; (off: the TRS-80's text is ASCII already)
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool REPEAT_SUBST = true    ; & and :s on its own repeat the last :s (needs SUBST)
    const bool DOS = false      ; (CBM DOS only) :@ sends a command to the drive
    const bool FINAL_EOL = true ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = true    ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = false      ; (CBM DOS only) :@$ shows the disk directory
    const bool FONT = false     ; the C64 font build: oscii.fnt shows the ASCII characters (src/c64/font.p8)
    const bool SWITCH = false   ; (the C128) the 40/80 DISPLAY key switches the screen while p8vi runs
    const bool PREFIX = false   ; (CBM DOS only) :w keeps a drive or path prefix (0:name, //dir/:name) for the safe save
    const bool CTRL_AT = true    ; @ then a letter is Ctrl + the letter in normal mode (for keyboards without Ctrl)
    const bool MARKS = false   ; ma, 'a, `a: vi's marks a-z (28 buffer marks instead of 2)
    const bool KEYFILE = false  ; (the test build, src/p8vi_trs80test.p8) the keys come from KEYS/TXT first
}
