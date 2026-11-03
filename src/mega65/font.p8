%import dma

;
; the MEGA65 font build (p8vi-mega65font, features.FONT): the MEGA65 ROM's
; own lower case character set with ASCII characters (BASIC 65's FONT A
; set, at $29800) is copied into the VIC-IV's character RAM, so PETSCII
; shows the characters it lacks.  They are at the same screen codes as in
; the C64 font build's p8vi.fnt, so charset.p8's FONT tables are the same:
;   \ $5c  ^ $5e  _ $5f  ` $c0  { $db  | $dc  } $dd  ~ $de
;
; The character RAM ($ff7e000, 4 KB: upper case, then lower case) is what
; the VIC shows for the character ROM addresses $1000-$1fff; in lower case
; mode ($d018 = $26) that is its second half.  It can't be read, so stop()
; can't put back what was there: it copies the C64 lower case set from ROM
; ($2d800), which is what xemu has there when a program starts (a real
; MEGA65 might start with another).  The upper case half isn't changed.
;
font {
    ; the character RAM's lower case half: megabyte $ff, bank $07, $e800
    const ubyte CHARS_MB = $ff
    const ubyte CHARS_BANK = $07
    const uword CHARS = $e800
    ; the ROM's lower case sets, in bank 2: with ASCII characters, and the C64's
    const ubyte ROM_BANK = $02
    const uword ROM_ASCII = $9800
    const uword ROM_C64 = $d800

    sub start() {
        dma.far(0, ROM_ASCII, ROM_BANK, CHARS_MB, CHARS, CHARS_BANK, 2048)
    }

    ; back to the C64 lower case set
    sub stop() {
        dma.far(0, ROM_C64, ROM_BANK, CHARS_MB, CHARS, CHARS_BANK, 2048)
    }
}
