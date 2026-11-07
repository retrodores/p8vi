%import diskio
%import strings
%import textio
%import cbmscreen
%import vdcscreen
%import font


;
; platform specific: the C128 in its own mode (not GO64).  The screen is
; the 40 column VIC or the 80 column VDC, whichever is active at the start
; (textio.p8 here: txt.setchr and friends work on both)
;
platform {
    ; draw a screen row (see src/cbmscreen.p8), on the VIC-II or the VDC
    sub put_row(ubyte r, ubyte col, uword text, ubyte n) {
        if txt.vdc & $80 != 0
            vdcscreen.put_row(r, col, text, n)
        else
            cbmscreen.put_row(r, col, text, n)
    }

    sub scroll_rows(ubyte first, ubyte last, ubyte count, bool up) {
        if txt.vdc & $80 != 0
            vdcscreen.scroll_rows(first, last, count, up)
        else if features.FONT and font.shown and txt.vdc & $80 == 0 {
            ; (the font build's screen is under the KERNAL ROM, src/c128font/font.p8)
            sys.set_irqd()
            c128.MMUCR = $3e
            cbmscreen.scroll_rows(first, last, count, up)
            c128.MMUCR = $0e
            sys.clear_irqd()
        } else
            cbmscreen.scroll_rows(first, last, count, up)
    }

    ; the KERNAL's count of open files (for src/diskpage): LDTND, as on the C64
    const uword KERNAL_OPEN_FILES = $98

    ; memory for the text (the gap buffer), set by init()
    pointer textstart
    pointer texttop         ; 1 byte past the last usable byte
    ; optional spare memory elsewhere, used for the yank buffer, undo log and
    ; key buffers when they fit (otherwise they come off the top of the text
    ; memory): the C128's "golden RAM", $1300-$1bdf (Prog8 keeps the R0-R15
    ; virtual registers at $1be0-$1bff)
    pointer sparestart = $1300
    pointer sparetop = $1be0

    sub init() {
       ; Prog8 banks out the BASIC ROM on the C128: the program and the text
       ; have the RAM from $1c00 to $bfff
       textstart = sys.progend()
       texttop = $c000
       txt.init()
       ; file names and loaded/saved data are in RAM bank 0.  the KERNAL
       ; reads a file name through the bank SETBNK set; after BASIC that is
       ; bank 15, where $4000-$bfff is the BASIC ROM (and p8vi's names are)
       c128.SETBNK(0, 0)
       ; (the font build) without p8vi.fnt the ROM's font stays
       if features.FONT
           void font.start()

       if SWITCH
           key4080 = @(MMU_MODE) & $80
       geometry()
    }

    ; the screen's size and the editor's rows (again after a switch)
    sub geometry() {
       main.SCREEN_WIDTH    = txt.width()
       main.SCREEN_HEIGHT   = txt.height()
       main.STATUS_HEIGHT   = 2
       main.MIN_COL         = 0
       main.MAX_COL         = main.SCREEN_WIDTH - 1
       main.MIN_ROW         = 0
       main.MAX_ROW         = main.SCREEN_HEIGHT - main.STATUS_HEIGHT - 1
       main.STATUS_LINE     = main.SCREEN_HEIGHT - 1
    }

    ; (features.SWITCH) the 40/80 DISPLAY key switches the screen while
    ; p8vi runs.  The KERNAL reads the key only at a reset; its position
    ; is bit 7 of the MMU's mode register: 0 when it is down (80 columns).
    ; (not with the font yet: src/c128font/font.p8 sets up one screen)
    const bool SWITCH = features.SWITCH and not features.FONT
    const uword MMU_MODE = $d505
    ubyte @nozp key4080     ; the key's position at the last look

    ; true if the key was pressed and selects the other screen
    sub switch_wanted() -> bool {
        ubyte k = @(MMU_MODE) & $80
        if k == key4080
            return false
        key4080 = k
        return (k == 0) != (txt.vdc & $80 != 0)
    }

    ; switch to the other screen (the KERNAL's SWAPPER, as ESC X does) and
    ; clear it, lowercase
    sub switch_screen() {
        c128.SWAPPER()
        txt.init()
        txt.lowercase()
        txt.cls()
        geometry()
    }

    ; before the program ends (the font build only)
    sub stop() {
        if features.FONT and font.shown
            font.stop()
    }

    ; (the font build) show the font for ASCII or for PETSCII text; returns
    ; true if its ASCII characters are shown: the font stays, if p8vi.fnt
    ; loaded
    sub font_mode(bool ascii) -> bool {
        return features.FONT and font.shown
    }

    ; open a file for writing with diskio.f_write as a SEQ file.
    ; the CBM diskio.f_open_w doesn't add the type, so do that here.
    ; the drive status can't be checked until the file is closed: reading
    ; it opens and closes channel 15, and closing channel 15 closes every
    ; file on the drive.  the file must not exist yet.
    str write_name = " " * 40
    sub open_write(str name) -> bool {
        void strings.copy(name, write_name)
        void strings.append(write_name, ",s,w")
        return diskio.f_open_w(write_name)
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
