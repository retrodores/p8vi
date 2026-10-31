; p8vi - a vi for 8-bit computers, written in Prog8.
; the Commander X16 version: like src/p8vi.p8 (the C64's), but its main
; RAM is nearly full (the page store's code is big; the text is in banked
; RAM), so it leaves out features when room runs out.  The editor itself
; is in editor.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).  make size shows the room left.
features {
    const bool SPLASH = false   ; the start screen (off: main RAM is full)
    const bool ASCII = true     ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool DOS = true       ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = true ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = true     ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = true       ; :@$ shows the disk directory
}
