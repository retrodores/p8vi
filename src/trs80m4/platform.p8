%import diskio
%import strings
%import textio
%import charset_platform

;
; p8vi on the TRS-80 Model 4 in its own mode, with TRSDOS 6 or LS-DOS 6.3:
; built with prog8c's llvm16 target and the z80-trs80-m4 profile (llvm-z80
; and z88dk), a .cmd program.  The screen is 80 x 24, through the DOS's
; @VDCTL (txt.setchr and getchr: the DOS pages the video RAM in only while
; its routines run), the keys come from @KBD, the files go through the
; DOS's own file calls ("t.txt" is T/TXT).  The Model III version is
; src/trs80/platform.p8; this build shares its other files (charset,
; fastmem, store: -srcdirs src:src/trs80m4:src/trs80).
;
platform {
    const ubyte COLUMNS = 80

    ; memory for the text (the gap buffer), set by init()
    pointer textstart
    pointer texttop         ; 1 byte past the last usable byte
    ; spare memory: between the heap and the stack (see init), for the key
    ; buffers and the like
    pointer sparestart
    pointer sparetop

    ; z88dk's heap: from the end of the program up.  the file routines take
    ; their buffers from it (a sector and the file's control block for the
    ; open file; the DOS renames, so one is open at a time): the text leaves
    ; FILE_ROOM of it.  z88dk's malloc takes a block from the top of the
    ; free memory, so the text is at the top, FILE_ROOM below it.
    ; The profile puts the stack at HIGH$ (below $f400), and z88dk's AMALLOC
    ; makes the heap only 75% of the memory up to it: the rest, less
    ; STACK_ROOM for the stack, is spare memory.  (if the heap goes up to the
    ; stack, STACK_ROOM of it is kept free instead.)
    extsub malloc(uword size) -> uword
    extsub free(uword block)
    const uword FILE_ROOM = 1024
    ; (measured on the Model III: running the edits and big test suites, the
    ; stack used under 64 bytes of it)
    const uword STACK_ROOM = 512

    ; the stack pointer: ld hl,0 / add hl,sp / ret
    ubyte[] get_sp = [$21, $00, $00, $39, $c9]

    sub init() {
        uword size = $c000
        ; the DOS's cursor off until the editor shows it (DOS_CURSOR)
        txt.cursor_off()
        uword stack
        ; the text gets the biggest block the heap has, less FILE_ROOM: it
        ; ends where the heap does
        repeat {
            textstart = malloc(size) as pointer
            if textstart != 0
                break
            size -= $100
        }
        free(textstart)
        ; from there up to the stack, less STACK_ROOM: spare memory
        sparestart = textstart + size
        sparetop = sparestart
        stack = &get_sp
        stack = call(stack)
        if stack > sparestart and stack - sparestart > STACK_ROOM
            sparetop = stack - STACK_ROOM
        else {
            void malloc(STACK_ROOM)
            size -= STACK_ROOM
        }
        size -= FILE_ROOM
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

    ; before the program ends: the DOS's cursor back
    sub stop() {
        txt.cursor_on()
    }

    ; draw a screen row: n characters of text from column col, control
    ; characters as '.', and spaces before col and after the text (as
    ; src/cbmscreen.p8 does on the CBM machines)
    sub put_row(ubyte r, ubyte col, uword text, ubyte n) {
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
            row_buf[i] = c
        }
        video_on()
        sys.memcopy(&row_buf, VIDEO + (r as uword) * COLUMNS, COLUMNS)
        video_off()
    }
    ubyte[COLUMNS] row_buf

    ; move screen rows first to last count rows up (up: row first+count to
    ; first ... last to last-count) or down (first to first+count ...
    ; last-count to last); the rows moved into aren't changed
    sub scroll_rows(ubyte first, ubyte last, ubyte count, bool up) {
        ubyte r
        video_on()
        if up {
            for r in first to last - count
                sys.memcopy(VIDEO + ((r + count) as uword) * COLUMNS, VIDEO + (r as uword) * COLUMNS, COLUMNS)
        } else {
            r = last
            while r >= first + count {
                sys.memcopy(VIDEO + ((r - count) as uword) * COLUMNS, VIDEO + (r as uword) * COLUMNS, COLUMNS)
                r--
            }
        }
        video_off()
    }

    ; the video RAM: memory map 2 (port $84 bits 0-1) has the keyboard at
    ; $f400 and the screen at $f800, instead of the RAM there.  the DOS keeps
    ; the port's value at $0078 (the port can't be read); TRSDOS 6 leaves
    ; map 2 on ($86 in trs80gp), so this is only in case a DOS doesn't.
    ; interrupts are off meanwhile: the DOS's interrupt code may be in the
    ; RAM that is paged out.  (p8vi's code, heap and stack are below $f400.)
    const uword VIDEO = $f800
    const ubyte OPREG = $84
    const uword OPREG_COPY = $0078
    sub video_on() {
        sys.set_irqd()
        sys.outp(OPREG, (@(OPREG_COPY) & %11111100) | 2)
    }
    sub video_off() {
        sys.outp(OPREG, @(OPREG_COPY))
        sys.clear_irqd()
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

    ; (the X16's ISO build: the cursor as swapped colors; not here)
    sub color_cursor(ubyte col, ubyte row) {
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

    ; platform.stop() puts the DOS's cursor back
    const bool PLATFORM_STOP = true
    ; the DOS's cursor, which it blinks (editor.p8's cursor_on)
    const bool DOS_CURSOR = true
    ; a drive spec comes after the file name: name/ext:1 (editor.p8's
    ; save_file puts its temporary file on the same drive)
    ; (CP/M: text files end at the first ^Z)
    const bool CTRL_Z_EOF = false
    ; a new text's line ending (editor.p8's ENDING_*): CR
    const ubyte NEW_ENDING = 0
    const bool DRIVE_SUFFIX = true
    ; (features.PREFIX) what ends a drive or path prefix
    const ubyte PATH_SEP = ':'
    const ubyte PATH_VOLUME = 0     ; (the Amiga's volume:, a second end of a path prefix)
    ; the drive the DOS opened the last file on (0-7, 255 if unknown)
    sub opened_drive() -> ubyte {
        return diskio.last_drive()
    }
    sub dos_cursor(bool on) {
        if on
            txt.cursor_on()
        else
            txt.cursor_off()
    }

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

    ; (DOS_CURSOR: the DOS blinks its own cursor.  without it p8vi's
    ; blinks by the number of times the keyboard was looked at, as the
    ; DOS's clock isn't at a known address; 400 looked right in trs80gp)
    const uword BLINK_POLLS = 400
    uword polls
    sub blink_timer() -> bool {
        polls++
        if polls < BLINK_POLLS
            return false
        polls = 0
        return true
    }

    ; a key, 0 for none.  the DOS's codes, with the editor's for the
    ; arrows, BREAK (128) as RUN/STOP does on CBM (an Escape), and the left
    ; arrow (8) as DEL: the TRS-80's backspace, which deletes in insert mode
    ; and on the : line and moves left otherwise (as h).  shift + left arrow
    ; (24) moves left in insert mode too.  CTRL and a letter is Ctrl.
    const uword KEY_BUF_SIZE = 256
    ubyte[if features.KEYFILE KEY_BUF_SIZE else 1] key_buf
    uword key_count
    uword key_pos
    sub get_key() -> ubyte {
        if features.KEYFILE and key_pos < key_count {
            key_pos++
            return key_buf[key_pos - 1]
        }
        ubyte k = txt.getkey()
        when k {
            11 -> return KEY_UP
            10 -> return KEY_DOWN
            8 -> return KEY_DEL
            9 -> return KEY_RIGHT
            128 -> return KEY_STOP
            24 -> return KEY_LEFT
        }
        return k
    }

    ; a clock in 60ths of a second, for the page store's sync
    ; (p8vi-trs80m4x): the compiler's (an interrupt task of the DOS,
    ; installed by the first call)
    inline sub ticks() -> uword {
        return sys.ticks()
    }

    ; a character as txt.setchr wants it: ASCII
    inline sub screen_code(ubyte char) -> ubyte {
        return char
    }

    ; the rows past the end of the text, as vi shows them
    str EMPTY_ROW = "~"

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

    ; rename a file: the DOS's own rename (it fails when new exists).
    ; sets io_failed if it failed (diskio.status_code() is 0 when the last
    ; disk operation worked, 1 when it failed).
    sub rename_file(str old, str new) {
        diskio.rename(old, new)
        io_failed = diskio.status_code() != 0
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
