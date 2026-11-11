%import diskio
%import strings
%import textio
%import charset_platform

;
; p8vi under CP/M 2.2 (and later), on any Z80 machine with a big enough TPA:
; built with prog8c's llvm16 target and the z80-cpm profile (llvm-z80 and
; z88dk), a .com program.  The screen is a terminal: src/cpm/textio.p8
; keeps it in memory and sends the changes (ANSI, VT52 or ADM-3A codes,
; chosen with -T).  The files go through the BDOS (z88dk's stdio): text
; files end with ^Z in their last 128-byte record.  The other platform
; files are the TRS-80's (charset, fastmem, store: -srcdirs
; src:src/cpm:src/trs80).
;
;   P8VI [-T ANSI|VT52|ADM3A]
;
platform {
    const ubyte COLUMNS = txt.DEFAULT_WIDTH

    ; memory for the text (the gap buffer), set by init()
    pointer textstart
    pointer texttop         ; 1 byte past the last usable byte
    ; spare memory: between the heap and the stack (see init), for the key
    ; buffers and the like
    pointer sparestart
    pointer sparetop

    ; z88dk's heap (CRT_HEAP_AMALLOC, set in the Makefile's link options):
    ; from the end of the program up to 75% of the way to the stack, which
    ; z88dk puts at the top of the TPA.  the file routines take their
    ; buffers from it (the FILE and its 128-byte record for the open file;
    ; the BDOS renames, so one is open at a time): the text leaves FILE_ROOM
    ; of it.  z88dk's malloc takes a block from the top of the free memory,
    ; so the text is at the top, FILE_ROOM below it.  The rest up to the
    ; stack, less STACK_ROOM, goes to the text too.
    extsub malloc(uword size) -> uword
    extsub free(uword block)
    const uword FILE_ROOM = 1024
    const uword STACK_ROOM = 512

    ; the stack pointer: ld hl,0 / add hl,sp / ret
    ubyte[] get_sp = [$21, $00, $00, $39, $c9]

    sub init() {
        uword size = $c000
        options()
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
        ; the spare memory is right above the text (z88dk's malloc gave the
        ; text the top of the heap): the text gets it too, and the editor's
        ; small buffers come off its top instead (main.take_memory)
        if sparetop > texttop {
            texttop = sparetop
            sparestart = sparetop
        }
        main.SCREEN_WIDTH    = txt.width()
        main.SCREEN_HEIGHT   = txt.height()
        main.STATUS_HEIGHT   = 1
        main.MIN_COL         = 0
        main.MAX_COL         = main.SCREEN_WIDTH - 1
        main.MIN_ROW         = 0
        main.MAX_ROW         = main.SCREEN_HEIGHT - main.STATUS_HEIGHT - 1
        main.STATUS_LINE     = main.SCREEN_HEIGHT - 1
        ; (the test build) the keys to play, from KEYS.TXT
        if features.KEYFILE and diskio.f_open(KEY_FILE) {
            main.key_count = diskio.f_read(main.key_buf, len(main.key_buf))
            diskio.f_close()
        }
    }

    ; the command line: -T and the terminal's name (or -TNAME).  An unknown
    ; option or terminal ends the program with a usage line, before
    ; anything is drawn.
    sub options() {
        ubyte i = 1
        pointer arg
        while i < sys.argc() {
            arg = sys.argv(i)
            if arg[0] == '-' and arg[1] == '4' and arg[2] == '0' and arg[3] == 0
                txt.columns = 40
            else if arg[0] == '-' and (arg[1] == 'T' or arg[1] == 't') {
                if arg[2] == 0 {
                    i++
                    if i >= sys.argc()
                        usage()
                    arg = sys.argv(i)
                } else
                    arg += 2
                if not txt.select(arg)
                    usage()
            } else
                usage()
            i++
        }
    }

    sub usage() {
        txt.out_str("usage: p8vi [-t ansi|vt52|adm3a] [-40]\r\n")
        sys.exit(1)
    }

    ; (features.KEYFILE, the test build) the keys get_key() gives first:
    ; the editor's codes, as tests/vice/edtest.py's suites type them
    str KEY_FILE = "keys.txt"

    ; before the program ends: what is left to send
    sub stop() {
        txt.done()
    }

    ; draw a screen row: n characters of text from column col, control
    ; characters as '.', and spaces before col and after the text (as
    ; src/cbmscreen.p8 does on the CBM machines)
    sub put_row(ubyte r, ubyte col, pointer text, ubyte n) {
        ubyte c
        ubyte i
        for i in 0 to txt.columns - 1 {
            c = ' '
            if i >= col and n != 0 {
                c = @(text)
                text++
                n--
                if c == $de
                    c = '~'         ; (the empty rows' marker, PETSCII pi)
            }
            txt.put(i, r, c)
        }
    }

    ; move screen rows first to last count rows up (up: row first+count to
    ; first ... last to last-count) or down (first to first+count ...
    ; last-count to last); the rows moved into aren't changed.  (only in
    ; txt's copy: flush() sends the rows that changed)
    sub scroll_rows(ubyte first, ubyte last, ubyte count, bool up) {
        ubyte r
        if up {
            for r in first to last - count
                row_copy(r + count, r)
        } else {
            r = last
            while r >= first + count {
                row_copy(r - count, r)
                r--
            }
        }
    }

    sub row_copy(ubyte src, ubyte dest) {
        sys.memcopy(&txt.want + (src as uword) * COLUMNS, &txt.want + (dest as uword) * COLUMNS, COLUMNS)
        txt.dirty[dest] = true
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

    ; platform.stop() leaves the terminal's cursor below the screen
    const bool PLATFORM_STOP = true
    ; the terminal's own cursor, put where the editor's is (editor.p8's
    ; cursor_on): nothing is drawn for it
    const bool DOS_CURSOR = true
    ; (the TRS-80's name:1; CP/M's drive comes first, B:NAME, as a
    ; features.PREFIX prefix)
    const bool DRIVE_SUFFIX = false
    ; (features.PREFIX) what ends a drive or path prefix
    const ubyte PATH_SEP = ':'
    sub opened_drive() -> ubyte {
        return 255
    }
    ; DOS_CURSOR: the cursor goes where the editor just plotted (on), or
    ; follows what is written (off: the : line)
    sub dos_cursor(bool on) {
        if on
            txt.show_cursor(txt.col, txt.row)
        else
            txt.follow_output()
    }

    ; CP/M text files end at the first ^Z
    const bool CTRL_Z_EOF = true
    ; a new text's line ending: CR LF, as CP/M's text files have
    const ubyte NEW_ENDING = ENDING_CRLF

    ; special characters

    const ubyte CHAR_CURSOR     = '_'   ; (not drawn: DOS_CURSOR)

    const ubyte KEY_ESCAPE      = 27
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

    ; (DOS_CURSOR: the terminal shows the cursor; nothing blinks)
    sub blink_timer() -> bool {
        return false
    }

    ; a key, 0 for none: ASCII as the terminal sends it.  DEL (127) and
    ; backspace (8) delete (DEL), Ctrl-C is RUN/STOP (an Escape), the arrow
    ; keys' escape sequences are the arrows (txt.escape_key).
    const uword KEY_BUF_SIZE = 256
    ubyte[if features.KEYFILE KEY_BUF_SIZE else 1] key_buf
    uword key_count
    uword key_pos
    sub get_key() -> ubyte {
        if features.KEYFILE and key_pos < key_count {
            ; (the test build) the screen is sent before each key, as
            ; txt.getkey() does; $ff marks the screen for the test with three
            ; NULs (tests/cpm/cpmtest.py)
            txt.flush()
            key_pos++
            if key_buf[key_pos - 1] == $ff {
                txt.out(0)
                txt.out(0)
                txt.out(0)
                return 0
            }
            return key_buf[key_pos - 1]
        }
        ubyte k = txt.getkey()
        if k == 27
            k = txt.escape_key()        ; (the arrow keys)
        when k {
            127, 8 -> return KEY_DEL
            3 -> return KEY_STOP
            KEY_CONTROL_L -> txt.repaint()      ; (the editor draws it all again)
        }
        return k
    }

    ; no clock in CP/M 2.2 (only the page store's sync uses it, and this
    ; build has the gap buffer)
    sub ticks() -> uword {
        return 0
    }

    ; a character as txt.setchr wants it: ASCII
    inline sub screen_code(ubyte char) -> ubyte {
        return char
    }

    ; the rows past the end of the text, as vi shows them
    str EMPTY_ROW = "~"

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
    ; files.  the BDOS's errors aren't passed on: disk_code is set like CBM
    ; DOS's (0 ok, 62 file not found, 255 any other error), and status_text
    ; says it.
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

    ; rename a file: the BDOS's (on one drive; it fails when new exists).
    ; sets io_failed if it failed.
    sub rename_file(str old, str new) {
        diskio.rename(old, new)
        io_failed = diskio.status_code() != 0
    }

    ; (features.PREFIX) delete a file, the drive prefix and all
    sub scratch(str name) {
        diskio.delete(name)
    }

    ; (features.PREFIX) the safe save's rename, as CBM DOS's "r" command:
    ; old (p8vi.tmp) gets name's drive prefix, as the BDOS renames on one
    ; drive.  sets io_failed if it failed.
    ubyte[20] old_name
    sub dos_command(ubyte c, str name, str old) {
        if c == 'r' {
            ubyte plen = prefix_len(name)
            sys.memcopy(name, &old_name, plen)
            void strings.copy(old, &old_name + plen)
            rename_file(old_name, name)
        }
    }

    ; (features.DOS, features.DIR: CBM DOS only, off here)
    sub dos_cmd(str command) {
    }
    sub dir_cmd(str name, bool insert) {
    }
}
