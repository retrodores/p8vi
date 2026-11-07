%import diskio
%import strings
%import textio

;
; platform specific -- could merge to main
;
platform {
    ; main memory for the text, set by init() (the page store keeps it in
    ; banked RAM, see pagemem_platform.p8)
    pointer textstart
    pointer texttop         ; 1 byte past the last usable byte
    ; optional spare memory elsewhere, used for the yank buffer, undo log and
    ; key buffers when they fit (otherwise they come off the top of the text
    ; memory)
    pointer sparestart
    pointer sparetop

    sub init() {
       textstart = sys.progend()
       texttop = $9f00
       ; spare memory for the key buffers: the end of golden RAM, after the
       ; page store's buffers.  (not banked RAM: the page store switches
       ; banks to get at the text; it keeps the yank buffer and undo log)
       sparestart = pagemem.scratch + pagemem.SCRATCH_SIZE
       sparetop = $0800
       main.SCREEN_WIDTH    = txt.DEFAULT_WIDTH
       main.SCREEN_HEIGHT   = txt.DEFAULT_HEIGHT
       main.STATUS_HEIGHT   = 2
       main.MIN_COL         = 3
       main.MAX_COL         = main.SCREEN_WIDTH - 1
       main.MIN_ROW         = 0
       main.MAX_ROW         = main.SCREEN_HEIGHT - main.STATUS_HEIGHT - 1
       main.STATUS_LINE     = main.SCREEN_HEIGHT - 1
    }

    ; before the program ends (nothing to undo here)
    sub stop() {
    }

    ; (the C128: the 40/80 DISPLAY key switches the screen, see
    ; src/c128/platform.p8; not here)
    const bool SWITCH = false
    sub switch_wanted() -> bool {
        return false
    }
    sub switch_screen() {
    }

    ; (font builds only; there is none here)
    sub font_mode(bool ascii) -> bool {
        return false
    }

    ; open a file for writing with diskio.f_write as a SEQ file.
    ; the cx16 diskio.f_open_w adds ",s,w" and checks the drive status itself.
    ; the file must not exist yet.
    sub open_write(str name) -> bool {
        return diskio.f_open_w(name)
    }
    ; put n characters of PETSCII text at text on screen row r, from column
    ; col: as screen codes, control characters as '.'.  the columns before
    ; col and after the text become spaces.  (into VERA's text map with an
    ; increment of 2: the characters, not their colors)
    asmsub put_row(ubyte r @Y, ubyte col @X, uword text @R0, ubyte n @A) clobbers(A, X, Y) {
        %asm {{
            sta  P8ZP_SCRATCH_B1        ; n
            stx  _col
            stz  cx16.VERA_CTRL
            lda  #(txt.VERA_TEXTMATRIX >> 16) | $20
            sta  cx16.VERA_ADDR_H
            stz  cx16.VERA_ADDR_L
            tya
            clc
            adc  #>txt.VERA_TEXTMATRIX
            sta  cx16.VERA_ADDR_M
            ; spaces up to col
            lda  #$20
            cpx  #0
            beq  +
-           sta  cx16.VERA_DATA0
            dex
            bne  -
+           lda  cx16.r0
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
            bra  _put
+           eor  P8ZP_SCRATCH_REG
_put
            sta  cx16.VERA_DATA0
            iny
            cpy  P8ZP_SCRATCH_B1
            bne  _char
_spaces
            ; spaces up to the end of the row (width - col - n)
            lda  p8b_main.p8v_SCREEN_WIDTH
            sec
            sbc  _col
            sec
            sbc  P8ZP_SCRATCH_B1
            beq  +
            bcc  +
            tax
            lda  #$20
-           sta  cx16.VERA_DATA0
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
    ; last-count to last); the rows moved into aren't changed.  (VERA's
    ; data port 0 reads a row, port 1 writes it: the characters, not their
    ; colors)
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
            beq  _done
            inx
            bra  -
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
            bra  -
_done
            stz  cx16.VERA_CTRL
            rts
_copy
            ; row a to row x (keeps x)
            ldy  #0
            sty  cx16.VERA_CTRL     ; port 0: from
            jsr  _addr
            ldy  #1
            sty  cx16.VERA_CTRL     ; port 1: to
            txa
            jsr  _addr
            ldy  p8b_main.p8v_SCREEN_WIDTH
-           lda  cx16.VERA_DATA0
            sta  cx16.VERA_DATA1
            dey
            bne  -
            rts
_addr
            ; the selected port to the start of row a, an increment of 2
            clc
            adc  #>txt.VERA_TEXTMATRIX
            sta  cx16.VERA_ADDR_M
            stz  cx16.VERA_ADDR_L
            lda  #(txt.VERA_TEXTMATRIX >> 16) | $20
            sta  cx16.VERA_ADDR_H
            rts

_count      .byte  0
_first      .byte  0
_last       .byte  0
_end        .byte  0
            ; !notreached!
        }}
    }
}

;
; Lets try merging this straight into main for now
;
main {
%option merge

    ; screen geometry
    ; per platform and reconfigured per screen mode
    ubyte SCREEN_WIDTH    ; for now
    ubyte SCREEN_HEIGHT   ; for now
    ubyte STATUS_HEIGHT   ; status line size
    ubyte MIN_COL         ; text start column
    ubyte MAX_COL         ; max text column
    ubyte MIN_ROW         ; text start row
    ubyte MAX_ROW         ; max text rows
    ubyte STATUS_LINE     ; what row for the status line

    ; special characters
    const ubyte CHAR_CURSOR     = ' ' + 128

    ; control style keys
    const ubyte KEY_ESCAPE      = 27
    const ubyte KEY_CONTROL_L   = 12

    ; numbers & letters
    const ubyte KEY_0           = '0'
    const ubyte KEY_1           = '1'
    const ubyte KEY_2           = '2'
    const ubyte KEY_3           = '3'
    const ubyte KEY_4           = '4'
    const ubyte KEY_5           = '5'
    const ubyte KEY_6           = '6'
    const ubyte KEY_7           = '7'
    const ubyte KEY_8           = '8'
    const ubyte KEY_9           = '9'
    const ubyte KEY_A           = 'a'
    const ubyte KEY_B           = 'b'
    const ubyte KEY_C           = 'c'
    const ubyte KEY_D           = 'd'
    const ubyte KEY_E           = 'e'
    const ubyte KEY_F           = 'f'
    const ubyte KEY_G           = 'g'
    const ubyte KEY_H           = 'h'
    const ubyte KEY_I           = 'i'
    const ubyte KEY_J           = 'j'
    const ubyte KEY_K           = 'k'
    const ubyte KEY_L           = 'l'
    const ubyte KEY_M           = 'm'
    const ubyte KEY_N           = 'n'
    const ubyte KEY_O           = 'o'
    const ubyte KEY_P           = 'p'
    const ubyte KEY_Q           = 'q'
    const ubyte KEY_R           = 'r'
    const ubyte KEY_S           = 's'
    const ubyte KEY_T           = 't'
    const ubyte KEY_U           = 'u'
    const ubyte KEY_V           = 'v'
    const ubyte KEY_W           = 'w'
    const ubyte KEY_X           = 'x'
    const ubyte KEY_Y           = 'y'
    const ubyte KEY_Z           = 'z'
    ; capital / shifted
    const ubyte KEY_SHIFT_A     = 'A'
    const ubyte KEY_SHIFT_B     = 'B'
    const ubyte KEY_SHIFT_C     = 'C'
    const ubyte KEY_SHIFT_D     = 'D'
    const ubyte KEY_SHIFT_E     = 'E'
    const ubyte KEY_SHIFT_F     = 'F'
    const ubyte KEY_SHIFT_G     = 'G'
    const ubyte KEY_SHIFT_H     = 'H'
    const ubyte KEY_SHIFT_I     = 'I'
    const ubyte KEY_SHIFT_J     = 'J'
    const ubyte KEY_SHIFT_K     = 'K'
    const ubyte KEY_SHIFT_L     = 'L'
    const ubyte KEY_SHIFT_M     = 'M'
    const ubyte KEY_SHIFT_N     = 'N'
    const ubyte KEY_SHIFT_O     = 'O'
    const ubyte KEY_SHIFT_P     = 'P'
    const ubyte KEY_SHIFT_Q     = 'Q'
    const ubyte KEY_SHIFT_R     = 'R'
    const ubyte KEY_SHIFT_S     = 'S'
    const ubyte KEY_SHIFT_T     = 'T'
    const ubyte KEY_SHIFT_U     = 'U'
    const ubyte KEY_SHIFT_V     = 'V'
    const ubyte KEY_SHIFT_W     = 'W'
    const ubyte KEY_SHIFT_X     = 'X'
    const ubyte KEY_SHIFT_Y     = 'Y'
    const ubyte KEY_SHIFT_Z     = 'Z'

    bool last_timer = false
    sub blink_timer() -> bool {
        bool temp = ((cbm.RDTIM16() as ubyte & %00100000) == 0) as bool
        ;bool temp = ((cbm.RDTIM16() as ubyte & %00010000) == 0) as bool
        if temp != last_timer {
            last_timer = temp
            return true
        }
        return false
    }
}
