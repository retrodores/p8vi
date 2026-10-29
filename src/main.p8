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

    str filename = "sampsmall.txt"

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
        status_bytes(filename, gapbuffer.length())
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

    sub key_mode_cmd () {
        when key {
            KEY_ESCAPE -> handle_escape()
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
                if last_key == 'Z' sys.exit(0)
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
        uword count
        txt.lowercase()
        platform.init()
        gapbuffer.init(sys.progend(), platform.RAMTOP)
        count = read_file(filename, gapbuffer.ramstart, gapbuffer.free())
        ; the text is at ramstart, put the gap after it
        void gapbuffer.loaded(count)
        ; files from other systems use LF line endings
        if gapbuffer.find_next($0d, 0, count) == count and gapbuffer.find_next($0a, 0, count) != count
            gapbuffer.eol = $0a
        cur_line = 0
        goal_col = 0
        mode = MODE_NAV
        txt.cls()
    }

    ; reads user provided file into buffer, at most readsize bytes.
    ; returns the number of bytes read.
    ; returns zero if f_open or f_read fails.
    sub read_file(pointer name, pointer buffer, uword readsize) -> uword {
        uword count = 0
        txt.nl()
        txt.print("reading: ")
        txt.print(name)
        if diskio.f_open(name) {
            ; need to add error checking here
            count = diskio.f_read(buffer, readsize)
            txt.print(" (")
            txt.print_uw(count)
            txt.print(" bytes)")
            txt.nl()
        } else {
            txt.nl()
            txt.print("\nERROR: failed to open file.\n")
            txt.nl()
        }
        diskio.f_close()
        return count
    }

    ; write buffer to output filename.
    ; XXX: needs better handling of errors.
    sub file_write(pointer name, pointer buffer, uword size) -> uword {
        ;uword count = 0
        txt.nl()
        txt.print("Writing: ")
        txt.print(name)
        txt.nl()
        txt.print("Expecting ")
        txt.print_uw(size)
        txt.print(" bytes")
        txt.nl()
        if diskio.f_open_w(name) {
            ; check status() here first...
            if diskio.f_write(buffer, size) {
                diskio.f_close_w()
                txt.print("Done (")
                txt.print_uw(size)
                txt.print(" bytes)")
                txt.nl()
            } else {
                ; should check status() here also.
                txt.print("\nwrite error\n")
            }
        } else {
            txt.print("\nERROR: failed to open file.\n")
        }
        ; file is left in an inconsistent state and
        ; zero length if we don't close it properly
        diskio.f_close_w()
        return 0
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
