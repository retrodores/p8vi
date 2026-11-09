%import diskio
%import textio

;
; the C128 font build (p8vi-c128x with features.FONT): the font of the C64
; font build (src/c64/font.p8, oscii.fnt: the lowercase set with the ASCII
; characters PETSCII lacks), on either screen.  It is loaded to $f000 in
; bank 0, the RAM under the KERNAL ROM.
;
; 80 columns: copied into the VDC's lowercase character set (16 bytes per
; character there: the 8 of the font and 8 empty), and back from the ROM
; with DLCHR at the end.
;
; 40 columns: the VIC-II shows VIC bank 3 ($c000-$ffff), with the font at
; $f000 and the screen at $c400.  The KERNAL goes on writing at $0400 (it
; takes the screen from VM1, which says $0400 in any VIC bank): a CHROUT
; hook copies the row it wrote to the screen at $c400, the whole screen
; after a clear.  textio and cbmscreen draw through the screen row table
; txt.setchr._screenrows, which start() moves; reading the screen there
; needs the KERNAL ROM banked out (txt.getchr and platform.scroll_rows).
; ($ff00-$ffff can't hold the font: the MMU registers are there.)
;
; Both are set up at the start, whichever screen is active, so the 40/80
; key can switch screens (features.SWITCH): the hook copies only while the
; 40 column screen is the KERNAL's, and screen() sets VM1 again after the
; switch (lowercase changes it).
;
font {
    const uword SCREEN = $c400
    const uword CHARS = $f000
    ; VM1 (the KERNAL copies it to the VIC-II's memory pointers): the
    ; screen at $0400 and the characters at $3000 in the VIC bank
    const ubyte VM1_FONT = $1c
    ; and at the end: the screen at $0400, the ROM's lowercase characters
    ; (p8vi leaves the screen lowercase)
    const ubyte VM1_ROM = $16
    ; how far the screen rows move
    const ubyte MOVE = msb(SCREEN) - $04

    str FILE = "oscii.fnt"
    bool shown              ; the font is on the screen
    uword old_chrout

    ; load the font and show it.  returns false if oscii.fnt didn't load.
    sub start() -> bool {
        bool failed
        cbm.SETNAM(len(FILE), FILE)
        cbm.SETLFS(1, diskio.drivenumber, 0)
        failed, void, void = cbm.LOAD(0, CHARS)
        if failed
            return false
        shown = true
        to_vdc()
        mirror_all()
        set_bank(%00)
        screen()
        move_rows(MOVE)
        sys.set_irqd()
        old_chrout = cbm.IBSOUT
        cbm.IBSOUT = &chrout_hook
        sys.clear_irqd()
        return true
    }

    ; the font on the 40 column screen again (after a switch to it)
    sub screen() {
        c128.VM1 = VM1_FONT
    }

    ; back to the ROM's font on both screens (and the 40 column screen at
    ; $0400)
    sub stop() {
        shown = false
        c128.DLCHR()
        sys.set_irqd()
        cbm.IBSOUT = old_chrout
        sys.clear_irqd()
        set_bank(%11)
        c128.VM1 = VM1_ROM
        move_rows(256 - MOVE)       ; (back, modulo 256)
    }

    ; the VIC bank is CIA 2 port A bits 0 and 1, inverted: %11 is bank 0
    ; (the other bits are the serial bus and RS-232)
    sub set_bank(ubyte bits) {
        c64.CIA2DDRA |= %00000011
        c64.CIA2PRA = (c64.CIA2PRA & %11111100) | bits
    }

    ; add delta to the high byte of each of the 25 screen row addresses
    asmsub move_rows(ubyte delta @A) clobbers(A, X) {
        %asm {{
            sta  P8ZP_SCRATCH_B1
            ldx  #2*24+1
-           lda  txt.setchr._screenrows,x
            clc
            adc  P8ZP_SCRATCH_B1
            sta  txt.setchr._screenrows,x
            dex
            dex
            bpl  -
            rts
        }}
    }

    ; the KERNAL's screen ($0400) to the font's ($c400)
    asmsub mirror_all() clobbers(X) {
        %asm {{
            ldx  #0
-           lda  $0400,x
            sta  $c400,x
            lda  $0500,x
            sta  $c500,x
            lda  $0600,x
            sta  $c600,x
            lda  $0700,x
            sta  $c700,x
            inx
            bne  -
            rts
        }}
    }

    ; CHROUT, then (output to the 40 column screen) the KERNAL's row to the font's
    ; screen: the row PNT ($e0, the 40 column editor's) points at, or all
    ; of it after a clear.  keeps A, X, Y and the flags CHROUT returns.
    asmsub chrout_hook() {
        %asm {{
            sta  _char
            jsr  _old
            php
            pha
            txa
            pha
            tya
            pha
            lda  $9a                    ; DFLTO: the output device
            cmp  #3
            bne  _done
            bit  $d7                    ; MODE: bit 7 set on 80 columns
            bmi  _done
            lda  _char
            cmp  #147
            bne  _row
            jsr  p8b_font.p8s_mirror_all
            jmp  _done
_row
            lda  P8ZP_SCRATCH_W1
            pha
            lda  P8ZP_SCRATCH_W1+1
            pha
            lda  $e0
            sta  P8ZP_SCRATCH_W1
            lda  $e1
            clc
            adc  #p8b_font.p8c_MOVE
            sta  P8ZP_SCRATCH_W1+1
            ldy  #39
-           lda  ($e0),y
            sta  (P8ZP_SCRATCH_W1),y
            dey
            bpl  -
            pla
            sta  P8ZP_SCRATCH_W1+1
            pla
            sta  P8ZP_SCRATCH_W1
_done
            pla
            tay
            pla
            tax
            pla
            plp
            rts
_old
            jmp  (p8b_font.p8v_old_chrout)
_char       .byte  0
            ; !notreached!
        }}
    }

    ; the font at CHARS into the VDC's second (lowercase) character set,
    ; at the character base (register 28, bits 7-5) + $1000
    asmsub to_vdc() clobbers(A, X, Y) {
        %asm {{
            php
            sei
            ldx  #28
            jsr  txt.vdc_read
            and  #$e0
            clc
            adc  #$10
            ldx  #txt.VDC_UPDATE_HI
            jsr  txt.vdc_write
            lda  #0
            ldx  #txt.VDC_UPDATE_LO
            jsr  txt.vdc_write
            lda  #<p8b_font.p8c_CHARS
            sta  P8ZP_SCRATCH_W1
            lda  #>p8b_font.p8c_CHARS
            sta  P8ZP_SCRATCH_W1+1
            ; the RAM under the KERNAL, and the I/O
            lda  c128.MMUCR
            pha
            lda  #$3e
            sta  c128.MMUCR
            lda  #txt.VDC_DATAREG
            sta  txt.VDC_ADDR
            ldx  #0
_char
            ldy  #0
_byte
            lda  (P8ZP_SCRATCH_W1),y
_wait1
            bit  txt.VDC_ADDR
            bpl  _wait1
            sta  txt.VDC_DATA
            iny
            cpy  #8
            bne  _byte
            lda  #0
_empty
            bit  txt.VDC_ADDR
            bpl  _empty
            sta  txt.VDC_DATA
            iny
            cpy  #16
            bne  _empty
            lda  P8ZP_SCRATCH_W1
            clc
            adc  #8
            sta  P8ZP_SCRATCH_W1
            bcc  +
            inc  P8ZP_SCRATCH_W1+1
+           inx
            bne  _char
            pla
            sta  c128.MMUCR
            plp
            rts
        }}
    }
}
