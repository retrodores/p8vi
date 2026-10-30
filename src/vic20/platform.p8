%import diskio
%import strings
%import textio

;
; platform specific -- could merge to main
;
platform {
    ; gap buffer memory ends here (1 byte past the last usable byte), set by init()
    pointer ramtop

    sub init() {
       ; the program needs at least the 8K expansion at $2000 (block 1).
       ; blocks 2 and 3 ($4000-$7fff) are optional: extend the buffer into
       ; them when present.  a block the program itself reaches into must
       ; be there, and must not be tested (that would overwrite the code).
       ; $8000 is the character ROM.
       ramtop = $4000
       if sys.progend() > $4000 or ram_at($4000) {
           ramtop = $6000
           if sys.progend() > $6000 or ram_at($6000)
               ramtop = $8000
       }
       main.SCREEN_WIDTH    = txt.DEFAULT_WIDTH
       main.SCREEN_HEIGHT   = txt.DEFAULT_HEIGHT
       main.STATUS_HEIGHT   = 1    ; only 23 rows, so no spare row above the status line
       main.MIN_COL         = 0
       main.MAX_COL         = main.SCREEN_WIDTH - 1
       main.MIN_ROW         = 0
       main.MAX_ROW         = main.SCREEN_HEIGHT - main.STATUS_HEIGHT - 1
       main.STATUS_LINE     = main.SCREEN_HEIGHT - 1
    }

    ; true if there is RAM in the 8K block at addr (checked at both ends).
    ; without an expansion the reads don't return what was written.
    sub ram_at(pointer addr) -> bool {
        return ram_byte(addr) and ram_byte(addr + $1fff)
    }

    sub ram_byte(pointer addr) -> bool {
        @(addr) = $55
        if @(addr) != $55
            return false
        @(addr) = $aa
        return @(addr) == $aa
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
