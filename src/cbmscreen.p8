; screen rows on the C64 and the VIC-20 (screen memory with a row table,
; the one txt.setchr uses), in 6502 assembler.  platform.p8 of those
; targets makes these platform.put_row etc.

cbmscreen {

    ; put n characters of PETSCII text at text on screen row r, from column
    ; col: as screen codes, control characters as '.'.  the columns before
    ; col and after the text become spaces.  (one setchr call for every
    ; character took several times as long)
    asmsub put_row(ubyte r @Y, ubyte col @X, uword text @R0, ubyte n @A) clobbers(A, X, Y) {
        %asm {{
            sta  P8ZP_SCRATCH_B1        ; n
            stx  _col
            ; check for mega64 40/80
.if sys.target == 65
            lda  c65.VIDMODE            ; load VIC register
            and  #%10000000         ; Look only at the H640 40/80 flag
            beq  +
            tya
            asl  a
            tay
.endif
            ; the row's screen address
+           tya
            asl  a
            tay
            lda  txt.setchr._screenrows,y
            sta  P8ZP_SCRATCH_W2
            lda  txt.setchr._screenrows+1,y
            sta  P8ZP_SCRATCH_W2+1
            ; spaces up to col, then the address of col
            lda  #$20
            ldy  #0
            cpx  #0
            beq  _text
-           sta  (P8ZP_SCRATCH_W2),y
            iny
            dex
            bne  -
            tya
            clc
            adc  P8ZP_SCRATCH_W2
            sta  P8ZP_SCRATCH_W2
            bcc  _text
            inc  P8ZP_SCRATCH_W2+1
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
            sta  (P8ZP_SCRATCH_W2),y
            iny
            cpy  P8ZP_SCRATCH_B1
            bne  _char
_spaces
            ; spaces up to the end of the row (width - col)
            lda  p8b_main.p8v_SCREEN_WIDTH
            sec
            sbc  _col
            sta  P8ZP_SCRATCH_B1
            lda  #$20
-           cpy  P8ZP_SCRATCH_B1
            bcs  +
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  -
+           rts

_offsets    .byte  1, 0, 64, 32, 1, 192, 128, 128   ; 1: a control character
_col        .byte  0
            ; !notreached!
        }}
    }

    ; move screen rows first to last count rows up (up: row first+count to
    ; first ... last to last-count) or down (first to first+count ...
    ; last-count to last); the rows moved into aren't changed
    asmsub scroll_rows(ubyte first @X, ubyte last @Y, ubyte count @A, bool up @Pc) clobbers(A, X, Y) {
        %asm {{
            sta  _count
            stx  _first
            sty  _last
            bcc  _down
            ; up: row r+count to row r, for r = first to last-count
            tya
            sec
            sbc  _count
            sta  _end
-           txa
            clc
            adc  _count
            jsr  _copy
            cpx  _end
            beq  +
            inx
            bne  -
+           rts
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
            beq  +
            dex
            bne  -
+           rts
_copy
.if sys.target == 65
            tay
            lda  c65.VIDMODE            ; load VIC register
            and  #%10000000         ; Look only at the H640 40/80 flag
            beq  +
            tya
            asl  a
            tay
+           tya
.endif
            ; row a to row x (keeps x)
            asl  a
            tay
            lda  txt.setchr._screenrows,y
            sta  P8ZP_SCRATCH_W1
            lda  txt.setchr._screenrows+1,y
            sta  P8ZP_SCRATCH_W1+1
            txa
.if sys.target == 65
            tay
            lda  c65.VIDMODE            ; load VIC register
            and  #%10000000         ; Look only at the H640 40/80 flag
            beq  +
            tya
            asl  a
            tay
+           tya
.endif
            asl  a
            tay
            lda  txt.setchr._screenrows,y
            sta  P8ZP_SCRATCH_W2
            lda  txt.setchr._screenrows+1,y
            sta  P8ZP_SCRATCH_W2+1
            ldy  p8b_main.p8v_SCREEN_WIDTH
            dey
-           lda  (P8ZP_SCRATCH_W1),y
            sta  (P8ZP_SCRATCH_W2),y
            dey
            bpl  -
            rts

_count      .byte  0
_first      .byte  0
_last       .byte  0
_end        .byte  0
            ; !notreached!
        }}
    }
}
