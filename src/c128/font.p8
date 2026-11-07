;
; the C128 builds without the font (features.FONT false): the names
; platform.p8 uses, as constants, so nothing of the font is in the program.
; The font build's font module is src/c128font/font.p8 (p8vi-c128x).
;
font {
    const bool shown = false

    sub start() -> bool {
        return false
    }

    sub stop() {
    }

    sub screen() {
    }
}
