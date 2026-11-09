%import dma

;
; the MEGA65 font builds (features.FONT): the font follows the text.  For
; an ASCII file the MEGA65 ROM's own lower case character set with ASCII
; characters (BASIC 65's FONT A set, at $29800) is copied into the
; VIC-IV's character RAM, so PETSCII shows the characters it lacks; for a
; PETSCII file the C64's lower case set ($2d800) goes back, so PETSCII
; graphics show as they are.  The ASCII characters are at the same screen
; codes as in the C64 font build's oscii.fnt, so charset.p8's FONT tables
; are the same:
;   \ $5c  ^ $5e  _ $5f  ` $c0  { $db  | $dc  } $dd  ~ $de
;
; The character RAM ($ff7e000, 4 KB: upper case, then lower case) is what
; the VIC shows for the character ROM addresses $1000-$1fff; in lower case
; mode ($d018 = $26) that is its second half.  It can't be read, so what
; was there at the start can't be put back: at the end the C64 set goes
; back, which is what xemu has there when a program starts (a real MEGA65
; might start with another).  The upper case half isn't changed.
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

    ; the set with the ASCII characters, or (false) the C64's
    sub show(bool ascii) {
        uword set = ROM_C64
        if ascii
            set = ROM_ASCII
        dma.far(0, set, ROM_BANK, CHARS_MB, CHARS, CHARS_BANK, 2048)
    }
}
