%import diskio
%import textio

;
; the C64 font build (p8vi-c64font, features.FONT): a font loaded from
; oscii.fnt (a 2 KB character set saved with load address $f800) into the
; RAM under the KERNAL ROM, and the screen moved to $c800, both in VIC-II
; bank 3 ($c000-$ffff).  The font is the C64's lowercase set with ASCII
; characters in place of some graphics ones, so PETSCII shows them:
;   \ $5c  ^ $5e  _ $5f  ` $c0  { $db  | $dc  } $dd  ~ $de
; (charset.p8 translates ASCII files to these.)  The KERNAL draws on the
; screen HIBASE says; textio and cbmscreen draw through the screen row
; table txt.setchr._screenrows, which start() moves.  The text memory ends
; at the screen.
;
font {
    const uword SCREEN = $c800
    const uword CHARS = $f800
    ; the VIC-II's memory pointers: the screen at $0800 and the characters
    ; at $3800 in the bank
    const ubyte VMCSB_FONT = $2e
    ; how far the screen rows move
    const ubyte MOVE = msb(SCREEN) - $04

    str FILE = "oscii.fnt"
    ubyte old_vmcsb

    ; load the font and show it.  returns false if oscii.fnt didn't load.
    sub start() -> bool {
        bool failed
        ; (not diskio.load(): the font ends at $ffff, so the end address it
        ; returns wraps to 0, its value for an error)
        cbm.SETNAM(len(FILE), FILE)
        cbm.SETLFS(1, diskio.drivenumber, 0)
        failed, void, void = cbm.LOAD(0, CHARS)
        if failed
            return false
        old_vmcsb = c64.VMCSB
        set_bank(%00)
        c64.VMCSB = VMCSB_FONT
        cbm.HIBASE = msb(SCREEN)
        move_rows(MOVE)
        return true
    }

    ; back to the screen at $0400 and the C64's font
    sub stop() {
        set_bank(%11)
        c64.VMCSB = old_vmcsb
        cbm.HIBASE = $04
        move_rows(256 - MOVE)       ; (back, modulo 256)
    }

    ; the VIC-II bank is CIA 2 port A bits 0 and 1, inverted: %11 is bank 0
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
}
