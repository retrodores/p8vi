; c128 target: a program bigger than about 9 KB never starts
;
; Compiler: prog8c-llvm v14.0-BETA3 (git adcfe18e, branch llvm); the c128
; startup code is the same in prog8c-beta (master a4b59f6b), see below.
; Target: c128 (not c64, cx16, pet32: their startup is under no ROM)
;
; Build and run:
;   prog8c-llvm -target c128 -asmlist -out build bugs/c128_startup_under_basic_rom.p8
;   x128 -autostart build/c128_startup_under_basic_rom.prg
;
; Expected: "hello c128" on the screen.
; Actual: it never prints; the C128 runs into BASIC ROM and crashes (in
; p8vi: back at READY with garbage, or stuck in bank 1 with $ff00 = $7f).
;
; prog8_entrypoint (at $1c17, right after the BASIC stub) calls
; p8_sys_startup.init_system, which the compiler places after the program's
; code -- here above $4000.  At that point the KERNAL's bank 15 is still
; selected, with the BASIC ROM at $4000-$bfff, so the jsr goes into ROM.
; init_system itself is what banks the BASIC ROM out ($ff00 = $0e):
;
;   .1c17  prog8_entrypoint
;   .1c17  d8          cld
;   .1c18  ba          tsx
;   .1c19  8e 08 91    stx  prog8_lib.orig_stackpointer   ; also above $4000 in p8vi
;   .1c1c  20 79 61    jsr  p8_sys_startup.init_system    ; $6179: BASIC ROM
;   ...
;   .6179  init_system
;   .6179  78          sei
;   .617a  a9 00       lda  #0
;   .617c  8d 00 ff    sta  c128.MMUCR      ; select default bank 15
;   ...
;   .6188  a9 0e       lda  #%00001110
;   .618a  8d 00 ff    sta  c128.MMUCR      ; bank out basic rom
;
; (the stx to orig_stackpointer, a BSS variable, goes to the RAM under
; the ROM, which is fine; the jsr is not.)  A fix: bank the BASIC ROM out
; in prog8_entrypoint itself, before anything above $3fff is used.
;
; The same at the end: cleanup_at_exit (also after the program's code)
; starts with "lda #0 : sta $ff00", switching the BASIC ROM in under its
; own feet -- p8vi's :q crashes into BASIC with garbage on the screen.
; init_system has the same "lda #0 : sta $ff00" before IOINIT/RESTOR/CINT;
; with $0e instead (BASIC out, KERNAL and I/O in) those still work.
;
; %option no_sysinit doesn't avoid it: prog8_entrypoint still calls
; init_system_phase2 and jumps to cleanup_at_exit, both above $4000.
;
; How p8vi was tested meanwhile (not in the repo): built with %option
; no_sysinit, and the BASIC stub patched to "SYS7179:" followed by
;   a9 0e        lda  #$0e
;   a2 01        ldx  #1
;   9d ff fe     sta  $feff,x     ; $ff00 = $0e without a 0 byte in the line
;   d0 03        bne  prog8_entrypoint
; (a 0 byte would end the BASIC line, and BASIC's relinking after LOAD
; then hangs.)

%import textio
%zeropage basicsafe
%option no_sysinit

main {
    sub start() {
        filler()
        txt.print("hello c128\n")
        repeat {
        }
    }

    ; 16 KB of code, so the startup code ends up above $4000
    sub filler() {
        %asm {{
            rts
            .fill 16384, $ea
        }}
    }
}
