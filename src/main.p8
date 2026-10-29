%import diskio
%import strings
%import textio
%zeropage basicsafe
%option no_sysinit

%import gapbuffer
%import platform

main {
    const ubyte MODE_CMD        = 0
    const ubyte MODE_INSERT     = 1
    const ubyte MODE_NAV        = 2
    const ubyte MODE_OVERTYPE   = 3
    const ubyte MODE_REPLACE    = 4

    ubyte mode
    ubyte key
    ubyte char_save
    uword numbers
    ubyte last_key
    bool cursor_active
    sub start() {
        init()
        view.draw_screen()
        repeat {
            key = cbm.GETIN2()
            draw_cursor()
            if key == $00 continue
            when mode {
                MODE_CMD -> key_mode_cmd()
                MODE_INSERT -> key_mode_insert()
                MODE_NAV -> key_mode_nav()
                MODE_OVERTYPE -> key_mode_overtype()
                MODE_REPLACE -> key_mode_replace()
            }
            last_key = key
        }
    }

    sub cursor_off() {
        main.cursor_active = false
        if main.char_save != $00 {
            txt.setchr(view.column, view.row, main.char_save)
            main.char_save = $00
        }
    }

    sub cursor_on() {
        ubyte temp = txt.getchr(view.column, view.row)
        if main.char_save == $00 and temp != CHAR_CURSOR {
            main.char_save = temp
            txt.setchr(view.column, view.row, CHAR_CURSOR)
        } else {
            status("cursor blink broken")
        }
        main.cursor_active = true
    }

    sub draw_cursor() {
        if not blink_timer() return
        if main.cursor_active
            cursor_off()
        else
            cursor_on()
    }

    sub key_mode_cmd () {
        statusmode("MODE_CMD")
        when key {
            KEY_ESCAPE -> handle_escape()
            else -> { status_ub(key) }
        }
    }

    sub key_mode_insert () {
        statusmode("MODE_INSERT")
        when key {
            KEY_ESCAPE -> handle_escape()
            else -> {
                view.update_point()
                void gapbuffer.insert_char(key, gapbuffer.point)
                view.nav_right()
                ;view.draw_screen()
            }
        }
    }

    sub key_mode_nav () {
        statusmode("MODE_NAV")
        when key {
            ;KEY_0 to KEY_9 -> handle_numbers()
            '0' to '9' -> handle_numbers()
            KEY_CONTROL_L -> view.draw_screen()
            KEY_ESCAPE -> handle_escape()
            KEY_SHIFT_G -> nav_go()
            KEY_H -> view.nav_left()
            KEY_I -> handle_insert()
            KEY_J -> view.nav_down()
            KEY_K -> view.nav_up()
            KEY_L -> view.nav_right()
            KEY_X -> void gapbuffer.delete_char(gapbuffer.point)
            KEY_SHIFT_Z -> handle_shift_z()
            else -> { status_ub(key) }
        }
        statuscursor()
        statuspoint()
        if key < KEY_0 or key > KEY_9 numbers = 0
    }

    sub key_mode_overtype () {
        statusmode("MODE_OVERTYPE")
        when key {
            KEY_ESCAPE -> handle_escape()
            else -> { status_ub(key) }
        }
    }

    sub key_mode_replace () {
        statusmode("MODE_REPLACE")
        when key {
            KEY_ESCAPE -> handle_escape()
            else -> { status_ub(key) }
        }
    }

    sub handle_escape() {
        mode = MODE_NAV
        status("ESCAPE")
    }

    sub handle_insert() {
        mode = MODE_INSERT
        gapbuffer.move_cursor(gapbuffer.point)
        view.draw_screen()
        status("INSERT")
    }

    sub handle_numbers() {
        status("NUMBERS")

        if key == '0' {
            status("COLZERO")
            status_ub(last_key)
            if last_key < '0' or last_key > '9' {
                cursor_off()
                view.column=MIN_COL
                blink_timer()
                cursor_on()
                return
            }
        }
        numbers = (numbers * 10) + (key - '0')
        status_uw(numbers)
    }

    sub handle_shift_z() {
        if last_key == 'Z' sys.exit(0)
    }

    sub nav_go() {
        status("GO JUMP")
        cursor_off()
        if numbers == 1 {
            view.column = MIN_COL
            view.row = MIN_ROW
        }
        blink_timer()
        cursor_on()
    }

    sub status(str msg) {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        txt.plot(0,STATUS_LINE)
        txt.print(" " * 10)
        txt.plot(0,STATUS_LINE)
        txt.print(msg)
        txt.column(tcol)
        txt.row(trow)
    }

    sub statuscursor() {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        ;txt.plot(MAX_COL-6,STATUS_LINE)
        ;txt.print(" " * 6)
        txt.plot(MAX_COL-9,STATUS_LINE)
        txt.print_uw0(view.row)
        txt.chrout(':')
        txt.print_ub0(view.column-MIN_COL)
        txt.column(tcol)
        txt.row(trow)
    }

    sub statusfree() {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        ;txt.plot(MAX_COL-6,STATUS_LINE)
        ;txt.print(" " * 6)
        txt.plot(MAX_COL-36,STATUS_LINE)
        txt.print_uw0(gapbuffer.free())
        txt.column(tcol)
        txt.row(trow)
    }

    sub statusmode(str msg) {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        txt.plot(10,STATUS_LINE)
        txt.print(" " * 10)
        txt.plot(10,STATUS_LINE)
        txt.print(msg)
        txt.column(tcol)
        txt.row(trow)
    }

    sub statuspoint() {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        txt.plot(MAX_COL-27,STATUS_LINE)
        txt.print_uwhex(gapbuffer.gapstart, true)
        txt.spc()
        txt.print_uwhex(gapbuffer.gapend, true)
        txt.spc()
        txt.print_uw0(gapbuffer.point)
        txt.column(tcol)
        txt.row(trow)
    }

    sub status_ub(ubyte msgb) {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        txt.plot(18,STATUS_LINE)
        txt.print_ubhex(msgb,true)
        txt.spc()
        txt.print_ub(msgb)
        txt.column(tcol)
        txt.row(trow)
    }

    sub status_uw(uword msgw) {
        ubyte tcol = txt.get_column()
        ubyte trow = txt.get_row()
        txt.plot(29,STATUS_LINE)
        txt.print_uwhex(msgw,true)
        txt.spc()
        txt.print_uw(msgw)
        txt.column(tcol)
        txt.row(trow)
    }

    sub init() {
        uword count
        txt.lowercase()
        platform.init()
        gapbuffer.init()
        count = read_file("sampsmall.txt", gapbuffer.ramstart, gapbuffer.ramtop - gapbuffer.ramstart)
        ; the text is at ramstart, put the gap after it
        void gapbuffer.loaded(count)
        main.mode = main.MODE_NAV
        ; initial setup of view
        view.init()
    }



    ; reads user provided file into ptextbuf
    ; returns the number of bytes read.
    ; returns zero if f_open or f_read_all fails.
    sub read_file(uword filename, uword buffer, uword readsize) -> uword {
        uword count = 0
        txt.nl()
        txt.print("reading: ")
        txt.print(filename)
        if diskio.f_open(filename) {
            ; need to add error checking here
            count = diskio.f_read_all(buffer)
            ;count = diskio.f_read(buffer, readsize)
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
    sub file_write(uword filename, uword buffer, uword size) -> uword {
        ;uword count = 0
        txt.nl()
        txt.print("Writing: ")
        txt.print(filename)
        txt.nl()
        txt.print("Expecting ")
        txt.print_uw(size)
        txt.print(" bytes")
        txt.nl()
        if diskio.f_open_w(filename) {
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
; Has some kind of mapping between physical screen coordinates and logical buffer.
view {
    ubyte column
    ubyte row
    uword line
    uword addr
    uword screen_start_line
    uword screen_end_line
    ; need a const so use the largest size
    uword[txt.DEFAULT_HEIGHT] screen_rows

    ; do initial setup for the view
    sub init() {
        column = main.MIN_COL
        row = main.MIN_ROW
        addr = gapbuffer.bufstart   ; addr of top left screen character in buffer (0 rel)
        line = 1                    ; line number in buffer of top screen row
        screen_start_line = 1       ; what buffer line is on physical screen start
        screen_end_line = 1         ; what buffer line is on physical screen end (or last)
        clear_screen_rows()
    }

    ; reset array to $ffff
    sub clear_screen_rows() {
        ubyte i
        for i in 0 to txt.DEFAULT_HEIGHT {
            screen_rows[i] = $ffff
        }
    }

    ; draw the text buffer portion of the screen
    sub draw_screen() {
        ; TODO should do this later so we can skip gap in drawing?
        ; maybe use ramstart[ptr]
        ; manually calculate gapstart/gapend offset in while drawing?
        uword ptr = addr
        ubyte line_count
        ubyte temp
        txt.cls()
        txt.plot(main.MIN_COL,main.MIN_ROW)

        ; reset array of row pointers
        clear_screen_rows()
        ; *_ROW are zero relative so add 1 for a count
        repeat main.MAX_ROW - main.MIN_ROW + 1 {
            ; save buffer address of row to physical row index
            screen_rows[txt.get_row()] = ptr
            temp = gapbuffer.get(ptr)
            while temp != $0d and temp != $0a {
                txt.chrout(temp)
                ptr++
                temp = gapbuffer.get(ptr)
            }
            line_count++
            if line_count >= main.MAX_ROW break
            txt.nl()
            txt.column(main.MIN_COL)
            ; skip over line ending character
            ptr++
        }
        main.status("STATUS LINE")
        main.statuscursor()
        main.statusfree()
        main.statuspoint()
        main.status_ub(0)
        screen_end_line = screen_start_line + line_count as uword
    }

    ; returns the address (not buffer offset?) of the start of a specific line
    ; Lines are text followed by a line ending or a single bare line ending.
    ; TODO: make configurable line endings.  CR, LF, CRLF, etc?
    ; this is not necessarily a line on screen, but a line in the buffer anywhere.
    ; the caller will use this address as a starting point to render the screen.
    sub line_addr(uword number) -> uword {
        uword count
        uword ptr

        ptr = gapbuffer.ramstart    ; ram addr not buffer offset
        ; very beginning of the buffer is considered line 1.
        count = 1
        while count < number {
            ; don't count anything in the gap buffer
            if ptr == gapbuffer.gapstart
                ptr = gapbuffer.gapend + 1  ; skip over gap
            ; stop by the end of the buffer
            if ptr == gapbuffer.ramend() break
            if @(ptr) == $0d count++
            ptr++
        }
        ; returns pointer to character after count carriage returns
        ; or the last character in the buffer
        ; is gapend == bufend correct?  gapend could be a gap byte and
        ; bufend should be a buffer byte.  TODO: fix
        return ptr
    }

    ; move our view down one line in the buffer which could be more
    ; than one line on the screen
    sub nav_down() {
        ubyte trow = view.row
        uword taddr
        main.status("DOWN")
        main.cursor_off()
        ; TODO: need to scroll of course
        if trow < main.MAX_ROW
            trow++
        taddr = screen_rows[trow]

        ; should scroll
        while taddr == $ffff  and trow < main.MAX_ROW {
            trow++
            taddr = screen_rows[trow]
        }

        ; we found another row start below 
        if taddr != $ffff {
            addr = taddr
            row = trow
        }
        update_point()
        main.blink_timer()
        main.cursor_on()
    }

    ; move cursor/position left
    sub nav_left() {
        main.status("LEFT")
        main.cursor_off()
        if view.column > main.MIN_COL
            view.column--
        update_point()
        main.blink_timer()
        main.cursor_on()
    }

    sub nav_right() {
        main.status("RIGHT")
        main.cursor_off()
        if view.column < main.MAX_COL
            view.column++
        update_point()
        main.blink_timer()
        main.cursor_on()
    }

    ; move our view up one line in the buffer which could be more
    ; than one line on the screen
    sub nav_up() {
        ubyte trow = view.row
        uword taddr
        main.status("UP")
        main.cursor_off()
        ; TODO: need to scroll of course
        if trow > main.MIN_ROW
            trow--
        taddr = screen_rows[trow]

        ; should scroll
        while taddr == $ffff  and trow > main.MIN_ROW {
            trow--
            taddr = screen_rows[trow]
        }

        ; we found another row start above 
        if taddr != $ffff {
            addr = taddr
            row = trow
        }
        update_point()
        main.blink_timer()
        main.cursor_on()
    }

    ; does this need to account for where the gap buffer is?
    ; if point would be between gapstart / gapend, move gap to point
    sub update_point() {
        if screen_rows[view.row] == $ffff txt.print("NULL screen_row")
        gapbuffer.point = screen_rows[view.row] + (view.column - main.MIN_COL) as uword
        ; redraw row:col on status line
        ;main.statuscursor()
    }

} ; end of view block
