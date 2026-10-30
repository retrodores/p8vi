%import conv
%import diskio
%import strings
%import textio
%zeropage basicsafe

%import gapbuffer
%import platform

main {
    const ubyte MODE_CMD        = 0     ; typing a ':' command or a '/' or '?' search
    const ubyte MODE_INSERT     = 1
    const ubyte MODE_NAV        = 2
    const ubyte MODE_REPLACE    = 4

    ; gap buffer marks used by the editor
    const ubyte MARK_CURSOR     = 0     ; buffer offset of the cursor
    const ubyte MARK_TOP        = 1     ; buffer offset of the top left of the screen

    ; more keys
    const ubyte KEY_STOP        = $03   ; RUN/STOP, also works as escape
    const ubyte KEY_CONTROL_B   = 2
    const ubyte KEY_CONTROL_D   = 4
    const ubyte KEY_CONTROL_F   = 6
    const ubyte KEY_CONTROL_G   = 7
    const ubyte KEY_RETURN      = $0d
    const ubyte KEY_DOWN        = $11
    const ubyte KEY_HOME        = $13
    const ubyte KEY_DEL         = $14
    const ubyte KEY_CONTROL_U   = $15
    const ubyte KEY_RIGHT       = $1d
    const ubyte KEY_UP          = $91
    const ubyte KEY_LEFT        = $9d
    const ubyte KEY_TILDE       = $de   ; PETSCII has no ~, use pi (shift + up arrow)

    str filename = " " * 40     ; name of the file being edited, empty if none
    str cmdline = " " * 40      ; text typed after ':', '/' or '?'
    ubyte cmdlen
    ubyte cmd_prompt            ; ':', '/' or '?'
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
            if key == KEY_STOP
                key = KEY_ESCAPE
            when mode {
                MODE_CMD -> key_mode_cmd()
                MODE_INSERT -> key_mode_insert()
                MODE_NAV -> key_mode_nav()
                MODE_REPLACE -> key_mode_replace()
            }
            last_key = key
            view.refresh(false)
            if mode == MODE_CMD {
                ; the cursor is on the command line, after the typed text.
                ; (not min(): prog8c 14.0-BETA3 miscompiles min() of two
                ; ubyte expressions on 6502, it returns the second one)
                view.column = 1 + cmdlen
                if view.column > SCREEN_WIDTH - 2
                    view.column = SCREEN_WIDTH - 2
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

    ; typing a ':' command or a '/' or '?' search on the status line
    sub key_mode_cmd () {
        when key {
            KEY_ESCAPE -> handle_escape()
            KEY_RETURN -> {
                handle_escape()
                if cmd_prompt == ':'
                    execute()
                else
                    search_cmd(cmd_prompt == '/')
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
        txt.chrout(cmd_prompt)
        used = 1 + view.print_max(cmdline, SCREEN_WIDTH - 2)
        while used < SCREEN_WIDTH - 1 {
            txt.spc()
            used++
        }
    }

    sub handle_escape() {
        mode = MODE_NAV
        numbers = 0
        pending_op = 0
        op_count = 0
        pending_char = 0
        status("")
    }

    sub start_cmdline(ubyte prompt) {
        mode = MODE_CMD
        cmd_prompt = prompt
        cmdlen = 0
        cmdline[0] = 0
        draw_cmdline()
    }

    sub key_mode_insert () {
        when key {
            KEY_ESCAPE -> leave_insert()
            KEY_RETURN -> insert_key(gapbuffer.eol)
            KEY_DEL -> {
                if cursor() > 0 {
                    ; the cursor mark moves back by itself, so fix the line here
                    if gapbuffer.get(cursor() - 1) == gapbuffer.eol
                        cur_line--
                    void gapbuffer.delete_char(cursor() - 1)
                    view.dirty = true
                }
            }
            KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN -> insert_move()
            else -> {
                if printable(key)
                    insert_key(key)
            }
        }
    }

    ; cursor keys in insert and replace mode, the cursor may go to the line end
    sub insert_move() {
        uword target
        op_active = true
        target = motion(key, 1)
        op_active = false
        set_cursor(target)
        if key == KEY_LEFT or key == KEY_RIGHT
            goal_col = column()
    }

    ; like vi, leaving insert mode moves back onto the last character
    sub leave_insert() {
        mode = MODE_NAV
        status("")
        if cursor() > gapbuffer.line_start(cursor())
            set_cursor(cursor() - 1)
        goal_col = column()
    }

    sub printable(ubyte char) -> bool {
        return (char >= 32 and char < 128) or char >= 160
    }

    sub insert_key(ubyte char) {
        if gapbuffer.insert_char(char, cursor()) {
            ; a mark at the insertion point stays, so move the cursor past it
            set_cursor(cursor() + 1)
            view.dirty = true
        } else {
            status("buffer full")
        }
    }

    sub start_insert() {
        mode = MODE_INSERT
        status("-- INSERT --")
    }

    ; R: typed characters replace the ones under the cursor
    sub key_mode_replace () {
        uword c = cursor()
        when key {
            KEY_ESCAPE -> leave_insert()
            KEY_RETURN -> insert_key(gapbuffer.eol)
            KEY_DEL -> {
                if c > gapbuffer.line_start(c)
                    set_cursor(c - 1)
            }
            KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN -> insert_move()
            else -> {
                if printable(key) {
                    if c < gapbuffer.line_end(c) {
                        void gapbuffer.set(c, key)
                        set_cursor(c + 1)
                        view.dirty = true
                    } else {
                        insert_key(key)
                    }
                }
            }
        }
    }

    ;
    ; nav mode commands
    ;

    ubyte pending_op        ; 'd', 'c' or 'y' waiting for a motion, or 0
    uword op_count          ; count typed before the operator
    ubyte pending_char      ; command waiting for a character: r f F t T Z, or 0
    uword char_count        ; count for the pending_char command
    bool count_given        ; a count was typed (G uses it as a line number)

    sub key_mode_nav () {
        uword count
        uword target

        if pending_char != 0 {
            char_arg()
            numbers = 0
            return
        }
        ; a count before a command, '0' on its own is a command
        if (key >= '1' and key <= '9') or (key == '0' and numbers != 0) {
            numbers = numbers * 10 + (key - '0')
            return
        }
        count_given = numbers != 0 or op_count > 1
        count = max(numbers, 1) * max(op_count, 1)
        numbers = 0

        if key == KEY_ESCAPE {
            handle_escape()
            return
        }
        if pending_op != 0 {
            operator_key(count)
            return
        }

        target = motion(key, count)
        if target != gapbuffer.NONE {
            set_cursor(target)
            when key {
                'j', 'k', KEY_UP, KEY_DOWN -> {}
                '$' -> goal_col = $ffff
                else -> goal_col = column()
            }
            return
        }

        when key {
            'i' -> start_insert()
            'a' -> {
                if cursor() < gapbuffer.line_end(cursor())
                    set_cursor(cursor() + 1)
                start_insert()
            }
            'I' -> {
                set_cursor(first_nonblank(cursor()))
                start_insert()
            }
            'A' -> {
                set_cursor(gapbuffer.line_end(cursor()))
                start_insert()
            }
            'o' -> open_line(true)
            'O' -> open_line(false)
            'x' -> {
                target = min(cursor() + count, gapbuffer.line_end(cursor()))
                apply_operator('d', cursor(), target, false)
            }
            'X' -> {
                target = gapbuffer.line_start(cursor())
                if cursor() - target > count
                    target = cursor() - count
                apply_operator('d', target, cursor(), false)
            }
            'D' -> apply_operator('d', cursor(), gapbuffer.line_end(cursor()), false)
            'C' -> apply_operator('c', cursor(), gapbuffer.line_end(cursor()), false)
            's' -> apply_operator('c', cursor(), min(cursor() + count, gapbuffer.line_end(cursor())), false)
            'S' -> lines_operator('c', count)
            'Y' -> lines_operator('y', count)
            'd', 'c', 'y' -> {
                pending_op = key
                op_count = count
            }
            'p' -> put(true, count)
            'P' -> put(false, count)
            'J' -> join_lines(max(count, 2) - 1)
            KEY_TILDE -> toggle_case(count)
            'R' -> {
                mode = MODE_REPLACE
                status("-- REPLACE --")
            }
            'r', 'f', 'F', 't', 'T', 'Z' -> {
                pending_char = key
                char_count = count
            }
            ':', '/', '?' -> start_cmdline(key)
            'u' -> status("no undo yet")
            KEY_CONTROL_F -> page(count * (page_lines() - 2), true)
            KEY_CONTROL_B -> page(count * (page_lines() - 2), false)
            KEY_CONTROL_D -> page(page_lines() / 2, true)
            KEY_CONTROL_U -> page(page_lines() / 2, false)
            KEY_CONTROL_L -> view.refresh(true)
            KEY_CONTROL_G -> show_info()
        }
    }

    ; the character after r f F t T Z
    sub char_arg() {
        ubyte cmd = pending_char
        uword target
        pending_char = 0
        if key == KEY_ESCAPE {
            handle_escape()
            return
        }
        when cmd {
            'r' -> replace_chars(key, char_count)
            'Z' -> {
                if key == 'Z' {
                    ; ZZ is :x, write if modified and quit
                    if not gapbuffer.modified or write_cmd("", false)
                        quit(true)
                } else if key == 'Q' {
                    quit(true)
                }
            }
            else -> {
                ; f F t T, as a motion or for a pending operator
                find_cmd = cmd
                find_char = key
                target = find_in_line(cmd, key, char_count)
                if target == gapbuffer.NONE {
                    pending_op = 0
                    op_count = 0
                    return
                }
                if pending_op != 0 {
                    finish_operator(target, cmd == 'f' or cmd == 't', false)
                } else {
                    set_cursor(target)
                    goal_col = column()
                }
            }
        }
    }

    ; the key after d, c or y
    sub operator_key(uword count) {
        ubyte op = pending_op
        uword target
        if key == op {
            ; dd, cc, yy
            pending_op = 0
            op_count = 0
            lines_operator(op, count)
            return
        }
        if key == 'f' or key == 'F' or key == 't' or key == 'T' {
            ; the motion needs a character first
            pending_char = key
            char_count = count
            return
        }
        ; cw is like ce
        if op == 'c' and (key == 'w' or key == 'W') and gapbuffer.get(cursor()) != ' '
            key = key - 'w' + 'e'
        op_active = true
        target = motion(key, count)
        op_active = false
        if target == gapbuffer.NONE {
            pending_op = 0
            op_count = 0
            return
        }
        finish_operator(target, motion_inclusive, motion_linewise)
    }

    ; apply the pending operator from the cursor to target
    sub finish_operator(uword target, bool inclusive, bool linewise) {
        ubyte op = pending_op
        uword start = cursor()
        uword end = target
        pending_op = 0
        op_count = 0
        if end < start {
            start = target
            end = cursor()
        } else if inclusive and end < gapbuffer.length() {
            end++
        }
        if linewise
            lines_range(op, start, end)
        else
            apply_operator(op, start, end, false)
    }

    ; dd, cc, yy with a count: count lines from the cursor line
    sub lines_operator(ubyte op, uword count) {
        uword end = cursor()
        repeat count - 1 {
            if gapbuffer.next_line(end) == gapbuffer.NONE
                break
            end = gapbuffer.next_line(end)
        }
        lines_range(op, cursor(), end)
    }

    ; apply op to the whole lines from the one containing first to the one containing last
    sub lines_range(ubyte op, uword first, uword last) {
        uword start = gapbuffer.line_start(first)
        uword end = gapbuffer.next_line(last)
        uword length = gapbuffer.length()
        if op == 'c' {
            ; cc keeps an empty line to type on
            apply_operator('c', start, gapbuffer.line_end(last), true)
            return
        }
        if end == gapbuffer.NONE {
            end = length
            ; deleting the last lines also removes the line ending before them
            if op == 'd' and start > 0 {
                void yank(start, end, true)
                start--
                set_cursor(start)
                void gapbuffer.delete_range(start, end)
                set_cursor(first_nonblank(gapbuffer.line_start(cursor())))
                view.dirty = true
                return
            }
        }
        apply_operator(op, start, end, true)
        if op == 'd'
            set_cursor(first_nonblank(cursor()))
    }

    ; yank, delete or change the text from start up to (not including) end
    sub apply_operator(ubyte op, uword start, uword end, bool linewise) {
        bool yanked = yank(start, end, linewise)
        if op == 'y' {
            if not linewise
                set_cursor(start)
            if not yanked
                status("too big to yank")
            return
        }
        set_cursor(start)
        void gapbuffer.delete_range(start, end)
        view.dirty = true
        if op == 'c' {
            start_insert()
        } else {
            ; the cursor stays on a character, not on the line ending
            set_cursor(min(cursor(), last_char(cursor())))
            if not yanked
                status("not yanked")
        }
    }

    ;
    ; yank buffer, kept at the top of memory above the gap buffer
    ;

    pointer yank_buf
    uword yank_size
    uword yank_len
    bool yank_lines         ; whole lines, put below / above the cursor line

    ; returns false if the text is too big for the yank buffer
    sub yank(uword start, uword end, bool linewise) -> bool {
        uword count = end - start
        if count > yank_size - 1
            return false
        yank_len = gapbuffer.copy_out(start, count, yank_buf)
        yank_lines = linewise
        ; whole lines always end with a line ending
        if linewise and (yank_len == 0 or yank_buf[yank_len - 1] != gapbuffer.eol) {
            yank_buf[yank_len] = gapbuffer.eol
            yank_len++
        }
        return true
    }

    ; p and P
    sub put(bool after, uword count) {
        uword c = cursor()
        uword position
        if yank_len == 0
            return
        if yank_lines {
            if after {
                position = gapbuffer.next_line(c)
                if position == gapbuffer.NONE {
                    ; below the last line: it needs a line ending first
                    position = gapbuffer.length()
                    set_cursor(position)
                    if position != 0 and gapbuffer.get(position - 1) != gapbuffer.eol {
                        void gapbuffer.insert_char(gapbuffer.eol, position)
                        position++
                    }
                }
            } else {
                position = gapbuffer.line_start(c)
            }
        } else {
            position = c
            if after and c < gapbuffer.line_end(c)
                position++
        }
        ; the cursor mark stays at the insertion point, so put it there first
        set_cursor(position)
        repeat count {
            if not gapbuffer.insert_bytes(yank_buf, yank_len, position) {
                status("buffer full")
                break
            }
        }
        view.dirty = true
        if yank_lines
            set_cursor(first_nonblank(position))
        else
            set_cursor(position + count * yank_len - 1)
    }

    ;
    ; other edits
    ;

    ; o and O
    sub open_line(bool below) {
        uword position
        if below {
            position = gapbuffer.line_end(cursor())
            set_cursor(position)
            if gapbuffer.insert_char(gapbuffer.eol, position)
                set_cursor(position + 1)
        } else {
            position = gapbuffer.line_start(cursor())
            set_cursor(position)
            ; the cursor mark stays at the start of the new empty line
            void gapbuffer.insert_char(gapbuffer.eol, position)
        }
        view.dirty = true
        start_insert()
    }

    ; J: join count lines onto the cursor line, with one space between
    sub join_lines(uword count) {
        uword end
        repeat count {
            end = gapbuffer.line_end(cursor())
            if end >= gapbuffer.length()
                break
            set_cursor(end)
            void gapbuffer.delete_char(end)
            while gapbuffer.get(end) == ' '
                void gapbuffer.delete_char(end)
            if end > gapbuffer.line_start(end) and end < gapbuffer.line_end(end)
                void gapbuffer.insert_char(' ', end)
        }
        view.dirty = true
    }

    ; r: replace count characters with char, r RETURN splits the line
    sub replace_chars(ubyte char, uword count) {
        uword c = cursor()
        uword i
        if gapbuffer.line_end(c) - c < count
            return
        if char == KEY_RETURN {
            void gapbuffer.delete_nchar(count, c)
            void gapbuffer.insert_char(gapbuffer.eol, c)
            set_cursor(c + 1)
        } else if printable(char) {
            for i in 0 to count - 1
                void gapbuffer.set(c + i, char)
            set_cursor(c + count - 1)
        }
        view.dirty = true
    }

    ; ~ (pi on CBM keyboards): switch the case of count characters and move past them
    sub toggle_case(uword count) {
        uword c = cursor()
        ubyte char
        repeat count {
            if c >= gapbuffer.line_end(c)
                break
            char = gapbuffer.get(c)
            if char >= $41 and char <= $5a
                char += $80
            else if char >= $c1 and char <= $da
                char -= $80
            else if char >= $61 and char <= $7a
                char -= $20
            void gapbuffer.set(c, char)
            c++
        }
        set_cursor(min(c, last_char(cursor())))
        goal_col = column()
        view.dirty = true
    }

    ;
    ; cursor movement, all in buffer offsets
    ;

    sub cursor() -> uword {
        return gapbuffer.get_mark(MARK_CURSOR)
    }

    ; move the cursor, keeping cur_line up to date by counting the line
    ; endings passed (so the cost is the distance moved)
    sub set_cursor(uword position) {
        uword old = cursor()
        gapbuffer.set_mark(MARK_CURSOR, position)
        position = cursor()
        if position > old
            cur_line += count_eols(old, position)
        else if position < old
            cur_line -= count_eols(position, old)
    }

    sub count_eols(uword start, uword end) -> uword {
        uword count = 0
        repeat {
            start = gapbuffer.find_next(gapbuffer.eol, start, end)
            if start >= end
                return count
            count++
            start++
        }
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

    ; goal_col in the line starting at start
    sub goal_in_line(uword start) -> uword {
        uword last = last_char(start)
        if op_active and mode != MODE_NAV
            last = gapbuffer.line_end(start)
        if goal_col > last - start
            return last
        return start + goal_col
    }

    sub first_nonblank(uword position) -> uword {
        position = gapbuffer.line_start(position)
        while gapbuffer.get(position) == ' '
            position++
        if position > gapbuffer.line_end(position)
            return gapbuffer.line_end(position)
        return position
    }

    ; go to line number line (1 = first), or the last line if there are fewer
    sub goto_line(uword line) {
        uword start = gapbuffer.NONE
        if line != 0
            start = gapbuffer.line_offset(line - 1)
        if start == gapbuffer.NONE
            start = gapbuffer.line_start(gapbuffer.length())
        set_cursor(first_nonblank(start))
        goal_col = column()
    }

    sub page_lines() -> uword {
        return MAX_ROW - MIN_ROW + 1
    }

    ; Ctrl-F, Ctrl-B, Ctrl-D, Ctrl-U: move lines lines down or up
    sub page(uword lines, bool down) {
        if down
            key = 'j'
        else
            key = 'k'
        set_cursor(motion(key, lines))
    }

    ;
    ; motions
    ;

    bool motion_linewise    ; set by motion(): the operator works on whole lines
    bool motion_inclusive   ; set by motion(): the target character is included
    bool op_active          ; motion() is for an operator: l and $ may reach the line end

    ; returns where the motion key goes, count times, from the cursor.
    ; returns NONE if key is not a motion (or a search found nothing).
    sub motion(ubyte k, uword count) -> uword {
        uword c = cursor()
        uword p
        uword limit
        motion_linewise = false
        motion_inclusive = false
        when k {
            'h', KEY_LEFT, KEY_DEL -> {
                limit = gapbuffer.line_start(c)
                repeat count {
                    if c > limit
                        c--
                }
            }
            'l', KEY_RIGHT, ' ' -> {
                limit = last_char(c)
                if op_active
                    limit = gapbuffer.line_end(c)
                repeat count {
                    if c < limit
                        c++
                }
            }
            '0', KEY_HOME -> c = gapbuffer.line_start(c)
            '^' -> c = first_nonblank(c)
            '$' -> {
                repeat count - 1 {
                    p = gapbuffer.next_line(c)
                    if p != gapbuffer.NONE
                        c = p
                }
                if op_active
                    c = gapbuffer.line_end(c)
                else
                    c = last_char(c)
            }
            'w', 'W' -> {
                big_words = k == 'W'
                limit = gapbuffer.line_end(c)
                repeat count
                    c = word_forward(c)
                ; dw on the last word of a line stops at the line end
                if op_active and c > limit and limit > cursor()
                    c = limit
                if not op_active and c >= gapbuffer.length()
                    c = last_char(c)
            }
            'b', 'B' -> {
                big_words = k == 'B'
                repeat count
                    c = word_back(c)
            }
            'e', 'E' -> {
                big_words = k == 'E'
                repeat count
                    c = word_end(c)
                motion_inclusive = true
            }
            'j', 'k', KEY_DOWN, KEY_UP, '+', '-', KEY_RETURN -> {
                motion_linewise = true
                repeat count {
                    if k == 'k' or k == KEY_UP or k == '-'
                        p = gapbuffer.prev_line(c)
                    else
                        p = gapbuffer.next_line(c)
                    if p == gapbuffer.NONE
                        break
                    c = p
                }
                if k == '+' or k == '-' or k == KEY_RETURN
                    c = first_nonblank(c)
                else if c != cursor()
                    c = goal_in_line(gapbuffer.line_start(c))
            }
            'G' -> {
                motion_linewise = true
                p = gapbuffer.NONE
                if count_given
                    p = gapbuffer.line_offset(count - 1)
                if p == gapbuffer.NONE
                    p = gapbuffer.line_start(gapbuffer.length())
                c = first_nonblank(p)
            }
            'H', 'M', 'L' -> {
                motion_linewise = true
                c = screen_row(k)
            }
            ';', ',' -> {
                if find_cmd == 0
                    return gapbuffer.NONE
                p = find_cmd
                if k == ','
                    p = reverse_find(find_cmd)
                c = find_in_line(p as ubyte, find_char, count)
                motion_inclusive = p == 'f' or p == 't'
            }
            'n' -> c = search_next(search_forward)
            'N' -> c = search_next(not search_forward)
            else -> return gapbuffer.NONE
        }
        return c
    }

    ; H M L: first non-blank of the top, middle or bottom screen row
    sub screen_row(ubyte k) -> uword {
        ubyte r = main.MIN_ROW
        ubyte last = main.MIN_ROW
        while last < main.MAX_ROW and view.row_start[last + 1] != gapbuffer.NONE
            last++
        when k {
            'M' -> r = (main.MIN_ROW + last) / 2
            'L' -> r = last
        }
        return first_nonblank(view.row_start[r])
    }

    ;
    ; words: letters, digits and _ form words, other non-blank characters
    ; form words of their own; for W B E any non-blank characters do.
    ; an empty line counts as a word.
    ;

    bool big_words

    sub char_class(ubyte char) -> ubyte {
        if char == ' ' or char == gapbuffer.eol or char == $a0
            return 0
        if big_words
            return 1
        if (char >= '0' and char <= '9') or char == '_' or (char >= $41 and char <= $5a) or
                (char >= $61 and char <= $7a) or (char >= $c1 and char <= $da)
            return 2
        return 1
    }

    sub empty_line_at(uword p) -> bool {
        return gapbuffer.get(p) == gapbuffer.eol and (p == 0 or gapbuffer.get(p - 1) == gapbuffer.eol)
    }

    ; w: start of the next word
    sub word_forward(uword p) -> uword {
        uword length = gapbuffer.length()
        ubyte class
        if p >= length
            return length
        class = char_class(gapbuffer.get(p))
        if class != 0 {
            while p < length and char_class(gapbuffer.get(p)) == class
                p++
        } else if empty_line_at(p) {
            p++
        }
        while p < length and char_class(gapbuffer.get(p)) == 0 {
            if empty_line_at(p)
                return p
            p++
        }
        return p
    }

    ; e: last character of this or the next word
    sub word_end(uword p) -> uword {
        uword length = gapbuffer.length()
        ubyte class
        if p + 1 >= length
            return p
        p++
        while p < length and char_class(gapbuffer.get(p)) == 0
            p++
        if p >= length
            return length - 1
        class = char_class(gapbuffer.get(p))
        while p + 1 < length and char_class(gapbuffer.get(p + 1)) == class
            p++
        return p
    }

    ; b: start of this or the previous word
    sub word_back(uword p) -> uword {
        ubyte class
        if p == 0
            return 0
        p--
        while p > 0 and char_class(gapbuffer.get(p)) == 0 {
            if empty_line_at(p)
                return p
            p--
        }
        class = char_class(gapbuffer.get(p))
        if class == 0
            return p
        while p > 0 and char_class(gapbuffer.get(p - 1)) == class
            p--
        return p
    }

    ;
    ; f F t T ; ,
    ;

    ubyte find_cmd          ; last f F t T, for ; and ,
    ubyte find_char

    sub reverse_find(ubyte cmd) -> ubyte {
        when cmd {
            'f' -> return 'F'
            'F' -> return 'f'
            't' -> return 'T'
        }
        return 't'
    }

    ; returns the target of f F t T in the cursor line, or NONE
    sub find_in_line(ubyte cmd, ubyte char, uword count) -> uword {
        uword c = cursor()
        uword p = c
        uword start = gapbuffer.line_start(c)
        uword end = gapbuffer.line_end(c)
        repeat count {
            if cmd == 'f' or cmd == 't' {
                ; t again right before the character must skip it
                if cmd == 't' and p == c and p + 1 < end and gapbuffer.get(p + 1) == char
                    p++
                p = gapbuffer.find_next(char, p + 1, end)
                if p >= end
                    return gapbuffer.NONE
            } else {
                if cmd == 'T' and p == c and p > start and gapbuffer.get(p - 1) == char
                    p--
                p = gapbuffer.find_prev(char, p)
                if p == gapbuffer.NONE or p < start
                    return gapbuffer.NONE
            }
        }
        if cmd == 't'
            p--
        else if cmd == 'T'
            p++
        return p
    }

    ;
    ; / ? n N
    ;

    str search_pat = " " * 40
    ubyte search_len
    bool search_forward = true

    sub search_cmd(bool forward) {
        uword target
        if cmdlen != 0 {
            void strings.copy(cmdline, search_pat)
            search_len = cmdlen
        }
        search_forward = forward
        if search_len == 0 {
            status("no pattern")
            return
        }
        target = search_next(forward)
        if target != gapbuffer.NONE {
            set_cursor(target)
            goal_col = column()
        }
    }

    ; returns the next match after (or before) the cursor, wrapping
    ; around the end of the text, or NONE
    sub search_next(bool forward) -> uword {
        uword c = cursor()
        uword p
        if search_len == 0
            return gapbuffer.NONE
        if forward {
            p = gapbuffer.find_bytes(search_pat, search_len, c + 1, gapbuffer.length())
            if p == gapbuffer.NONE
                p = gapbuffer.find_bytes(search_pat, search_len, 0, c + search_len)
        } else {
            p = gapbuffer.find_bytes_prev(search_pat, search_len, c)
            if p == gapbuffer.NONE
                p = gapbuffer.find_bytes_prev(search_pat, search_len, gapbuffer.length())
        }
        if p == gapbuffer.NONE
            status("not found")
        return p
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
        ; the yank buffer goes in the platform's spare memory if it fits,
        ; otherwise at the top of the text memory, with the gap buffer below it
        yank_size = 1024
        if platform.texttop - platform.textstart < 4096
            yank_size = 256
        if platform.sparetop - platform.sparestart >= yank_size {
            yank_buf = platform.sparestart
        } else {
            yank_buf = platform.texttop - yank_size
            platform.texttop = yank_buf
        }
        gapbuffer.init(platform.textstart, platform.texttop)
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
        pointer arg

        while cmdline[i] == ' '
            i++
        if cmdline[i] == 0
            return

        ; :n goes to line n
        if cmdline[i] >= '0' and cmdline[i] <= '9' {
            goto_line(max(conv.str2uword(&cmdline + i), 1))
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
