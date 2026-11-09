%import diskio
%import strings
%import textio
%import charset_platform

;
; p8vi on the TRS-80 Model III with LDOS: built with prog8c's llvm16 target
; and the z80-trs80-cmd profile (llvm-z80 and z88dk), a .cmd program.
; The screen is 64 x 16 at $3c00, the keys are the ROM's (through LDOS),
; the files go through z88dk's TRSDOS library ("t.txt" is T/TXT).  The CBM
; targets' src/cbmkernal.p8 has the same names for those machines.
;
platform {
    ; the screen, 64 bytes a row
    const uword VIDEO = $3c00
    const ubyte COLUMNS = 64
    ; the ROM's caps lock flag (not 0: letters come as capitals, shifted
    ; or not); p8vi needs lowercase, and puts it back at the end
    const uword CAPS = $4019
    ubyte old_caps
    ; LDOS's cursor (it blinks while a program waits for a key): $4020 its
    ; screen address, $4023 the character it blinks with.  saved at the
    ; start, put back at the end.
    const uword CURSOR_ADDR = $4020
    const uword CURSOR_CHAR = $4023
    uword old_cursor_addr
    ubyte old_cursor_char
    ubyte cursor_sink           ; where LDOS's cursor blinks meanwhile, unseen

    ; memory for the text (the gap buffer), set by init()
    pointer textstart
    pointer texttop         ; 1 byte past the last usable byte
    ; (no spare memory elsewhere)
    pointer sparestart
    pointer sparetop

    ; z88dk's heap: from the end of the program up to the stack, which
    ; LDOS starts at the top of memory (HIGH$).  the file routines take
    ; their buffers from it too (a sector and the file's control block for
    ; each open file; 2 are open in rename_file()), and the stack needs
    ; room to grow down: the text leaves FILE_ROOM and STACK_ROOM of it.
    ; (z88dk's malloc takes a block from the top of the free memory: first
    ; STACK_ROOM, which nothing uses but the stack, then the text, which
    ; leaves FILE_ROOM below it.)
    extsub malloc(uword size) -> uword
    extsub free(uword block)
    const uword FILE_ROOM = 2048
    const uword STACK_ROOM = 2048

    sub init() {
        uword size = $c000
        old_caps = @(CAPS)
        @(CAPS) = 0
        old_cursor_addr = peekw(CURSOR_ADDR)
        old_cursor_char = @(CURSOR_CHAR)
        ; LDOS's cursor out of the way (p8vi draws its own): it blinks where
        ; LDOS's prompt left it, the bottom left, and the status line is
        ; there.  (z88dk's console doesn't move it, nor turn it off with
        ; display code 15: it doesn't go through the ROM.)
        pokew(CURSOR_ADDR, &cursor_sink)
        ; the text gets the biggest block the heap has, less FILE_ROOM and
        ; STACK_ROOM
        repeat {
            textstart = malloc(size) as pointer
            if textstart != 0
                break
            size -= $100
        }
        free(textstart)
        void malloc(STACK_ROOM)
        size -= FILE_ROOM + STACK_ROOM
        repeat {
            textstart = malloc(size) as pointer
            if textstart != 0
                break
            size -= 16
        }
        texttop = textstart + size
        main.SCREEN_WIDTH    = txt.width()
        main.SCREEN_HEIGHT   = txt.height()
        main.STATUS_HEIGHT   = 1    ; only 16 rows, so no spare row above the status line
        main.MIN_COL         = 0
        main.MAX_COL         = main.SCREEN_WIDTH - 1
        main.MIN_ROW         = 0
        main.MAX_ROW         = main.SCREEN_HEIGHT - main.STATUS_HEIGHT - 1
        main.STATUS_LINE     = main.SCREEN_HEIGHT - 1
        ; (the test build) the keys to play, from KEYS/TXT
        if features.KEYFILE and diskio.f_open(KEY_FILE) {
            main.key_count = diskio.f_read(main.key_buf, len(main.key_buf))
            diskio.f_close()
        }
    }

    ; (features.KEYFILE, the test build) the keys get_key() gives first:
    ; the editor's codes, as tests/vice/edtest.py's suites type them
    str KEY_FILE = "keys.txt"

    ; before the program ends
    sub stop() {
        @(CAPS) = old_caps
        @(CURSOR_CHAR) = old_cursor_char
        pokew(CURSOR_ADDR, old_cursor_addr)
    }

    ; draw a screen row: n characters of text from column col, control
    ; characters as '.', and spaces before col and after the text (as
    ; src/cbmscreen.p8 does on the CBM machines)
    sub put_row(ubyte r, ubyte col, uword text, ubyte n) {
        uword p = VIDEO + (r as uword) * COLUMNS
        ubyte c
        ubyte i
        for i in 0 to COLUMNS - 1 {
            c = ' '
            if i >= col and n != 0 {
                c = @(text)
                text++
                n--
                if c == $de
                    c = '~'         ; (the empty rows' marker, PETSCII pi)
                else if c < ' ' or c >= $80
                    c = '.'
            }
            @(p + i) = c
        }
    }

    ; move screen rows first to last count rows up (up: row first+count to
    ; first ... last to last-count) or down (first to first+count ...
    ; last-count to last); the rows moved into aren't changed
    sub scroll_rows(ubyte first, ubyte last, ubyte count, bool up) {
        ubyte r
        if up {
            for r in first to last - count
                sys.memcopy(VIDEO + (r + count) as uword * COLUMNS, VIDEO + (r as uword) * COLUMNS, COLUMNS)
        } else {
            r = last
            while r >= first + count {
                sys.memcopy(VIDEO + (r - count) as uword * COLUMNS, VIDEO + (r as uword) * COLUMNS, COLUMNS)
                r--
            }
        }
    }

    ; (the C128: the 40/80 DISPLAY key switches the screen; not here)
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

    ; open a file for writing with diskio.f_write.  sets main.io_failed if
    ; that fails.
    sub open_write(str name) -> bool {
        main.io_failed = not diskio.f_open_w(name)
        return not main.io_failed
    }
}

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

    ; platform.stop() puts LDOS's caps lock and cursor back
    const bool PLATFORM_STOP = true

    ; special characters

    const ubyte CHAR_CURSOR     = $b0   ; the usual TRS-80 cursor: the graphics character with the bottom row of dots

    const ubyte KEY_ESCAPE      = 27    ; shift + up arrow
    const ubyte KEY_CONTROL_L   = 12

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

    ; LDOS's clock: $4216 counts 30ths of a second down, $4217 the seconds
    const uword TICKS = $4216
    const uword SECONDS = $4217

    bool last_timer = false
    sub blink_timer() -> bool {
        bool temp = @(TICKS) >= 15
        if temp != last_timer {
            last_timer = temp
            return true
        }
        return false
    }

    ; a key, 0 for none.  the ROM's codes, with the editor's for the
    ; arrows (91 is [ too, but the keyboard has no [), BREAK (1) as RUN/STOP
    ; does on CBM (an Escape), and the left arrow (8) as DEL: the TRS-80's
    ; backspace, which deletes in insert mode and on the : line and moves
    ; left otherwise (as h).  shift + left arrow (24) moves left in insert
    ; mode too.  Ctrl is shift + down arrow with a letter, as LDOS does it:
    ; Ctrl-F is 6.
    ubyte[if features.KEYFILE 2048 else 1] key_buf
    uword key_count
    uword key_pos
    sub get_key() -> ubyte {
        if features.KEYFILE and key_pos < key_count {
            key_pos++
            return key_buf[key_pos - 1]
        }
        ubyte k = txt.getkey()
        when k {
            91 -> return KEY_UP
            10 -> return KEY_DOWN
            8 -> return KEY_DEL
            9 -> return KEY_RIGHT
            1 -> return KEY_STOP
            24 -> return KEY_LEFT
        }
        return k
    }

    ; a clock in 30ths of a second (it wraps every minute)
    sub ticks() -> uword {
        return (@(SECONDS) as uword) * 30 + 30 - @(TICKS)
    }

    ; the cursor: an underline (the characters from $80 are graphics)
    inline sub cursor_char(ubyte char) -> ubyte {
        return CHAR_CURSOR
    }

    ; the number of digits conv.str2uword just read at cmdline[cmd_pos]
    ; (the CBM library leaves the count in r15, this one doesn't)
    sub str2uword_digits() -> ubyte {
        ubyte n = 0
        while cmdline[cmd_pos + n] >= '0' and cmdline[cmd_pos + n] <= '9'
            n++
        return n
    }

    ;
    ; files.  the TRSDOS library has no drive status: disk_code is set
    ; like CBM DOS's (0 ok, 62 file not found, 255 any other error), and
    ; status_text says it.
    ;

    ubyte disk_code
    str status_text = " " * 40
    bool io_failed

    ; true if the file can be opened for reading
    sub file_exists(str name) -> bool {
        if diskio.f_open(name) {
            diskio.f_close()
            disk_code = 0
            return true
        }
        disk_code = 62
        void strings.copy("file not found", status_text)
        return false
    }

    ; disk_code and status_text for the last write or rename
    sub read_disk_status() {
        disk_code = 0
        void strings.copy("ok", status_text)
        if io_failed {
            disk_code = 255
            void strings.copy("disk error", status_text)
        }
        io_failed = false
    }

    ; show the status
    sub disk_error() {
        if disk_code != 62 {
            io_failed = true
            read_disk_status()
        }
        status(status_text)
    }

    ; rename a file: the TRSDOS library has no rename, so copy old to new
    ; and delete old.  sets io_failed if that fails.
    ubyte[128] copy_buf
    sub rename_file(str old, str new) {
        uword n
        io_failed = true
        if diskio.f_open(old) {
            if diskio.f_open_w(new) {
                io_failed = false
                repeat {
                    n = diskio.f_read(copy_buf, len(copy_buf))
                    if n == 0
                        break
                    if not diskio.f_write(copy_buf, n) {
                        io_failed = true
                        break
                    }
                }
                diskio.f_close_w()
            }
            diskio.f_close()
        }
        if not io_failed
            diskio.delete(old)
    }

    ; (features.DOS, features.DIR, features.PREFIX: CBM DOS only, off here)
    sub dos_cmd(str command) {
    }
    sub dir_cmd(str name, bool insert) {
    }
    sub dos_command(ubyte c, str name, str old) {
    }
    sub scratch(str name) {
    }
}
