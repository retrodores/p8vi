%import conv
%import diskio
%import strings
%import textio
%zeropage basicsafe

%import gapbuffer
%import platform

main {
    const ubyte MODE_CMD        = 0
    const ubyte MODE_INSERT     = 1
    const ubyte MODE_NAV        = 2
    const ubyte MODE_OVERTYPE   = 3
    const ubyte MODE_REPLACE    = 4

    ; gap buffer marks used by the editor
    const ubyte MARK_CURSOR     = 0     ; buffer offset of the cursor
    const ubyte MARK_TOP        = 1     ; buffer offset of the top left of the screen

    ; more keys
    const ubyte KEY_RETURN      = $0d
    const ubyte KEY_DEL         = $14
    const ubyte KEY_CONTROL_G   = 7
    const ubyte KEY_DOLLAR      = '$'
    const ubyte KEY_COLON       = ':'

    str filename = " " * 40     ; name of the file being edited, empty if none
    str cmdline = " " * 40      ; text typed after ':'
    ubyte cmdlen
    bool cut_short              ; the file did not fit, so saving it over itself loses text

    ubyte mode
    ubyte key
    ubyte char_save
    uword numbers       ; count typed before a command
    ubyte last_key
    bool cursor_active
    uword cur_line      ; line number of the cursor (zero relative)
    uword goal_col      ; column j and k try to keep

    sub start() {
        init()
        view.refresh(true)
        cursor_on()
        repeat {
            key = cbm.GETIN2()
            if key == $00 {
                draw_cursor()
                continue
            }
            cursor_off()
            when mode {
                MODE_CMD -> key_mode_cmd()
                MODE_INSERT -> key_mode_insert()
                MODE_NAV -> key_mode_nav()
                MODE_OVERTYPE -> key_mode_overtype()
                MODE_REPLACE -> key_mode_replace()
            }
            last_key = key
            view.refresh(false)
            if mode == MODE_CMD {
                ; the cursor is on the command line
                view.column = min(1 + cmdlen, SCREEN_WIDTH - 2)
                view.row = STATUS_LINE
            }
            void blink_timer()
            cursor_on()
        }
    }

    ;
    ; cursor display
    ;

    sub cursor_off() {
        if cursor_active {
            txt.setchr(view.column, view.row, char_save)
            cursor_active = false
        }
    }

    ; show the character under the cursor in reverse
    sub cursor_on() {
        if not cursor_active {
            char_save = txt.getchr(view.column, view.row)
            txt.setchr(view.column, view.row, char_save ^ $80)
            cursor_active = true
        }
    }

    sub draw_cursor() {
        if not blink_timer() return
        if cursor_active
            cursor_off()
        else
            cursor_on()
    }

    ;
    ; key handling per mode
    ;

    ; typing a ':' command on the status line
    sub key_mode_cmd () {
        when key {
            KEY_ESCAPE -> handle_escape()
            KEY_RETURN -> {
                handle_escape()
                execute()
            }
            KEY_DEL -> {
                if cmdlen == 0 {
                    handle_escape()
                } else {
                    cmdlen--
                    cmdline[cmdlen] = 0
                }
            }
            else -> {
                ; stop short of the last column so the screen does not scroll
                if ((key >= 32 and key < 128) or key >= 160) and
                        cmdlen < len(cmdline) - 1 and cmdlen < SCREEN_WIDTH - 2 {
                    cmdline[cmdlen] = key
                    cmdlen++
                    cmdline[cmdlen] = 0
                }
            }
        }
        if mode == MODE_CMD
            draw_cmdline()
    }

    sub draw_cmdline() {
        ubyte used
        txt.plot(0, STATUS_LINE)
        txt.chrout(':')
        used = 1 + view.print_max(cmdline, SCREEN_WIDTH - 2)
        while used < SCREEN_WIDTH - 1 {
            txt.spc()
            used++
        }
    }

    sub key_mode_insert () {
        when key {
            KEY_ESCAPE -> {
                mode = MODE_NAV
                status("")
                ; like vi, leaving insert mode moves back onto the last character
                if cursor() > gapbuffer.line_start(cursor())
                    set_cursor(cursor() - 1)
                goal_col = column()
            }
            KEY_RETURN -> insert_key(gapbuffer.eol)
            KEY_DEL -> {
                if cursor() > 0 {
                    if gapbuffer.get(cursor() - 1) == gapbuffer.eol
                        cur_line--
                    ; the cursor mark moves back by itself
                    void gapbuffer.delete_char(cursor() - 1)
                    view.dirty = true
                }
            }
            else -> {
                if (key >= 32 and key < 128) or key >= 160
                    insert_key(key)
            }
        }
    }

    sub insert_key(ubyte char) {
        if gapbuffer.insert_char(char, cursor()) {
            ; a mark at the insertion point stays, so move the cursor past it
            set_cursor(cursor() + 1)
            if char == gapbuffer.eol
                cur_line++
            view.dirty = true
        } else {
            status("buffer full")
        }
    }

    sub key_mode_nav () {
        uword count

        ; a count before a command, '0' on its own is a command
        if (key >= '1' and key <= '9') or (key == '0' and numbers != 0) {
            numbers = numbers * 10 + (key - '0')
            return
        }
        count = max(numbers, 1)

        when key {
            KEY_0 -> {
                set_cursor(gapbuffer.line_start(cursor()))
                goal_col = 0
            }
            KEY_DOLLAR -> {
                set_cursor(last_char(cursor()))
                goal_col = $ffff
            }
            KEY_CONTROL_L -> view.refresh(true)
            KEY_CONTROL_G -> show_info()
            KEY_COLON -> {
                mode = MODE_CMD
                cmdlen = 0
                cmdline[0] = 0
                draw_cmdline()
            }
            KEY_ESCAPE -> handle_escape()
            KEY_SHIFT_G -> nav_go()
            KEY_H -> repeat count nav_left()
            KEY_A -> {
                mode = MODE_INSERT
                status("-- INSERT --")
                if cursor() < gapbuffer.line_end(cursor())
                    set_cursor(cursor() + 1)
            }
            KEY_I -> {
                mode = MODE_INSERT
                status("-- INSERT --")
            }
            KEY_J -> repeat count nav_down()
            KEY_K -> repeat count nav_up()
            KEY_L -> repeat count nav_right()
            KEY_X -> delete_chars(count)
            KEY_SHIFT_Z -> {
                ; ZZ is :x, write if modified and quit
                if last_key == 'Z' and (not gapbuffer.modified or write_cmd("", false))
                    quit(true)
            }
        }
        numbers = 0
    }

    sub key_mode_overtype () {
        when key {
            KEY_ESCAPE -> handle_escape()
        }
    }

    sub key_mode_replace () {
        when key {
            KEY_ESCAPE -> handle_escape()
        }
    }

    sub handle_escape() {
        mode = MODE_NAV
        numbers = 0
        status("")
    }

    ;
    ; cursor movement and editing, all in buffer offsets
    ;

    sub cursor() -> uword {
        return gapbuffer.get_mark(MARK_CURSOR)
    }

    sub set_cursor(uword position) {
        gapbuffer.set_mark(MARK_CURSOR, position)
    }

    ; column of the cursor in its line
    sub column() -> uword {
        return cursor() - gapbuffer.line_start(cursor())
    }

    ; offset of the last character of the line containing position
    ; (the line start for an empty line).  vi keeps the cursor on a
    ; character in nav mode, never on the line ending.
    sub last_char(uword position) -> uword {
        uword start = gapbuffer.line_start(position)
        uword end = gapbuffer.line_end(position)
        if end > start
            return end - 1
        return start
    }

    ; move to goal_col in the line starting at start
    sub to_goal(uword start) {
        uword last = last_char(start)
        if goal_col > last - start
            set_cursor(last)
        else
            set_cursor(start + goal_col)
    }

    sub nav_left() {
        if cursor() > gapbuffer.line_start(cursor())
            set_cursor(cursor() - 1)
        goal_col = column()
    }

    sub nav_right() {
        if cursor() < last_char(cursor())
            set_cursor(cursor() + 1)
        goal_col = column()
    }

    sub nav_down() {
        uword next = gapbuffer.next_line(cursor())
        if next != gapbuffer.NONE {
            to_goal(next)
            cur_line++
        }
    }

    sub nav_up() {
        uword prev = gapbuffer.prev_line(cursor())
        if prev != gapbuffer.NONE {
            to_goal(prev)
            cur_line--
        }
    }

    ; G goes to the last line, nG to line n
    sub nav_go() {
        uword start
        if numbers != 0 {
            start = gapbuffer.line_offset(numbers - 1)
            if start != gapbuffer.NONE {
                cur_line = numbers - 1
                goal_col = 0
                to_goal(start)
                return
            }
        }
        cur_line = gapbuffer.line_number(gapbuffer.length())
        goal_col = 0
        to_goal(gapbuffer.line_start(gapbuffer.length()))
    }

    ; delete count characters at the cursor, but not past the end of the line
    sub delete_chars(uword count) {
        uword room = gapbuffer.line_end(cursor()) - cursor()
        if room == 0
            return
        void gapbuffer.delete_nchar(min(count, room), cursor())
        ; deleting the last character leaves the cursor on the line ending
        set_cursor(min(cursor(), last_char(cursor())))
        view.dirty = true
    }

    ;
    ; status line
    ;

    ; width of the message part of the status line, the rest shows the position
    sub message_width() -> ubyte {
        return SCREEN_WIDTH - 10
    }

    sub status(str msg) {
        txt.plot(0, STATUS_LINE)
        status_pad(view.print_max(msg, message_width()))
    }

    sub status_bytes(str name, uword count) {
        ubyte used
        txt.plot(0, STATUS_LINE)
        used = view.print_max(name, message_width() - 7)
        txt.spc()
        txt.print_uw(count)
        status_pad(used + 1 + num_digits(count))
    }

    sub show_info() {
        uword lines = gapbuffer.line_number(gapbuffer.length()) + 1
        txt.plot(0, STATUS_LINE)
        txt.print_uw(lines)
        txt.print("L ")
        txt.print_uw(gapbuffer.free())
        txt.chrout('F')
        status_pad(num_digits(lines) + 2 + num_digits(gapbuffer.free()) + 1)
    }

    ; clear the rest of the message part of the status line
    sub status_pad(ubyte used) {
        while used < message_width() {
            txt.spc()
            used++
        }
    }

    ; show line,column on the right of the status line.
    ; stops short of the last column so the screen does not scroll.
    sub status_position() {
        ubyte used
        txt.plot(message_width(), STATUS_LINE)
        txt.print_uw(cur_line + 1)
        txt.chrout(',')
        txt.print_uw(column() + 1)
        used = message_width() + num_digits(cur_line + 1) + 1 + num_digits(column() + 1)
        while used < SCREEN_WIDTH - 1 {
            txt.spc()
            used++
        }
    }

    sub num_digits(uword value) -> ubyte {
        ubyte digits = 1
        while value >= 10 {
            value /= 10
            digits++
        }
        return digits
    }

    ;
    ; startup and files
    ;

    sub init() {
        txt.lowercase()
        platform.init()
        gapbuffer.init(sys.progend(), platform.ramtop)
        mode = MODE_NAV
        txt.cls()
        void strings.copy("sampsmall.txt", filename)
        void load_file(filename, false)
    }

    ;
    ; ':' commands
    ;
    ;   :w[!] [name]    write the file (or to name)
    ;   :q[!]           quit, ! discards changes
    ;   :wq[!] [name]   write and quit
    ;   :x[!] [name]    write if modified and quit (also ZZ)
    ;   (writing a file that was cut short when read over itself needs !)
    ;   :e[!] name  edit another file, ! discards changes; :e! reloads
    ;   :r [name]   read a file in below the cursor line
    ;   :n          go to line n
    ;

    str cmdword = " " * 4

    sub execute() {
        ubyte i = 0
        ubyte n = 0
        bool force = false
        uword line
        pointer arg

        while cmdline[i] == ' '
            i++
        if cmdline[i] == 0
            return

        ; :n goes to line n
        if cmdline[i] >= '0' and cmdline[i] <= '9' {
            line = conv.str2uword(&cmdline + i)
            numbers = max(line, 1)
            nav_go()
            numbers = 0
            return
        }

        ; command letters, an optional '!', then the argument
        while cmdline[i] >= 'a' and cmdline[i] <= 'z' and n < len(cmdword) - 1 {
            cmdword[n] = cmdline[i]
            n++
            i++
        }
        cmdword[n] = 0
        if cmdline[i] == '!' {
            force = true
            i++
        }
        while cmdline[i] == ' '
            i++
        arg = &cmdline + i

        if strings.compare(cmdword, "w") == 0
            void write_cmd(arg, force)
        else if strings.compare(cmdword, "q") == 0
            quit(force)
        else if strings.compare(cmdword, "wq") == 0 {
            if write_cmd(arg, force)
                quit(true)
        }
        else if strings.compare(cmdword, "x") == 0 {
            if not gapbuffer.modified or write_cmd(arg, force)
                quit(true)
        }
        else if strings.compare(cmdword, "e") == 0
            edit_cmd(arg, force)
        else if strings.compare(cmdword, "r") == 0
            read_cmd(arg)
        else
            status("unknown cmd")
    }

    ; returns arg, or the current file name if arg is empty
    sub name_or_current(str arg) -> str {
        if arg[0] != 0
            return arg
        return filename
    }

    ; :w - returns true if the file was written
    sub write_cmd(str arg, bool force) -> bool {
        pointer name = name_or_current(arg)
        bool same
        if name[0] == 0 {
            status("no file name")
            return false
        }
        if filename[0] == 0
            void strings.copy(name, filename)
        same = strings.compare(name, filename) == 0
        if same and cut_short and not force {
            status("file cut (!)")
            return false
        }
        if not save_file(name)
            return false
        ; writing a copy elsewhere still leaves this file unsaved
        if same {
            gapbuffer.modified = false
            cut_short = false
        }
        return true
    }

    sub quit(bool force) {
        if gapbuffer.modified and not force {
            status("unsaved (!)")
            return
        }
        txt.cls()
        sys.exit(0)
    }

    ; :e - replace the text with another file
    sub edit_cmd(str arg, bool force) {
        pointer name = name_or_current(arg)
        if gapbuffer.modified and not force {
            status("unsaved (!)")
            return
        }
        if name[0] == 0 {
            status("no file name")
            return
        }
        if load_file(name, false) {
            void strings.copy(name, filename)
        } else if disk_code == 62 and arg[0] != 0 {
            ; like vi, a file that does not exist yet starts out empty
            void strings.copy(name, filename)
            gapbuffer.clear()
            new_text()
            cut_short = false
            status("new file")
        }
    }

    ; :r - insert a file below the cursor line
    sub read_cmd(str arg) {
        pointer name = name_or_current(arg)
        if name[0] == 0 {
            status("no file name")
            return
        }
        void load_file(name, true)
    }

    ;
    ; files
    ;

    ; read a file, replacing the text or inserting it below the cursor line.
    ; shows the result on the status line, returns false if it can't be opened
    ; (the text is not changed then).
    sub load_file(str name, bool insert) -> bool {
        uword count
        uword position
        ubyte extra
        bool truncated = false

        if not diskio.f_open(name) {
            disk_error()
            return false
        }
        if insert {
            position = gapbuffer.next_line(cursor())
            if position == gapbuffer.NONE {
                ; the cursor is on the last line: start a new line after it
                position = gapbuffer.length()
                if position != 0 and gapbuffer.get(position - 1) != gapbuffer.eol {
                    void gapbuffer.insert_char(gapbuffer.eol, position)
                    position++
                }
            }
            ; read straight into the gap
            gapbuffer.move_gap(position)
            count = diskio.f_read(gapbuffer.gap_ptr(), gapbuffer.free())
            gapbuffer.inserted(count)
            set_cursor(position)
            cur_line = gapbuffer.line_number(position)
            goal_col = 0
        } else {
            count = diskio.f_read(gapbuffer.ramstart, (gapbuffer.ramtop - gapbuffer.ramstart) as uword)
            void gapbuffer.loaded(count)
            new_text()
        }
        ; a full buffer may mean the file did not fit
        if gapbuffer.free() == 0 and diskio.f_read(&extra, 1) == 1
            truncated = true
        diskio.f_close()
        view.dirty = true
        if not insert
            cut_short = truncated
        if truncated
            status("too big, cut")
        else
            status_bytes(name, count)
        return true
    }

    ; reset the editor for new text in the buffer
    sub new_text() {
        uword length = gapbuffer.length()
        ; files from other systems use LF line endings
        gapbuffer.eol = $0d
        if gapbuffer.find_next($0d, 0, length) == length and gapbuffer.find_next($0a, 0, length) != length
            gapbuffer.eol = $0a
        cur_line = 0
        goal_col = 0
        view.dirty = true
    }

    ; write the whole text to a file, replacing it if it exists.
    ; returns false (and shows the drive status) if that fails.
    sub save_file(str name) -> bool {
        pointer p1
        pointer p2
        uword n1
        uword n2
        bool ok
        ; CBM DOS can't open an existing file for writing
        if diskio.exists(name)
            diskio.delete(name)
        if not platform.open_write(name) {
            disk_error()
            return false
        }
        p1, n1, p2, n2 = gapbuffer.segments()
        ok = diskio.f_write(p1, n1) and diskio.f_write(p2, n2)
        diskio.f_close_w()
        if not ok or diskio.status_code() != 0 {
            disk_error()
            return false
        }
        status_bytes(name, gapbuffer.length())
        return true
    }

    ; drive status code from the last disk_error()
    ubyte disk_code

    ; show the drive status message and remember its code.
    ; reading the status clears it, so check disk_code afterwards, not
    ; diskio.status_code().
    sub disk_error() {
        pointer msg = diskio.status()
        disk_code = 255
        if msg[0] >= '0' and msg[0] <= '9' and msg[1] >= '0' and msg[1] <= '9'
            disk_code = (msg[0] - '0') * 10 + (msg[1] - '0')
        status(msg)
    }
}

; Contains the View which is looking into a portion of the buffer.
; Maps the text rows of the screen (main.MIN_ROW..MAX_ROW, main.MIN_COL..MAX_COL)
; to buffer offsets.  Long lines wrap onto the next row.
; Works for any screen size up to txt.DEFAULT_WIDTH x txt.DEFAULT_HEIGHT.
view {
    const uword NONE = gapbuffer.NONE

    ubyte column    ; screen position of the cursor
    ubyte row
    bool dirty      ; the text changed and the screen must be redrawn

    ; buffer offset and length of the text on each screen row, NONE past the end
    uword[txt.DEFAULT_HEIGHT] row_start
    ubyte[txt.DEFAULT_HEIGHT] row_len
    uword drawn_top = NONE

    ubyte[txt.DEFAULT_WIDTH] linebuf

    ; number of text columns
    sub width() -> ubyte {
        return main.MAX_COL - main.MIN_COL + 1
    }

    ; make sure the cursor is on screen (scrolling if needed),
    ; redraw if anything changed, and update the status line.
    sub refresh(bool force) {
        uword cursor = main.cursor()
        uword top
        uword prev
        ; cursor above the screen: its row becomes the top row
        if cursor < gapbuffer.get_mark(main.MARK_TOP)
            gapbuffer.set_mark(main.MARK_TOP, row_of(cursor))
        layout()
        if not locate() {
            ; cursor below the screen: its row becomes the bottom row
            top = row_of(cursor)
            repeat main.MAX_ROW - main.MIN_ROW {
                prev = prev_row(top)
                if prev == NONE
                    break
                top = prev
            }
            gapbuffer.set_mark(main.MARK_TOP, top)
            layout()
            void locate()
        }
        if force or dirty or gapbuffer.get_mark(main.MARK_TOP) != drawn_top {
            draw()
            dirty = false
            drawn_top = gapbuffer.get_mark(main.MARK_TOP)
        }
        if main.mode != main.MODE_CMD
            main.status_position()
    }

    ; returns the start of the screen row (part of a wrapped line) containing position
    sub row_of(uword position) -> uword {
        uword start = gapbuffer.line_start(position)
        uword offset = position - start
        uword rows = offset / width()
        ; at the end of a line that exactly fills its last row the
        ; cursor is shown after that row, not on an empty row below it
        if rows != 0 and offset == rows * width() and
                (position >= gapbuffer.length() or gapbuffer.get(position) == gapbuffer.eol)
            rows--
        return start + rows * width()
    }

    ; returns the start of the screen row before the one starting at
    ; start, or NONE at the start of the text
    sub prev_row(uword start) -> uword {
        if start == 0
            return NONE
        return row_of(start - 1)
    }

    ; work out which text goes on each screen row, starting at the top mark
    sub layout() {
        uword position = gapbuffer.get_mark(main.MARK_TOP)
        uword length = gapbuffer.length()
        uword limit
        uword end
        ubyte r
        for r in main.MIN_ROW to main.MAX_ROW {
            row_start[r] = position
            row_len[r] = 0
            if position == NONE
                continue
            if length - position < width()
                limit = length
            else
                limit = position + width()
            end = gapbuffer.find_next(gapbuffer.eol, position, limit)
            row_len[r] = (end - position) as ubyte
            if end < length {
                if gapbuffer.get(end) == gapbuffer.eol
                    position = end + 1      ; next line
                else
                    position = end          ; rest of a wrapped line
            } else {
                position = NONE
            }
        }
    }

    ; find the screen row and column of the cursor.
    ; returns false if it is not on screen.
    sub locate() -> bool {
        uword cursor = main.cursor()
        uword start
        bool found = false
        ubyte r
        for r in main.MIN_ROW to main.MAX_ROW {
            start = row_start[r]
            if start == NONE or cursor < start
                break
            ; the end of a wrapped row is also the start of the next one,
            ; keep looking so the later row wins
            if cursor <= start + row_len[r] {
                row = r
                column = main.MIN_COL + (cursor - start) as ubyte
                if column > main.MAX_COL
                    column = main.MAX_COL
                found = true
            }
        }
        return found
    }

    sub draw() {
        ubyte r
        ubyte i
        ubyte n
        for r in main.MIN_ROW to main.MAX_ROW {
            txt.plot(0, r)
            n = 0
            if row_start[r] == NONE {
                ; rows past the end of the text show a - (vi uses ~, not in petscii)
                txt.chrout('-')
                n = 1
            } else {
                while n < main.MIN_COL {
                    txt.spc()
                    n++
                }
                void gapbuffer.copy_out(row_start[r], row_len[r], linebuf)
                i = 0
                while i < row_len[r] {
                    txt.chrout(printable(linebuf[i]))
                    i++
                }
                n += row_len[r]
            }
            while n < main.SCREEN_WIDTH {
                txt.spc()
                n++
            }
        }
    }

    ; control characters would change the screen, show them as '.'
    sub printable(ubyte char) -> ubyte {
        if char < 32 or (char >= 128 and char < 160)
            return '.'
        return char
    }

    ; print at most maxlen characters of msg, returns how many were printed
    sub print_max(str msg, ubyte maxlen) -> ubyte {
        ubyte n = 0
        while msg[n] != 0 and n < maxlen {
            txt.chrout(msg[n])
            n++
        }
        return n
    }

} ; end of view block
