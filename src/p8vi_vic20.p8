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
    const bool SPLASH = false   ; the start screen (off: the room went to the safe save)
    const bool ASCII = true     ; ASCII files translated to PETSCII and back, :set ascii
    const bool CRLF = true      ; CR LF line endings, :set crlf
    const bool SUBST = false    ; :s/old/new/ and line ranges (:%, :1,5, :$)
    const bool DOS = false      ; :@ sends a command to the drive (:@s:name deletes a file)
    const bool FINAL_EOL = false ; a line ending at the end of a file ends the last line (no empty line after it)
    const bool SCROLL = false    ; scroll the screen one row when the cursor goes just off it (not draw it all again)
    const bool DIR = false      ; :@$ shows the disk directory
    const bool FONT = false     ; the C64 font build: p8vi.fnt shows the ASCII characters (src/c64/font.p8)
}

; features.FONT again, for the assembler (charset.p8's tables).  In main:
; Prog8 leaves the features block out, asm and all (bugs/block_asm_dropped.p8)
main {
    %option merge
    %asm {{
FONT = 0
    }}
}
