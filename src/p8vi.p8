; p8vi - a vi for 8-bit computers, written in Prog8.
; the full editor, for the C64 and the Commander X16.  The editor itself is
; in editor.p8; src/p8vi_vic20.p8 builds the VIC-20's smaller version.

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
    const bool DIR = true       ; :@$ shows the disk directory
}
