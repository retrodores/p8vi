; p8vi - a vi for 8-bit computers, written in Prog8.
; the VIC-20 version: the program must end below $8000 (text goes in block 5
; when there is RAM there), so it leaves out features when room runs out.
; new features that don't fit start out off here.  The editor itself is in
; editor.p8, the full version is src/p8vi.p8.

%import editor
%zeropage basicsafe

; which optional features the build has (code for the ones that are off
; is left out of the program).  make size checks the room left.
features {
    const bool SPLASH = true    ; the start screen
    const bool ASCII = true     ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true      ; CR LF line endings, :set crlf
}
