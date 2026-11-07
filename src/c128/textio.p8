; Text I/O for the Commodore 128 in its own mode, on the 40 column VIC-II
; screen or the 80 column VDC screen, whichever is active when txt.init()
; is called (the C128 KERNAL's MODE flag, $d7).  It takes the place of the
; library's c128 textio (whose screen routines are for the VIC-II only).
;
; Written for p8vi: the routines it needs that touch the screen directly
; (setchr, getchr), the cursor and size through the KERNAL (which handles
; both screens), and the library's common CBM functions (print, print_uw
; and the like, shared_cbm_textio_functions).  Not here yet: colors, the
; scroll_* routines, fill_screen.
;
; Calling txt.init() again after switching screens (ESC X) picks up the
; new one.
;
; Screen codes: setchr and getchr take screen codes on both screens.  The
; VDC's character set (copied there by the KERNAL) has the reversed
; characters at 128-255 as the VIC-II's does; the upper/lower case set of
; a VDC character is in its attribute byte (the KERNAL sets it when
; printing, and after a clear screen).

%import syslib
%import conv
%import shared_cbm_textio_functions

txt {
    %option no_symbol_prefixing, ignore_unused

    ; the largest screen (the VDC's); width() and height() give the one in use
    const ubyte DEFAULT_WIDTH = 80
    const ubyte DEFAULT_HEIGHT = 25

    ; VDC registers
    const uword VDC_ADDR = $d600        ; register number to write; bit 7: ready
    const uword VDC_DATA = $d601
    const ubyte VDC_UPDATE_HI = 18      ; the address the data register reads and writes
    const ubyte VDC_UPDATE_LO = 19
    const ubyte VDC_COPYMODE = 24       ; bit 7: block copy (else fill)
    const ubyte VDC_COUNT = 30          ; writing it starts a block fill or copy
    const ubyte VDC_DATAREG = 31        ; the byte at the update address (then +1)
    const ubyte VDC_SOURCE_HI = 32      ; where a block copy reads
    const ubyte VDC_SOURCE_LO = 33

    ; bit 7 set: the VDC screen is in use (see init())
    ubyte vdc
    ; the VDC's screen memory (the KERNAL's page for it, VM3)
    uword vdc_screen

    extsub $FFD2 = chrout(ubyte character @ A)    ; PETSCII

    ; which screen is active: call at the start (and after a switch)
    sub init() {
        vdc = c128.SCREEN_MODE & $80
        vdc_screen = mkword(c128.VM3, 0)
    }

    sub bell() {
        chrout(7)
    }

    ; the KERNAL's character set switches work on both screens
    sub lowercase() {
        chrout(14)
    }

    sub uppercase() {
        chrout(142)
    }

    asmsub column(ubyte col @A) clobbers(A, X, Y) {
        ; ---- the cursor to the given column (from 0) on the current row
        %asm {{
            pha
            sec
            jsr  cbm.PLOT
            pla
            tay
            clc
            jmp  cbm.PLOT
        }}
    }

    asmsub get_column() -> ubyte @Y {
        %asm {{
            sec
            jmp  cbm.PLOT
        }}
    }

    asmsub row(ubyte rownum @A) clobbers(A, X, Y) {
        ; ---- the cursor to the given row (from 0) in the current column
        %asm {{
            pha
            sec
            jsr  cbm.PLOT
            pla
            tax
            clc
            jmp  cbm.PLOT
        }}
    }

    asmsub get_row() -> ubyte @X {
        %asm {{
            sec
            jmp  cbm.PLOT
        }}
    }

    asmsub get_cursor() -> ubyte @X, ubyte @Y {
        ; ---- column in X, row in Y
        %asm {{
            sec
            jsr  cbm.PLOT
            stx  P8ZP_SCRATCH_REG
            tya
            tax
            ldy  P8ZP_SCRATCH_REG
            rts
        }}
    }

    asmsub plot(ubyte col @Y, ubyte row @X) {
        %asm {{
            clc
            jmp  cbm.PLOT
        }}
    }

    asmsub width() clobbers(X, Y) -> ubyte @A {
        ; ---- the number of columns of the screen in use
        %asm {{
            jsr  cbm.SCREEN
            inx
            txa
            rts
        }}
    }

    asmsub height() clobbers(X, Y) -> ubyte @A {
        ; ---- the number of rows of the screen in use
        %asm {{
            jsr  cbm.SCREEN
            iny
            tya
            rts
        }}
    }

    asmsub size() clobbers(A) -> ubyte @X, ubyte @Y {
        ; ---- columns in X, rows in Y
        %asm {{
            jsr  cbm.SCREEN
            inx
            iny
            rts
        }}
    }

    asmsub waitkey() -> ubyte @A {
        %asm {{
-           jsr  cbm.GETIN
            beq  -
            rts
        }}
    }

    asmsub setchr(ubyte col @X, ubyte row @Y, ubyte character @A) clobbers(A, X, Y) {
        ; ---- put a screen code on the screen at col, row
        %asm {{
            pha
            bit  vdc
            bmi  _vdc
            tya
            asl  a
            tay
            lda  _screenrows,y
            sta  P8ZP_SCRATCH_W1
            lda  _screenrows+1,y
            sta  P8ZP_SCRATCH_W1+1
            txa
            tay
            pla
            sta  (P8ZP_SCRATCH_W1),y
            rts
_vdc
            jsr  vdc_address
            pla
            ldx  #VDC_DATAREG
            jmp  vdc_write

            ; the VIC-II screen's rows (src/cbmscreen.p8 uses this table too)
_screenrows .word  cbm.Screen + range(0, 1000, 40)
            ; !notreached!
        }}
    }

    asmsub getchr(ubyte col @A, ubyte row @Y) clobbers(X, Y) -> ubyte @A {
        ; ---- the screen code on the screen at col, row
        %asm {{
            bit  vdc
            bmi  _vdc
            pha
            tya
            asl  a
            tay
            lda  setchr._screenrows,y
            sta  P8ZP_SCRATCH_W1
            lda  setchr._screenrows+1,y
            sta  P8ZP_SCRATCH_W1+1
            pla
            tay
            .if  p8b_main.FONT != 0
            ; (the font build's 40 column screen is under the KERNAL ROM,
            ; src/c128font/font.p8: read with the RAM there)
            php
            sei
            lda  c128.MMUCR
            pha
            lda  #$3e
            sta  c128.MMUCR
            lda  (P8ZP_SCRATCH_W1),y
            tax
            pla
            sta  c128.MMUCR
            plp
            txa
            .else
            lda  (P8ZP_SCRATCH_W1),y
            .endif
            rts
_vdc
            tax
            jsr  vdc_address
            ldx  #VDC_DATAREG
            jmp  vdc_read
        }}
    }

    asmsub vdc_address(ubyte col @X, ubyte row @Y) clobbers(A, X, Y) {
        ; ---- the VDC's update address to col, row of its screen
        %asm {{
            tya
            asl  a
            tay
            txa
            clc
            adc  _rows,y
            sta  P8ZP_SCRATCH_REG
            lda  _rows+1,y
            adc  #0
            tay                     ; offset in Y (high), P8ZP_SCRATCH_REG (low)
            lda  P8ZP_SCRATCH_REG
            clc
            adc  vdc_screen
            sta  P8ZP_SCRATCH_REG
            tya
            adc  vdc_screen+1
            ldx  #VDC_UPDATE_HI
            jsr  vdc_write
            lda  P8ZP_SCRATCH_REG
            ldx  #VDC_UPDATE_LO
            jmp  vdc_write

_rows       .word  range(0, 2000, 80)
            ; !notreached!
        }}
    }

    asmsub vdc_write(ubyte reg @X, ubyte value @A) {
        ; ---- write a VDC register
        %asm {{
            stx  VDC_ADDR
-           bit  VDC_ADDR
            bpl  -
            sta  VDC_DATA
            rts
        }}
    }

    asmsub vdc_read(ubyte reg @X) -> ubyte @A {
        ; ---- read a VDC register
        %asm {{
            stx  VDC_ADDR
-           bit  VDC_ADDR
            bpl  -
            lda  VDC_DATA
            rts
        }}
    }
}
