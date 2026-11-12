%import diskio
%import strings
%import textio
%import exec
%import charset_platform
%import strings_platform

;
; p8vi on the Amiga (amiga500 target, Kickstart 1.3 and later), in its CLI
; window: console.device is an ANSI terminal, so the screen is
; src/cpm/textio.p8's, kept in memory and sent when it changes, through
; src/amiga/console_platform.p8 (raw mode, keys).  Files are AmigaDOS's
; (src/amiga/diskio.p8, until the compiler's library has an Amiga
; diskio): new ones get LF line endings.  The editor core is the wide one
; (32-bit positions, as the host's), its undo records read a byte at a
; time (tools/encode_copy.py --bytewise: the 68000's longs must be at even
; addresses).  The other platform files are the CP/M version's and the
; TRS-80's.
;
;   p8vi [-s COLSxROWS] [file]
;
; The screen is the window's size when p8vi starts (the console's window
; status request), up to 160 x 80; -s gives a size instead.  The text
; gets the largest free block of memory, less 32 KB for AmigaDOS.
;
platform {
    const ubyte COLUMNS = txt.DEFAULT_WIDTH

    ; memory for the text (the gap buffer), set by init()
    pointer textstart
    pointer texttop         ; 1 byte past the last usable byte
    ; spare memory, for the key buffers and the like (none here: they
    ; come off the text's top)
    pointer sparestart
    pointer sparetop

    ; the text's memory (and the editor's small buffers, off its top: see
    ; main.take_memory): the largest free block (exec.AllocMem), less
    ; MEM_KEPT for AmigaDOS, at most pos.TEXT_MAX; freed in stop()
    const long MEM_KEPT = 32 * 1024
    long text_size

    sub init() {
        options()
        if not console.start() {
            txt.out_str("p8vi: runs in a CLI window\n")
            console.flush()
            sys.exit(1)
        }
        text_size = exec.AvailMem(exec.MEMF_LARGEST) - MEM_KEPT
        if text_size > pos.TEXT_MAX
            text_size = pos.TEXT_MAX
        if text_size >= 16 * 1024
            textstart = exec.AllocMem(text_size, exec.MEMF_PUBLIC)
        if textstart == 0 {
            console.stop()
            txt.out_str("p8vi: not enough memory\n")
            console.flush()
            sys.exit(1)
        }
        texttop = textstart + text_size
        sparestart = texttop
        sparetop = texttop
        follow_size()
        set_screen()
        ; (the test build) the keys to play, from keys.txt
        if features.KEYFILE and diskio.f_open(KEY_FILE) {
            main.key_count = diskio.f_read(&main.key_buf, len(main.key_buf)) as uword
            diskio.f_close()
        }
    }

    ; (features.KEYFILE, the test build: tests/amiga/amigatest.py) the
    ; keys get_key() gives first: the editor's codes, as
    ; tests/vice/edtest.py's suites type them
    str KEY_FILE = "keys.txt"

    ; the editor's screen size from txt's
    sub set_screen() {
        main.SCREEN_WIDTH    = txt.width()
        main.SCREEN_HEIGHT   = txt.height()
        main.STATUS_HEIGHT   = 1
        main.MIN_COL         = 0
        main.MAX_COL         = main.SCREEN_WIDTH - 1
        main.MIN_ROW         = 0
        main.MAX_ROW         = main.SCREEN_HEIGHT - main.STATUS_HEIGHT - 1
        main.STATUS_LINE     = main.SCREEN_HEIGHT - 1
    }

    bool fixed_size     ; -s: the size is the one given, not the window's
    bool resized        ; (the window's size isn't followed yet: never set)

    ; the window's size, when it isn't given: asked once, at the start
    ; (console.size: 80 x 24 if the console doesn't say)
    sub follow_size() {
        if fixed_size
            return
        uword s = console.size()
        if s != 0
            txt.resize(lsb(s), msb(s))
    }

    ; the command line (sys.arguments, one string): -s COLSxROWS and a
    ; file to edit ("quotes" around a name with spaces).  An unknown
    ; option ends the program with a usage line, before anything is drawn.
    ubyte[80] arg_buf
    sub options() {
        pointer a = sys.arguments
        if a == 0
            return
        repeat {
            a = next_arg(a)
            if arg_buf[0] == 0
                return
            if arg_buf[0] == '-' and (arg_buf[1] == 'S' or arg_buf[1] == 's') {
                if arg_buf[2] == 0 {
                    a = next_arg(a)
                    if arg_buf[0] == 0
                        usage()
                    size_option(&arg_buf)
                } else
                    size_option(&arg_buf + 2)
            } else if arg_buf[0] != '-' and start_keys[0] == 0 and strings.length(arg_buf) < len(start_keys) - 5 {
                ; the file: typed as :e name
                void strings.copy(":e ", start_keys)
                void strings.copy(arg_buf, &start_keys + 3)
                start_keys[strings.length(start_keys)] = 13
            } else
                usage()
        }
    }

    ; (options) the next word of the arguments from a into arg_buf ("" at
    ; the end); returns where the rest starts
    sub next_arg(pointer a) -> pointer {
        ubyte n = 0
        while @(a) == ' ' or @(a) == 9 or @(a) == 10
            a++
        if @(a) == '"' {
            a++
            while @(a) != 0 and @(a) != '"' and @(a) != 10 and n < len(arg_buf) - 1 {
                arg_buf[n] = @(a)
                n++
                a++
            }
            if @(a) == '"'
                a++
        } else {
            while @(a) > ' ' and n < len(arg_buf) - 1 {
                arg_buf[n] = @(a)
                n++
                a++
            }
        }
        arg_buf[n] = 0
        return a
    }

    ; the file named on the command line, typed as :e name and Enter
    ubyte[84] start_keys
    ubyte start_pos

    sub usage() {
        txt.out_str("usage: p8vi [-s COLSxROWS] [file]\n")
        console.flush()
        sys.exit(1)
    }

    ; -s COLSxROWS: the screen's size (kept within 20 x 4 and 160 x 80)
    sub size_option(pointer arg) {
        uword c = 0
        uword r = 0
        while @(arg) >= '0' and @(arg) <= '9' and c < 1000 {
            c = c * 10 + @(arg) - '0'
            arg++
        }
        if @(arg) != 'x' and @(arg) != 'X'
            usage()
        arg++
        while @(arg) >= '0' and @(arg) <= '9' and r < 1000 {
            r = r * 10 + @(arg) - '0'
            arg++
        }
        if @(arg) != 0 or c == 0 or r == 0
            usage()
        txt.resize(min(c, 255) as ubyte, min(r, 255) as ubyte)
        fixed_size = true
    }

    ; before the program ends: what is left to send, the window in its
    ; normal mode, the text's memory freed
    sub stop() {
        txt.done()
        console.stop()
        if textstart != 0 {
            exec.FreeMem(textstart, text_size)
            textstart = 0
        }
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

    ; (a new window size: not followed yet)
    const bool SWITCH = false
    sub switch_wanted() -> bool {
        return resized
    }
    sub switch_screen() {
        follow_size()
        set_screen()
        txt.repaint()
        resized = false
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
    ; (the TRS-80's name:1; a host path comes first, dir/name, as a
    ; features.PREFIX prefix)
    const bool DRIVE_SUFFIX = false
    ; (features.PREFIX) what ends a path prefix: dir/, and the volume's
    ; df0: or work:
    const ubyte PATH_SEP = '/'
    const ubyte PATH_VOLUME = ':'
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

    ; (CP/M's text files end at the first ^Z; not here)
    const bool CTRL_Z_EOF = false
    ; a new text's line ending: LF
    const ubyte NEW_ENDING = ENDING_LF

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

    ; a key: ASCII (ISO-8859-1) as the console sends it.  DEL (127) and
    ; backspace (8) delete (DEL), Ctrl-C is RUN/STOP (an Escape), the
    ; cursor keys' CSI sequences are the arrows (txt.escape_key: the
    ; console's CSI is $9B, given to it as ESC [).  It waits for the key;
    ; when the input ends, so does the program (exit status 1).
    const uword KEY_BUF_SIZE = 1024
    ubyte[if features.KEYFILE KEY_BUF_SIZE else 1] key_buf
    uword key_count
    uword key_pos
    sub get_key() -> ubyte {
        if features.KEYFILE and key_pos < key_count {
            ; (the test build) the screen is sent before each key, as
            ; txt.getkey() does; $ff marks the screen for the test with three
            ; NULs (as tests/cpm/cpmtest.py's)
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
        if platform.start_keys[platform.start_pos] != 0 {
            platform.start_pos++
            return platform.start_keys[platform.start_pos - 1]
        }
        ubyte k
        do {
            k = txt.getkey()
            if k == 0 {
                if console.resized {
                    ; (no key: the editor lays the screen out again)
                    console.resized = false
                    platform.resized = true
                    return 0
                }
                platform.stop()
                sys.exit(1)
            }
            if k == $9b {
                txt.unget('[')
                k = 27
            }
            if k == 27
                k = txt.escape_key()    ; (the arrow keys; 0: a sequence dropped)
        } until k != 0
        when k {
            127, 8 -> return KEY_DEL
            3 -> return KEY_STOP
            KEY_CONTROL_L -> txt.repaint()      ; (the editor draws it all again)
        }
        return k
    }

    ; (only the page store's sync uses it, and this build has the gap
    ; buffer)
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
    ; files.  the host's errors aren't passed on: disk_code is set like CBM
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

    ; rename a file (in one directory: see dos_command).
    ; sets io_failed if it failed.
    sub rename_file(str old, str new) {
        diskio.rename(old, new)
        io_failed = diskio.status_code() != 0
    }

    ; (features.PREFIX) delete a file, the path and all
    sub scratch(str name) {
        diskio.delete(name)
    }

    ; (features.PREFIX) the safe save's rename, as CBM DOS's "r" command:
    ; old (p8vi.tmp) gets name's path, so the rename stays in name's
    ; directory.  sets io_failed if it failed.
    ubyte[40] old_name
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

; the editor's loops use cx16.r0L as a counter (a zero page register on
; the 6502 targets); the m68k targets have no cx16 registers
cx16 {
    ubyte r0L
}
