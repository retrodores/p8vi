; Text format conversions in memory: ASCII <-> PETSCII and line endings.
;
; The ASCII <-> PETSCII mapping is one to one over all 256 byte values, so
; translating to PETSCII and back gives the original bytes, whatever they are:
;   ASCII a-z ($61-$7a) <-> PETSCII lowercase ($41-$5a)
;   ASCII A-Z ($41-$5a) <-> PETSCII uppercase ($c1-$da)
;   ASCII $c1-$da       <-> PETSCII $61-$7a (the other uppercase codes)
;   ASCII _ | ~         <-> PETSCII $a4 $dd $de (the keys typed for them)
; everything else stays the same, line endings too.  The font build
; (features.FONT, src/c64/font.p8) keeps _ and maps the characters its font
; shows instead (its own pair table):
;   ASCII ` { | } ~     <-> PETSCII $c0 $db $dc $dd $de
; (\ ^ _ are the same codes in both)
; (in assembly, to keep the editor small enough for the VIC-20)

charset {
    ; the modes of translate()
    const ubyte TO_PETSCII = 0
    const ubyte TO_ASCII = 1
    const ubyte SWAP_EOL = 2      ; CR <-> LF, nothing else

    ; translate count bytes at p in place
    asmsub translate(uword p @R0, uword count @R1, ubyte mode @Y) clobbers(A, X, Y) {
        %asm {{
            ; the pairs to look at, from r2L down to r2H
            lda  _pair_top,y
            sta  cx16.r2L
            lda  _pair_bottom,y
            sta  cx16.r2H
            ; the letter ranges start at mode * 3
            tya
            sta  P8ZP_SCRATCH_REG
            asl  a
            adc  P8ZP_SCRATCH_REG
            sta  P8ZP_SCRATCH_REG
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
_next
            lda  cx16.r1
            ora  cx16.r1+1
            beq  _done
            ldy  #0
            lda  (P8ZP_SCRATCH_W1),y
            sta  P8ZP_SCRATCH_B1
            ; three ranges of 26 letters for this mode
            ldx  P8ZP_SCRATCH_REG
            ldy  #3
_range
            lda  P8ZP_SCRATCH_B1
            sec
            sbc  _from,x
            cmp  #26
            bcc  _letter
            inx
            dey
            bne  _range
            ; the pairs that swap (the same both ways)
            lda  P8ZP_SCRATCH_B1
            ldx  cx16.r2L
_pair
            cmp  _pairs,x
            beq  _swap
            cpx  cx16.r2H
            beq  _store
            dex
            bpl  _pair
_swap
            txa
            eor  #1
            tax
            lda  _pairs,x
            jmp  _store
_letter
            clc
            adc  _to,x
_store
            ldy  #0
            sta  (P8ZP_SCRATCH_W1),y
            inc  P8ZP_SCRATCH_W1
            bne  +
            inc  P8ZP_SCRATCH_W1+1
+           lda  cx16.r1
            bne  +
            dec  cx16.r1+1
+           dec  cx16.r1
            jmp  _next
_done
            rts

            ; per mode: TO_PETSCII, TO_ASCII, SWAP_EOL (its letters stay the same)
_from       .byte  $41, $61, $c1,  $c1, $41, $61,  $41, $41, $41
_to         .byte  $c1, $41, $61,  $41, $61, $c1,  $41, $41, $41
            .if  p8b_main.FONT == 0
_pair_top   .byte  5, 5, 7
_pair_bottom .byte 0, 0, 6
_pairs      .byte  $5f, $a4, $7c, $dd, $7e, $de,  $0d, $0a
            .else
_pair_top   .byte  9, 9, 11
_pair_bottom .byte 0, 0, 10
_pairs      .byte  $60, $c0, $7b, $db, $7c, $dc, $7d, $dd, $7e, $de,  $0d, $0a
            .endif
            ; !notreached! (tables, after the rts)
        }}
    }

    ; remove the LF of each CR LF pair in the count bytes at p.
    ; returns the number of bytes left.
    asmsub crlf_to_cr(uword p @R0, uword count @R1) clobbers(X) -> uword @AY {
        %asm {{
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            sta  P8ZP_SCRATCH_W2
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
            sta  P8ZP_SCRATCH_W2+1
            ldx  #0                 ; the byte before
_next
            lda  cx16.r1
            ora  cx16.r1+1
            beq  _done
            ldy  #0
            lda  (P8ZP_SCRATCH_W1),y
            cmp  #$0a
            bne  _keep
            cpx  #$0d
            beq  _skip
_keep
            sta  (P8ZP_SCRATCH_W2),y
            inc  P8ZP_SCRATCH_W2
            bne  _skip
            inc  P8ZP_SCRATCH_W2+1
_skip
            tax
            inc  P8ZP_SCRATCH_W1
            bne  +
            inc  P8ZP_SCRATCH_W1+1
+           lda  cx16.r1
            bne  +
            dec  cx16.r1+1
+           dec  cx16.r1
            jmp  _next
_done
            lda  P8ZP_SCRATCH_W2
            sec
            sbc  cx16.r0
            tax
            lda  P8ZP_SCRATCH_W2+1
            sbc  cx16.r0+1
            tay
            txa
            rts
        }}
    }

    ; guess whether text is ASCII from the letters in it (looking at the
    ; first 4 KB at most).  PETSCII uppercase never appears in ASCII; ASCII
    ; text has more lowercase than uppercase.  Without letters, or as many
    ; of each, lf decides (LF line endings come from other systems).
    asmsub looks_ascii(uword p @R0, uword count @R1, bool lf @Y) clobbers(X, Y) -> bool @A {
        %asm {{
            sty  P8ZP_SCRATCH_REG
            lda  cx16.r0
            sta  P8ZP_SCRATCH_W1
            lda  cx16.r0+1
            sta  P8ZP_SCRATCH_W1+1
            lda  cx16.r1+1
            cmp  #$10
            bcc  +
            lda  #$10
            sta  cx16.r1+1
            lda  #0
            sta  cx16.r1
+           ; lowercase minus uppercase letters, low byte in X, high in r2
            ldx  #0
            stx  cx16.r2
_next
            lda  cx16.r1
            ora  cx16.r1+1
            beq  _end
            ldy  #0
            lda  (P8ZP_SCRATCH_W1),y
            sec
            sbc  #$c1
            cmp  #26
            bcc  _no
            lda  (P8ZP_SCRATCH_W1),y
            sec
            sbc  #$61
            cmp  #26
            bcs  +
            inx
            bne  _step
            inc  cx16.r2
            jmp  _step
+           lda  (P8ZP_SCRATCH_W1),y
            sec
            sbc  #$41
            cmp  #26
            bcs  _step
            txa
            bne  +
            dec  cx16.r2
+           dex
_step
            inc  P8ZP_SCRATCH_W1
            bne  +
            inc  P8ZP_SCRATCH_W1+1
+           lda  cx16.r1
            bne  +
            dec  cx16.r1+1
+           dec  cx16.r1
            jmp  _next
_end
            lda  cx16.r2
            bmi  _no
            bne  _yes
            txa
            bne  _yes
            lda  P8ZP_SCRATCH_REG
            rts
_yes
            lda  #1
            rts
_no
            lda  #0
            rts
        }}
    }
}
