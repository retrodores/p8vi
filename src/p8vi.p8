; p8vi - a vi for 8-bit computers, written in Prog8.
; the full editor, for the C64.  The editor itself is in editor.p8;
; src/p8vi_cx16.p8 and src/p8vi_vic20.p8 build the X16's and the VIC-20's
; versions.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program)
features {
    const bool SPLASH = true    ; the start screen
    const bool ASCII = true     ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = true     ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool DOS = true       ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = true  ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool DIR = true       ; :@$ shows the disk directory
}
