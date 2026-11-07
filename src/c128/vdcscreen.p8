; screen rows on the C128's 80 column VDC screen, in 6502 assembler: the
; same as src/cbmscreen.p8's routines for screen memory the CPU can see.
; platform.put_row and platform.scroll_rows (src/c128/platform.p8) pick
; these or those by txt.vdc.

vdcscreen {

    ; put n characters of PETSCII text at text on screen row r, from column
    ; col: as screen codes, control characters as '.'.  the columns before
    ; col and after the text become spaces.  (the VDC's data register steps
    ; to the next address after each byte)
    asmsub put_row(ubyte r @Y, ubyte col @X, uword text @R0, ubyte n @A) clobbers(A, X, Y) {
        %asm {{
            sta  P8ZP_SCRATCH_B1        ; n
            stx  _col
            ldx  #0
            jsr  txt.vdc_address        ; column 0 of row r
            lda  #txt.VDC_DATAREG
            sta  txt.VDC_ADDR
            ; spaces up to col
            ldx  _col
            beq  _text
            lda  #$20
-           bit  txt.VDC_ADDR
            bpl  -
            sta  txt.VDC_DATA
            dex
            bne  -
_text
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
            ldy  #0
            cpy  P8ZP_SCRATCH_B1
            beq  _spaces
_char
            ; PETSCII to a screen code (like txt.petscii2scr), control
            ; characters ($00-$1f, $80-$9f) as '.'
            lda  (P8ZP_SCRATCH_W1),y
            sta  P8ZP_SCRATCH_REG
            lsr  a
            lsr  a
            lsr  a
            lsr  a
            lsr  a
            tax
            lda  _offsets,x
            cmp  #1
            bne  +
            lda  #$2e
            bne  _put
+           eor  P8ZP_SCRATCH_REG
_put
-           bit  txt.VDC_ADDR
            bpl  -
            sta  txt.VDC_DATA
            iny
            cpy  P8ZP_SCRATCH_B1
            bne  _char
_spaces
            ; spaces up to the end of the row: width - col - n of them
            lda  p8b_main.p8v_SCREEN_WIDTH
            sec
            sbc  _col
            sec
            sbc  P8ZP_SCRATCH_B1
            beq  +
            bcc  +
            tax
            lda  #$20
-           bit  txt.VDC_ADDR
            bpl  -
            sta  txt.VDC_DATA
            dex
            bne  -
+           rts

_offsets    .byte  1, 0, 64, 32, 1, 192, 128, 128   ; 1: a control character
_col        .byte  0
            ; !notreached!
        }}
    }

    ; move screen rows first to last count rows up (up: row first+count to
    ; first ... last to last-count) or down (first to first+count ...
    ; last-count to last); the rows moved into aren't changed.  each row
    ; with the VDC's block copy (it copies upwards in memory only, so one
    ; row at a time, in the order that doesn't overwrite rows still to go)
    asmsub scroll_rows(ubyte first @X, ubyte last @Y, ubyte count @A, bool up @Pc) clobbers(A, X, Y) {
        %asm {{
            sta  _count
            stx  _first
            sty  _last
            php
            ; block copy mode (bit 7 of register 24; the rest kept)
            ldx  #txt.VDC_COPYMODE
            jsr  txt.vdc_read
            sta  _mode
            ora  #$80
            jsr  txt.vdc_write
            plp
            ldx  _first
            bcc  _down
            ; up: row r+count to row r, for r = first to last-count
            lda  _last
            sec
            sbc  _count
            sta  _end
-           txa
            clc
            adc  _count
            jsr  _copy
            cpx  _end
            beq  _done
            inx
            bne  -
_down
            ; down: row r-count to row r, for r = last down to first+count
            lda  _first
            clc
            adc  _count
            sta  _end
            ldx  _last
-           txa
            sec
            sbc  _count
            jsr  _copy
            cpx  _end
            beq  _done
            dex
            bne  -
_done
            lda  _mode
            ldx  #txt.VDC_COPYMODE
            jmp  txt.vdc_write

_copy
            ; row a to row x (keeps x)
            stx  _to
            ; the source: row a, column 0
            asl  a
            tay
            lda  txt.vdc_address._rows,y
            clc
            adc  txt.vdc_screen
            pha
            lda  txt.vdc_address._rows+1,y
            adc  txt.vdc_screen+1
            ldx  #txt.VDC_SOURCE_HI
            jsr  txt.vdc_write
            pla
            ldx  #txt.VDC_SOURCE_LO
            jsr  txt.vdc_write
            ; the destination: row x, column 0
            ldx  #0
            ldy  _to
            jsr  txt.vdc_address
            ; the count starts the copy
            lda  p8b_main.p8v_SCREEN_WIDTH
            ldx  #txt.VDC_COUNT
            jsr  txt.vdc_write
            ldx  _to
            rts

_count      .byte  0
_first      .byte  0
_last       .byte  0
_end        .byte  0
_to         .byte  0
_mode       .byte  0
            ; !notreached!
        }}
    }
}
