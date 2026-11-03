;
; RAM mode on the Plus/4: the program runs with RAM at $8000-$fcff (written
; to $ff3f; $fd00-$ff3f is I/O either way), so it and its text get the RAM
; up to $fc00 instead of up to $8000.  The KERNAL ROM is switched in
; ($ff3e) only while it runs:
;
; - KERNAL calls: the RAM under the KERNAL's jump table ($ff49-$fff3) gets
;   a "jsr kernal" in every entry.  kernal (in low RAM, so it is still
;   there with the ROM in) works out the entry from its return address,
;   switches to the ROM, calls the ROM's entry, switches back and returns,
;   with A, X, Y and the flags as the ROM left them (and as the caller set
;   them, going in: PLOT and others take the carry).
; - SETNAM: the KERNAL reads the file name later, with the ROM in, so a
;   name above $8000 would read the ROM.  Its entry copies the name to
;   name_buf in low RAM first.
; - interrupts: in RAM mode the CPU takes the vector from the RAM at $fffe.
;   irq switches the ROM in and runs the KERNAL's handler ($fcb3), with a
;   return frame that comes back to irq_back, which switches back.  (the
;   pushed status has B clear: the KERNAL checks it for BRK)
;
; The KERNAL itself never takes an interrupt in RAM mode: BASIC reads the
; RAM under the ROM with interrupts off ($cfad in the KERNAL).
;
; The low code goes in the cassette buffer, $0353-$03f2 (Prog8's R0-R15 are
; at $0333-$0352, config/plus4.properties).  start() must run before any
; code above $8000 runs, and main.start begins with Prog8's own start-up
; (clearing the variables: prog8_lib, at the end of the program).  So the
; library's p8_sys_startup.init_system_phase2, the last thing before
; main.start, is replaced below to call it; src/p8vi_plus4.p8 imports
; platform (which imports rammode) first, so this block comes early in the
; program, below $8000.  On exit, the library's cleanup_at_exit switches
; the ROM back in.
;
rammode {
    %option force_output    ; start() is called from assembler only
    const uword LOW = $0353         ; where the low code goes (to $03f2)
    const ubyte NAME_MAX = 40       ; longest file name SETNAM passes on (the editor's are 40 at most)

    asmsub start() clobbers(A, X, Y) {
        %asm {{
            sei
            ; the low code (more than 128 bytes: counted up, not with bpl)
            ldx  #0
-           lda  _low_code,x
            sta  p8c_LOW,x
            inx
            cpx  #_low_end - _low
            bne  -
            ; the jump table under the ROM: jsr kernal in every entry, the
            ; Plus/4's own $ff49-$ff52 and the usual $ff81-$fff3
            ldx  #0
-           lda  #$20               ; jsr
            sta  $ff49,x
            lda  #<_kernal
            sta  $ff4a,x
            lda  #>_kernal
            sta  $ff4b,x
            inx
            inx
            inx
            cpx  #$ff55 - $ff49
            bne  -
            ldx  #0
-           lda  #$20               ; jsr
            sta  $ff81,x
            lda  #<_kernal
            sta  $ff82,x
            lda  #>_kernal
            sta  $ff83,x
            inx
            inx
            inx
            cpx  #$fff6 - $ff81
            bne  -
            ; SETNAM: jmp setnam
            lda  #$4c               ; jmp
            sta  $ffbd
            lda  #<_setnam
            sta  $ffbe
            lda  #>_setnam
            sta  $ffbf
            ; the vectors under the ROM
            lda  #<_nmi
            sta  $fffa
            lda  #>_nmi
            sta  $fffb
            lda  #<_irq
            sta  $fffe
            lda  #>_irq
            sta  $ffff
            sta  $ff3f              ; RAM in
            cli
            rts

            ; the low code, assembled for where it runs
_low_code
            .logical p8c_LOW
_low
_kernal
            php
            sta  _a
            pla
            sta  _p
            pla                     ; the return address: the entry + 2
            sec
            sbc  #2
            sta  _vec
            pla
            sbc  #0
            sta  _vec+1
            lda  _p
            pha
            lda  _a
            plp
            sta  $ff3e              ; ROM in (sta leaves A and the flags)
            jsr  _go
            sta  $ff3f              ; RAM in
            rts
_go         jmp  (_vec)

_setnam
            stx  _src+1
            sty  _src+2
            cmp  #p8c_NAME_MAX
            bcc  +
            lda  #p8c_NAME_MAX
+           sta  _a
            tay
            beq  _setnam_rom
-           dey
_src        lda  $ffff,y
            sta  _name,y
            cpy  #0
            bne  -
_setnam_rom
            lda  _a
            ldx  #<_name
            ldy  #>_name
            sta  $ff3e
            jsr  $ffbd
            sta  $ff3f
            ldx  _src+1
            ldy  _src+2
            rts

_irq
            pha                     ; A (put back by irq_back)
            lda  #>_irq_back        ; a return frame for the KERNAL's RTI
            pha
            lda  #<_irq_back
            pha
            lda  #%00100100         ; status: I set, B clear
            pha
            sta  $ff3e              ; ROM in
            jmp  $fcb3              ; the KERNAL's interrupt handler
_irq_back
            sta  $ff3f              ; RAM in
            pla
_nmi        rti

_a          .byte 0
_p          .byte 0
_vec        .word 0
_name       .fill p8c_NAME_MAX
_low_end
            .endlogical
            .cerror _low_end > $03f3, "the low code doesn't fit in the cassette buffer"
            ; !notreached!
        }}
    }
}

; (see above) RAM mode before main.start
p8_sys_startup {
    %option merge

    asmsub init_system_phase2() {
        %asm {{
            jsr  p8b_rammode.p8s_start
            cld
            clc
            clv
            rts
        }}
    }
}
