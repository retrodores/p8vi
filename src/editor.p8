; p8vi, a vi for 8-bit computers: the editor.
; built from a toplevel file that sets the features block:
; src/p8vi.p8 (c64, cx16) or src/p8vi_vic20.p8 (the VIC-20, which leaves
; out what doesn't fit).

%import conv
%import diskio
%import strings
%import textio

%import store_platform
%import platform

main {
    const ubyte MODE_CMD        = 0     ; typing a ':' command or a '/' or '?' search
    const ubyte MODE_INSERT     = 1
    const ubyte MODE_NAV        = 2
    const ubyte MODE_REPLACE    = 4

    ; gap buffer marks used by the editor
    const ubyte MARK_CURSOR     = 0     ; buffer offset of the cursor
    const ubyte MARK_TOP        = 1     ; buffer offset of the top left of the screen
    const ubyte MARK_USER       = 2     ; (features.MARKS) vi's marks a-z: 2 to 27
    const ubyte MARK_JUMP       = 28    ; (features.MARKS) where the last jump came from: '' and ``
    const ubyte BUFFER_MARKS    = if features.MARKS 29 else 2   ; buffer.NUM_MARKS

    ; more keys
    const ubyte KEY_STOP        = $03   ; RUN/STOP, also works as escape
    const ubyte KEY_CONTROL_B   = 2
    const ubyte KEY_CONTROL_D   = 4
    const ubyte KEY_CONTROL_F   = 6
    const ubyte KEY_CONTROL_G   = 7
    const ubyte KEY_RETURN      = $0d
    const ubyte KEY_CONTROL_R   = $12
    const ubyte KEY_DOWN        = $11
    const ubyte KEY_HOME        = $13
    const ubyte KEY_DEL         = $14
    const ubyte KEY_CONTROL_U   = $15
    const ubyte KEY_CONTROL_W   = $17
    const ubyte KEY_RIGHT       = $1d
    const ubyte KEY_UP          = $91
    const ubyte KEY_LEFT        = $9d
    const ubyte KEY_TILDE       = $de   ; PETSCII has no ~, use pi (shift + up arrow)
    const ubyte KEY_BACKTICK    = $c0   ; PETSCII has no `, use shift + * (as the font build shows it)
    const ubyte KEY_UNDERSCORE  = $a4   ; _ as typed on a C64 (commodore + @), '_' is $e4
    ; the font build's | and _ (src/c64/font.p8)
    const ubyte KEY_FONT_PIPE       = $dc
    const ubyte KEY_FONT_UNDERSCORE = $5f   ; left arrow
    const ubyte KEY_SHIFT_POUND     = $a9   ; typed for | in the font build

    str filename = " " * 40     ; name of the file being edited, empty if none

    ; recovery after a crash (page store): the text is synced when no key
    ; came for SYNC_DELAY jiffies, with the file's settings in meta
    const ubyte SYNC_DELAY = 30
    uword key_time
    ubyte[buffer.META_SIZE] meta
    const ubyte META_ENDING = 41     ; (after the file name)
    const ubyte META_ASCII = 42
    const ubyte META_EOL = 43
    const ubyte META_FINAL_EOL = 44
    str cmdline = " " * 40      ; text typed after ':', '/' or '?'
    ubyte cmdlen
    ubyte cmd_prompt            ; ':', '/' or '?'
    bool cut_short              ; the file did not fit, so saving it over itself loses text
    bool ascii_file             ; the file is ASCII: translated to PETSCII when read, back when written
    ; (the font build) the font's ASCII characters are shown, and the keys
    ; type them.  on the MEGA65 the font follows ascii_file: a PETSCII file
    ; gets the C64's characters back (ascii_mode())
    bool font_ascii
    bool swap_full              ; (the disk build) "swap disk full" is shown
    ubyte line_ending           ; the file's ENDING_*; CRLF is CR in memory
    ; the file ends with a line ending.  like vi, the text doesn't keep it
    ; (it ends the last line, it doesn't start an empty one): reading takes
    ; it off, writing puts it back.  new texts have one.  (features.FINAL_EOL:
    ; without it the text keeps the line ending, and shows an empty last line)
    bool final_eol

    const ubyte ENDING_CR = 0
    const ubyte ENDING_LF = 1
    const ubyte ENDING_CRLF = 2

    ubyte mode
    ubyte key
    ubyte char_save
    uword numbers       ; count typed before a command
    bool cursor_active
    uword cur_line      ; line number of the cursor (zero relative)
    uword goal_col      ; column j and k try to keep

    sub start() {
        init()
        if buffer.PAGED and buffer.recoverable != 0
            status(":rec to recover")
        view.refresh(true)
        cursor_on()
        repeat {
            key = get_key()
            if features.CTRL_AT
                key = ctrl_at(key)
            if key == $00 {
                ; (page store) keep the text recoverable: when the keys stop
                if buffer.PAGED and buffer.changes != buffer.synced_changes and ticks() - key_time > SYNC_DELAY
                    sync_text()
                if platform.SWITCH and platform.switch_wanted()
                    switch_screen()
                draw_cursor()
                continue
            }
            if buffer.PAGED
                key_time = ticks()
            ; (the font build) shift + pound types | (the font's |, $dc)
            if features.FONT and font_ascii and key == KEY_SHIFT_POUND
                key = KEY_FONT_PIPE
            ; (the font build) the MEGA65 types { | } ~ as $7b-$7e (MEGA with
            ; : . ; ,), which show the same as $db-$de: the codes the font
            ; build keeps them as (charset.p8 swaps $7b-$7e with $db-$de)
            if features.FONT and font_ascii and key >= $7b and key <= $7e
                key += $60
            cursor_off()
            if key == KEY_STOP
                key = KEY_ESCAPE
            record_before()
            handle_key()
            record_after()
            ; (the disk build) a page couldn't be written: the disk is full,
            ; and the page is only in memory until the text is saved
            if buffer.CAN_FAIL {
                if buffer.failed {
                    status("swap disk full")
                    swap_full = true
                } else if swap_full {
                    ; there is room again
                    status("")
                    swap_full = false
                }
            }
            if repeat_requested
                replay()
            ; the start screen stays up while a ':' command is typed
            bool clear_splash = features.SPLASH and view.splash and mode != MODE_CMD
            if clear_splash
                view.splash = false
            view.refresh(clear_splash)
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

    ; (the C128) on the other screen: everything drawn again for its width
    sub switch_screen() {
        cursor_off()
        platform.switch_screen()
        ; the top row starts where a row starts at the new width
        buffer.set_mark(MARK_TOP, view.row_of(buffer.get_mark(MARK_TOP)))
        view.refresh(true)
        if mode == MODE_CMD {
            draw_cmdline()
            view.column = 1 + cmdlen
            if view.column > SCREEN_WIDTH - 2
                view.column = SCREEN_WIDTH - 2
            view.row = STATUS_LINE
        }
        cursor_on()
    }

    sub handle_key() {
        when mode {
            MODE_CMD -> key_mode_cmd()
            MODE_INSERT -> key_mode_insert()
            MODE_NAV -> key_mode_nav()
            MODE_REPLACE -> key_mode_insert()
        }
    }

    ;
    ; . repeats the last change by replaying its keys
    ;

    const ubyte REPEAT_SIZE = 128

    ; the keys of the command being typed (REPEAT_SIZE bytes, from take_memory)
    pointer rec_keys
    ubyte rec_len
    bool recording
    bool rec_overflow
    uword rec_count         ; count typed before the command, 0 if none
    uword rec_motion_count  ; count typed after an operator (d3w), 0 if none
    uword rec_changes       ; buffer.changes when the command started

    ; the last change, what . replays (REPEAT_SIZE bytes, from take_memory)
    pointer dot_keys
    ubyte dot_len
    uword dot_count         ; 0 if it had no count
    bool dot_valid
    bool dot_too_long

    bool replaying
    bool repeat_requested
    uword repeat_count      ; count typed before ., 0 if none

    ; a count digit in nav mode (a '0' on its own is a command)
    sub count_digit() -> bool {
        return (key >= '1' and key <= '9') or (key == '0' and numbers != 0)
    }

    sub record_before() {
        if replaying
            return
        if not recording {
            ; a new command starts with its first key after the count
            if mode != MODE_NAV or pending_op != 0 or pending_char != 0 or count_digit() or key == '.'
                return
            recording = true
            rec_len = 0
            rec_overflow = false
            rec_count = numbers
            rec_motion_count = 0
            rec_changes = buffer.changes
        } else if mode == MODE_NAV and pending_op != 0 and pending_char == 0 and count_digit() {
            ; the count between an operator and its motion goes into the
            ; command's count, so a count typed before . can replace it
            rec_motion_count = rec_motion_count * 10 + (key - '0')
            return
        } else if (mode == MODE_INSERT or mode == MODE_REPLACE) and
                (key == KEY_LEFT or key == KEY_RIGHT or key == KEY_UP or key == KEY_DOWN) {
            ; like vim, moving in insert mode starts the repeatable insert over
            rec_keys[0] = 'i'
            if mode == MODE_REPLACE
                rec_keys[0] = 'R'
            rec_len = 1
            rec_count = 0
            rec_motion_count = 0
            return
        }
        if rec_len == REPEAT_SIZE {
            rec_overflow = true
            return
        }
        rec_keys[rec_len] = key
        rec_len++
    }

    sub record_after() {
        ubyte first = rec_keys[0]
        if replaying or not recording
            return
        ; the command is complete when nav mode waits for a new one
        if mode != MODE_NAV or pending_op != 0 or pending_char != 0
            return
        recording = false
        ; only changes are repeated: not yanks, motions, :, u or Ctrl-R
        if buffer.changes == rec_changes or first == ':' or first == 'u' or first == KEY_CONTROL_R
            return
        dot_too_long = rec_overflow
        dot_valid = not rec_overflow
        if dot_valid {
            dot_len = rec_len
            sys.memcopy(rec_keys, dot_keys, rec_len)
            dot_count = 0
            if rec_count != 0 or rec_motion_count != 0
                dot_count = max(rec_count, 1) * max(rec_motion_count, 1)
        }
    }

    ; replay the last change, with the count typed before . if there was one
    sub replay() {
        ubyte i
        repeat_requested = false
        if not dot_valid {
            if dot_too_long
                status("too long (.)")
            else
                status("no repeat")
            return
        }
        replaying = true
        ; like vim, a count given to . is also used by the next .
        if repeat_count != 0
            dot_count = repeat_count
        numbers = dot_count
        for i in 0 to dot_len - 1 {
            key = dot_keys[i]
            handle_key()
        }
        replaying = false
    }

    ;
    ; cursor display
    ;

    ; (DOS_CURSOR, the TRS-80 Model 4: the DOS's own cursor, which it
    ; blinks.  it is off while the screen is drawn, which writes the video
    ; RAM directly: the DOS puts back the character under it when it goes
    ; off, and that must not undo a new one.)
    sub cursor_off() {
        if cursor_active {
            if DOS_CURSOR
                dos_cursor(false)
            else
                txt.setchr(view.column, view.row, char_save)
            cursor_active = false
        }
    }

    ; show the cursor on the character under it (in reverse on CBM)
    sub cursor_on() {
        if not cursor_active {
            if DOS_CURSOR {
                txt.plot(view.column, view.row)
                dos_cursor(true)
            } else {
                char_save = txt.getchr(view.column, view.row)
                txt.setchr(view.column, view.row, cursor_char(char_save))
            }
            cursor_active = true
        }
    }

    sub draw_cursor() {
        if DOS_CURSOR or not blink_timer() return
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

    ; insert mode, and replace mode (R), where typed characters replace
    ; the ones under the cursor
    sub key_mode_insert () {
        uword c = cursor()
        bool replace = mode == MODE_REPLACE
        when key {
            KEY_ESCAPE -> leave_insert()
            KEY_RETURN -> insert_key(buffer.eol)
            KEY_DEL -> {
                if replace {
                    ; replace mode just moves left
                    if c > cursor_line_start()
                        set_cursor(c - 1)
                } else if c > 0 {
                    ; the cursor mark moves back by itself, so fix the line here
                    if buffer.get(cursor() - 1) == buffer.eol
                        cur_line--
                    void buffer.delete_char(cursor() - 1)
                }
            }
            KEY_CONTROL_W -> {
                ; delete the word before the cursor, not past the line start
                big_words = false
                delete_back(max(word_back(cursor()), cursor_line_start()))
            }
            KEY_CONTROL_U -> {
                ; delete back to where this insert started, or the line start
                uword start = cursor_line_start()
                if insert_start > start and insert_start < cursor()
                    start = insert_start
                delete_back(start)
            }
            KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN -> insert_move()
            else -> {
                if printable(key) {
                    if replace and c < cursor_line_end() {
                        void buffer.set(c, key)
                        set_cursor(c + 1)
                    } else {
                        insert_key(key)
                    }
                }
            }
        }
        if insert_start > cursor()
            insert_start = cursor()
    }

    ; delete from start up to the cursor (in the cursor line)
    sub delete_back(uword start) {
        if start >= cursor()
            return
        ; the cursor mark moves back to start by itself
        void buffer.delete_range(start, cursor())
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
        ; typing goes on from here: a count no longer repeats it
        insert_start = cursor()
        insert_count = 1
    }

    ; like vi, leaving insert mode moves back onto the last character
    sub leave_insert() {
        mode = MODE_NAV
        status("")
        if insert_count > 1
            repeat_insert()
        if cursor() > cursor_line_start()
            set_cursor(cursor() - 1)
        goal_col = column()
    }

    sub printable(ubyte char) -> bool {
        return (char >= 32 and char < 128) or char >= 160
    }

    sub insert_key(ubyte char) {
        if buffer.insert_char(char, cursor()) {
            ; a mark at the insertion point stays, so move the cursor past it
            set_cursor(cursor() + 1)
        } else {
            status("buffer full")
        }
    }

    uword insert_start      ; where the current insert started
    uword insert_count      ; 3ifoo<Esc> inserts foo 3 times
    bool insert_lines       ; o and O: each repeat goes on a new line

    sub start_insert() {
        start_insert_n(1, false)
    }

    sub start_insert_n(uword count, bool lines) {
        mode = MODE_INSERT
        status("-- INSERT --")
        insert_start = cursor()
        insert_count = count
        insert_lines = lines
    }

    ; insert the text typed since insert_start insert_count - 1 more times
    ; (INSERT_SIZE bytes, from take_memory)
    const uword INSERT_SIZE = 128
    pointer insert_text
    sub repeat_insert() {
        uword length = cursor() - insert_start
        pointer text = insert_text + 1
        if cursor() <= insert_start or length > INSERT_SIZE - 1
            return
        void buffer.copy_out(insert_start, length, text)
        if insert_lines {
            ; o and O put each copy on a line of its own
            text--
            text[0] = buffer.eol
            length++
        }
        repeat insert_count - 1 {
            if not buffer.insert_bytes(text, length, cursor()) {
                status("buffer full")
                break
            }
            set_cursor(cursor() + length)
        }
    }

    ;
    ; nav mode commands
    ;

    ubyte pending_op        ; 'd', 'c' or 'y' waiting for a motion, or 0
    uword op_count          ; count typed before the operator
    ubyte pending_char      ; command waiting for a character: r f F t T Z g, or 0
    uword char_count        ; count for the pending_char command
    bool char_count_given
    bool count_given        ; a count was typed (G uses it as a line number)

    sub key_mode_nav () {
        uword count
        uword target

        if pending_char != 0 {
            char_arg()
            numbers = 0
            return
        }
        ; a new command: its changes are what u undoes
        if pending_op == 0
            buffer.undo_mark()
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

        if features.MARKS and (key == 'm' or key == '\'' or key == KEY_BACKTICK) {
            pending_char = key
            return
        }
        if features.Z_VIEW and key == 'z' {
            pending_char = key
            return
        }
        ; & repeats the last :s on the cursor line
        if features.REPEAT_SUBST and key == '&' {
            range_first = buffer.NONE
            subst_cmd("")
            return
        }
        target = motion(key, count)
        if target != buffer.NONE {
            if features.MARKS {
                when key {
                    'G', 'H', 'M', 'L', 'n', 'N', '*', '#', '%' -> set_jump()
                }
            }
            set_cursor(target)
            when key {
                'j', 'k', KEY_UP, KEY_DOWN -> {}
                '$' -> goal_col = $ffff
                else -> goal_col = column()
            }
            return
        }

        when key {
            'i' -> start_insert_n(count, false)
            'a' -> {
                if cursor() < cursor_line_end()
                    set_cursor(cursor() + 1)
                start_insert_n(count, false)
            }
            'I' -> {
                set_cursor(first_nonblank(cursor()))
                start_insert_n(count, false)
            }
            'A' -> {
                set_cursor(cursor_line_end())
                start_insert_n(count, false)
            }
            'o', 'O' -> open_line(key == 'o', count)
            'x' -> {
                target = min(cursor() + count, cursor_line_end())
                apply_operator('d', cursor(), target, false)
            }
            'X' -> {
                target = cursor_line_start()
                if cursor() - target > count
                    target = cursor() - count
                apply_operator('d', target, cursor(), false)
            }
            'D', 'C' -> apply_operator(if key == 'D' 'd' else 'c', cursor(), cursor_line_end(), false)
            's' -> apply_operator('c', cursor(), min(cursor() + count, cursor_line_end()), false)
            'S' -> lines_operator('c', count)
            'Y' -> lines_operator('y', count)
            'd', 'c', 'y', '>', '<' -> {
                pending_op = key
                op_count = count
            }
            'p', 'P' -> put(key == 'p', count)
            'J' -> join_lines(max(count, 2) - 1, true)
            KEY_TILDE -> toggle_case(count)
            'R' -> {
                mode = MODE_REPLACE
                status("-- REPLACE --")
            }
            'r', 'f', 'F', 't', 'T', 'Z', 'g' -> {
                pending_char = key
                char_count = count
                char_count_given = count_given
            }
            ':', '/', '?' -> start_cmdline(key)
            '.' -> {
                repeat_requested = true
                repeat_count = 0
                if count_given
                    repeat_count = count
            }
            'u' -> undo()
            KEY_CONTROL_R -> {
                ; redo: only when the last u undid something
                if buffer.undo_reversed
                    undo()
                else
                    status("no redo")
            }
            KEY_CONTROL_F, KEY_CONTROL_B -> page(count * (page_lines() - 2), key == KEY_CONTROL_F)
            KEY_CONTROL_D, KEY_CONTROL_U -> page(page_lines() / 2, key == KEY_CONTROL_D)
            KEY_CONTROL_L -> view.refresh(true)
            KEY_CONTROL_G -> show_info()
        }
    }

    ; u: undo the last change, or redo it if it was just undone
    sub undo() {
        uword position = buffer.undo()
        if position == buffer.NONE {
            if buffer.undo_lost
                status("undo too big")
            else
                status("no undo")
            return
        }
        ; the change can be anywhere, so find the line number from scratch
        buffer.set_mark(MARK_CURSOR, position)
        cur_line = buffer.line_number(cursor())
        ; (shared with the marks: a subroutine of its own only pays then)
        if features.MARKS
            cursor_on_char(cursor())
        else {
            set_cursor(min(cursor(), last_char(cursor())))
            goal_col = column()
        }
    }

    ; put the cursor at position, or on the last character of its line if
    ; position is the line's end, and keep its column for j and k
    ; (features.Z_VIEW) zt zz zb: the screen moves to show the cursor's row
    ; at the top, in the middle or at the bottom.  zt and zb leave it to
    ; view.refresh(): a top mark after the cursor puts its row at the top,
    ; one at the start (with the cursor further down than a screen) at the
    ; bottom.
    sub z_command() {
        uword top = 0
        when key {
            't' -> top = buffer.NONE
            'z' -> top = view.rows_up(view.row_of(cursor()), (MAX_ROW - MIN_ROW) / 2)
            'b' -> {}
            else -> return
        }
        buffer.set_mark(MARK_TOP, top)
    }

    sub cursor_on_char(uword position) {
        set_cursor(min(position, last_char(position)))
        goal_col = column()
    }

    ; the character after r f F t T Z g
    sub char_arg() {
        ubyte cmd = pending_char
        uword target
        pending_char = 0
        if key == KEY_ESCAPE {
            handle_escape()
            return
        }
        if features.MARKS and (cmd == 'm' or cmd == '\'' or cmd == KEY_BACKTICK) {
            mark_command(cmd)
            return
        }
        if features.Z_VIEW and cmd == 'z' {
            z_command()
            return
        }
        when cmd {
            'r' -> replace_chars(key, char_count)
            'g' -> g_command()
            'Z' -> {
                if key == 'Z' {
                    ; ZZ is :x, write if modified and quit
                    if not buffer.modified or write_cmd("", false)
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
                if target == buffer.NONE {
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

    ; gg ge gE gJ, as a motion or for a pending operator
    sub g_command() {
        uword target = cursor()
        bool linewise = false
        bool inclusive = false
        when key {
            'g' -> {
                ; gg goes to the first line, ngg to line n
                target = 0
                if char_count_given {
                    target = buffer.line_offset(char_count - 1)
                    if target == buffer.NONE
                        target = buffer.line_start(buffer.length())
                }
                target = first_nonblank(target)
                linewise = true
            }
            'e', 'E' -> {
                big_words = key == 'E'
                repeat char_count
                    target = word_end_back(target)
                inclusive = true
            }
            'J' -> {
                if pending_op == 0
                    join_lines(max(char_count, 2) - 1, false)
                return
            }
            else -> {
                pending_op = 0
                op_count = 0
                return
            }
        }
        if pending_op != 0 {
            finish_operator(target, inclusive, linewise)
        } else {
            if features.MARKS and key == 'g'
                set_jump()
            set_cursor(target)
            goal_col = column()
        }
    }

    ; (features.MARKS) the letter after m, ' or ` (KEY_BACKTICK: shift + *).
    ; ma sets mark a at the cursor; 'a goes to its line (linewise for an
    ; operator: d'a), `a to the mark itself (exclusive: d`a).  '' and ``
    ; go back to where the last jump came from (MARK_JUMP, the 27th: G gg
    ; H M L n N * # % / ? :n and going to a mark set it), so '' twice comes
    ; back.  the marks move along with the text, a :e or :rec clears them;
    ; a deleted mark's line is where the deletion was (vi forgets it).
    bool[if features.MARKS 27 else 1] mark_set
    sub mark_command(ubyte cmd) {
        uword target
        ubyte m = key - 'a'
        if key == '\'' or key == KEY_BACKTICK
            m = 26
        if m < 27 {
            if cmd == 'm' {
                buffer.set_mark(MARK_USER + m, cursor())
                mark_set[m] = true
                return
            }
            if mark_set[m] {
                target = buffer.get_mark(MARK_USER + m)
                if cmd == '\''
                    target = first_nonblank(target)
                if pending_op != 0 {
                    finish_operator(target, false, cmd == '\'')
                } else {
                    set_jump()
                    cursor_on_char(target)
                }
                return
            }
            status("mark not set")
        }
        pending_op = 0
        op_count = 0
    }

    ; (features.MARKS) a jump starts from here: '' comes back
    sub set_jump() {
        if features.MARKS {
            buffer.set_mark(MARK_JUMP, cursor())
            mark_set[len(mark_set) - 1] = true   ; (26: the index stays in bounds without MARKS too)
        }
    }

    ; the key after d, c, y, > or <
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
        if features.MARKS and (key == '\'' or key == KEY_BACKTICK) {
            ; d'a, d`a: the mark's letter first
            pending_char = key
            return
        }
        if key == 'f' or key == 'F' or key == 't' or key == 'T' or key == 'g' {
            ; the motion needs another key first
            pending_char = key
            char_count = count
            char_count_given = count_given
            return
        }
        ; cw is like ce
        if op == 'c' and (key == 'w' or key == 'W') and buffer.get(cursor()) != ' '
            key = key - 'w' + 'e'
        op_active = true
        target = motion(key, count)
        op_active = false
        if target == buffer.NONE {
            pending_op = 0
            op_count = 0
            return
        }
        finish_operator(target, motion_inclusive, motion_linewise)
    }

    ; apply the pending operator from the cursor to target
    sub finish_operator(uword target, bool inclusive, bool linewise) {
        ubyte op = pending_op
        if op == '>' or op == '<'
            linewise = true
        uword start = cursor()
        uword end = target
        pending_op = 0
        op_count = 0
        if end < start {
            start = target
            end = cursor()
        } else if inclusive and end < buffer.length() {
            end++
        }
        if linewise
            lines_range(op, start, end)
        else
            apply_operator(op, start, end, false)
    }

    ; dd, cc, yy with a count: count lines from the cursor line
    sub lines_operator(ubyte op, uword count) {
        lines_range(op, cursor(), lines_move(cursor(), count - 1, true))
    }

    ; apply op to the whole lines from the one containing first to the one containing last
    sub lines_range(ubyte op, uword first, uword last) {
        uword start = buffer.line_start(first)
        uword end = buffer.next_line(last)
        uword length = buffer.length()
        if op == '>' or op == '<' {
            shift_lines(start, count_eols(start, last) + 1, op == '>')
            return
        }
        if op == 'c' {
            ; cc keeps an empty line to type on
            apply_operator('c', start, buffer.line_end(last), true)
            return
        }
        if end == buffer.NONE {
            end = length
            ; deleting the last lines also removes the line ending before them
            if op == 'd' and start > 0 {
                void yank(start, end, true)
                start--
                set_cursor(start)
                void buffer.delete_range(start, end)
                set_cursor(first_nonblank(cursor_line_start()))
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
                status("yank too big")
            return
        }
        set_cursor(start)
        void buffer.delete_range(start, end)
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
    ; yanking (the text store keeps the yank buffer)
    ;

    bool yank_lines         ; whole lines, put below / above the cursor line

    ; returns false if the text is too big for the yank buffer.  (whole
    ; lines always end with a line ending)
    sub yank(uword start, uword end, bool linewise) -> bool {
        if not buffer.yank(start, end - start, linewise)
            return false
        yank_lines = linewise
        return true
    }

    ; end the text before position with a line ending, unless it has one
    ; (or position is 0).  returns true if it added one.
    sub add_eol_before(uword position) -> bool {
        if position == 0 or buffer.get(position - 1) == buffer.eol
            return false
        void buffer.insert_char(buffer.eol, position)
        return true
    }

    ; p and P
    sub put(bool after, uword count) {
        uword c = cursor()
        uword position
        bool added_eol = false
        if buffer.yank_len == 0
            return
        if yank_lines {
            if after {
                position = buffer.next_line(c)
                if position == buffer.NONE {
                    ; below the last line: it needs a line ending first
                    position = buffer.length()
                    set_cursor(position)
                    added_eol = add_eol_before(position)
                    if added_eol
                        position++
                }
            } else {
                position = buffer.line_start(c)
            }
        } else {
            position = c
            if after and c < buffer.line_end(c)
                position++
        }
        ; the cursor mark stays at the insertion point, so put it there first
        set_cursor(position)
        repeat count {
            if not buffer.put(position) {
                status("buffer full")
                break
            }
        }
        ; the text didn't end with a line ending before, so it shouldn't now
        if added_eol
            void buffer.delete_char(buffer.length() - 1)
        if yank_lines
            set_cursor(first_nonblank(position))
        else
            set_cursor(position + count * buffer.yank_len - 1)
    }

    ;
    ; other edits
    ;

    ; o and O
    sub open_line(bool below, uword count) {
        uword position
        if below {
            position = cursor_line_end()
            set_cursor(position)
            if buffer.insert_char(buffer.eol, position)
                set_cursor(position + 1)
        } else {
            position = cursor_line_start()
            set_cursor(position)
            ; the cursor mark stays at the start of the new empty line
            void buffer.insert_char(buffer.eol, position)
        }
        start_insert_n(count, true)
    }

    ; > and <: shift count lines from the one starting at start by SHIFT_WIDTH
    const ubyte SHIFT_WIDTH = 4
    sub shift_lines(uword start, uword count, bool right) {
        uword p = start
        ubyte n
        ; edits happen at and after the cursor, which keeps cur_line right
        set_cursor(start)
        repeat count {
            if right {
                ; empty lines stay empty
                if p < buffer.line_end(p)
                    void buffer.insert_bytes("        ", SHIFT_WIDTH, p)
            } else {
                n = 0
                while n < SHIFT_WIDTH and buffer.get(p) == ' ' {
                    void buffer.delete_char(p)
                    n++
                }
            }
            p = buffer.next_line(p)
            if p == buffer.NONE
                break
        }
        set_cursor(first_nonblank(start))
    }

    ; J: join count lines onto the cursor line, with one space between
    ; (gJ: as they are, without removing leading blanks or adding a space)
    sub join_lines(uword count, bool spaces) {
        uword end
        repeat count {
            end = cursor_line_end()
            if end >= buffer.length()
                break
            set_cursor(end)
            void buffer.delete_char(end)
            if spaces {
                while buffer.get(end) == ' '
                    void buffer.delete_char(end)
                if end > buffer.line_start(end) and end < buffer.line_end(end)
                    void buffer.insert_char(' ', end)
            }
        }
    }

    ; r: replace count characters with char, r RETURN splits the line
    sub replace_chars(ubyte char, uword count) {
        uword c = cursor()
        uword i
        if buffer.line_end(c) - c < count
            return
        if char == KEY_RETURN {
            void buffer.delete_nchar(count, c)
            void buffer.insert_char(buffer.eol, c)
            set_cursor(c + 1)
        } else if printable(char) {
            for i in 0 to count - 1
                void buffer.set(c + i, char)
            set_cursor(c + count - 1)
        }
    }

    ; ~ (pi on CBM keyboards): switch the case of count characters and move past them
    sub toggle_case(uword count) {
        uword c = cursor()
        ubyte char
        repeat count {
            if c >= buffer.line_end(c)
                break
            char = buffer.get(c)
            if char >= $41 and char <= $5a
                char += $80
            else if char >= $c1 and char <= $da
                char -= $80
            else if char >= $61 and char <= $7a
                char -= $20
            void buffer.set(c, char)
            c++
        }
        set_cursor(min(c, last_char(cursor())))
        goal_col = column()
    }

    ;
    ; cursor movement, all in buffer offsets
    ;

    sub cursor() -> uword {
        return buffer.get_mark(MARK_CURSOR)
    }

    sub cursor_line_start() -> uword {
        return buffer.line_start(cursor())
    }

    sub cursor_line_end() -> uword {
        return buffer.line_end(cursor())
    }

    ; move the cursor, keeping cur_line up to date by counting the line
    ; endings passed (so the cost is the distance moved).  the page store
    ; keeps a count per page, so its line_number() reads one page however
    ; far the cursor went (counting would read every page passed, from the
    ; disk in the disk builds)
    sub set_cursor(uword position) {
        uword old = cursor()
        buffer.set_mark(MARK_CURSOR, position)
        position = cursor()
        if buffer.PAGED
            cur_line = buffer.line_number(position)
        else if position > old
            cur_line += count_eols(old, position)
        else if position < old
            cur_line -= count_eols(position, old)
    }

    sub count_eols(uword start, uword end) -> uword {
        uword count = 0
        repeat {
            start = buffer.find_next(buffer.eol, start, end)
            if start >= end
                return count
            count++
            start++
        }
    }

    ; column of the cursor in its line
    sub column() -> uword {
        return cursor() - cursor_line_start()
    }

    ; offset of the last character of the line containing position
    ; (the line start for an empty line).  vi keeps the cursor on a
    ; character in nav mode, never on the line ending.
    sub last_char(uword position) -> uword {
        uword start = buffer.line_start(position)
        uword end = buffer.line_end(position)
        if end > start
            return end - 1
        return start
    }

    ; goal_col in the line starting at start
    sub goal_in_line(uword start) -> uword {
        uword last = last_char(start)
        if op_active and mode != MODE_NAV
            last = buffer.line_end(start)
        if goal_col > last - start
            return last
        return start + goal_col
    }

    sub first_nonblank(uword position) -> uword {
        position = buffer.line_start(position)
        while buffer.get(position) == ' '
            position++
        if position > buffer.line_end(position)
            return buffer.line_end(position)
        return position
    }

    ; go to line number line (1 = first), or the last line if there are fewer
    sub goto_line(uword line) {
        uword start = buffer.NONE
        if line != 0
            start = buffer.line_offset(line - 1)
        if start == buffer.NONE
            start = buffer.line_start(buffer.length())
        if features.MARKS
            set_jump()
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

    ; the last position l, $ and | go to: the last character of the line,
    ; or the line end for an operator
    sub line_limit(uword c) -> uword {
        if op_active
            return buffer.line_end(c)
        return last_char(c)
    }

    ; n lines down (or up) from c, as far as there are lines
    sub lines_move(uword c, uword n, bool down) -> uword {
        uword p
        repeat n {
            if down
                p = buffer.next_line(c)
            else
                p = buffer.prev_line(c)
            if p == buffer.NONE
                break
            c = p
        }
        return c
    }

    ; returns where the motion key goes, count times, from the cursor.
    ; returns NONE if key is not a motion (or a search found nothing).
    sub motion(ubyte k, uword count) -> uword {
        uword c = cursor()
        uword p
        uword limit
        motion_linewise = false
        motion_inclusive = false
        ; (the font build) the font's | and _ are the commands; '|' ($dd)
        ; is its }
        if features.FONT and font_ascii and k == '|'
            k = 0
        else if features.FONT and k == KEY_FONT_PIPE
            k = '|'
        else if features.FONT and k == KEY_FONT_UNDERSCORE
            k = '_'
        when k {
            'h', KEY_LEFT, KEY_DEL -> {
                limit = buffer.line_start(c)
                repeat count {
                    if c > limit
                        c--
                }
            }
            'l', KEY_RIGHT, ' ' -> {
                limit = line_limit(c)
                repeat count {
                    if c < limit
                        c++
                }
            }
            '0', KEY_HOME -> c = buffer.line_start(c)
            '^' -> c = first_nonblank(c)
            '$' -> c = line_limit(lines_move(c, count - 1, true))
            'w', 'W' -> {
                big_words = k == 'W'
                limit = buffer.line_end(c)
                repeat count
                    c = word_forward(c)
                ; dw on the last word of a line stops at the line end
                if op_active and c > limit and limit > cursor()
                    c = limit
                if not op_active and c >= buffer.length()
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
                c = lines_move(c, count, not (k == 'k' or k == KEY_UP or k == '-'))
                if k == '+' or k == '-' or k == KEY_RETURN
                    c = first_nonblank(c)
                else if c != cursor()
                    c = goal_in_line(buffer.line_start(c))
            }
            'G' -> {
                motion_linewise = true
                p = buffer.NONE
                if count_given
                    p = buffer.line_offset(count - 1)
                if p == buffer.NONE
                    p = buffer.line_start(buffer.length())
                c = first_nonblank(p)
            }
            'H', 'M', 'L' -> {
                motion_linewise = true
                c = screen_row(k)
            }
            ';', ',' -> {
                if find_cmd == 0
                    return buffer.NONE
                p = find_cmd
                if k == ','
                    p = reverse_find(find_cmd)
                c = find_in_line(p as ubyte, find_char, count)
                motion_inclusive = p == 'f' or p == 't'
            }
            'n' -> c = search_next(search_forward)
            'N' -> c = search_next(not search_forward)
            '*', '#' -> c = search_word(k == '*')
            '_', KEY_UNDERSCORE -> {
                motion_linewise = true
                c = first_nonblank(lines_move(c, count - 1, true))
            }
            '|' -> {
                ; column count (the first column is 1)
                p = buffer.line_start(c)
                limit = line_limit(c)
                c = p + count - 1
                if c > limit or c < p
                    c = limit
            }
            '%' -> {
                c = match_bracket(c)
                motion_inclusive = true
            }
            else -> return buffer.NONE
        }
        return c
    }

    ; H M L: first non-blank of the top, middle or bottom screen row
    sub screen_row(ubyte k) -> uword {
        ubyte r = main.MIN_ROW
        ubyte last = main.MIN_ROW
        while last < main.MAX_ROW and view.row_start[last + 1] != buffer.NONE
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
        if char == ' ' or char == buffer.eol or char == $a0
            return 0
        if big_words
            return 1
        if features.FONT and font_ascii and char == KEY_FONT_UNDERSCORE
            return 2
        if (char >= '0' and char <= '9') or char == '_' or (char >= $41 and char <= $5a) or
                (char >= $61 and char <= $7a) or (char >= $c1 and char <= $da)
            return 2
        return 1
    }

    sub empty_line_at(uword p) -> bool {
        return buffer.get(p) == buffer.eol and (p == 0 or buffer.get(p - 1) == buffer.eol)
    }

    ; w: start of the next word
    sub word_forward(uword p) -> uword {
        uword length = buffer.length()
        ubyte class
        if p >= length
            return length
        class = class_at(p)
        if class != 0
            p = skip_class(p, class)
        else if empty_line_at(p)
            p++
        while p < length and class_at(p) == 0 {
            if empty_line_at(p)
                return p
            p++
        }
        return p
    }

    ; e: last character of this or the next word
    sub word_end(uword p) -> uword {
        uword length = buffer.length()
        if p + 1 >= length
            return p
        p = skip_class(p + 1, 0)
        if p >= length
            return length - 1
        return skip_class(p, class_at(p)) - 1
    }

    ; ge: last character of the previous word
    sub word_end_back(uword p) -> uword {
        ubyte class = class_at(p)
        if p == 0
            return 0
        ; leave the word the cursor is on
        if class != 0 {
            p = skip_class_back(p, class)
            if p == 0
                return 0
            p--
        }
        while p > 0 and class_at(p) == 0 {
            if empty_line_at(p)
                return p
            p--
        }
        return p
    }

    sub class_at(uword p) -> ubyte {
        return char_class(buffer.get(p))
    }

    ; the position after the run of characters of class starting at p
    sub skip_class(uword p, ubyte class) -> uword {
        uword length = buffer.length()
        while p < length and class_at(p) == class
            p++
        return p
    }

    ; the start of the run of characters of class that ends at p
    sub skip_class_back(uword p, ubyte class) -> uword {
        while p > 0 and class_at(p - 1) == class
            p--
        return p
    }

    ; %: the bracket matching the first ( ) [ ] at or after p in its line,
    ; or NONE.  (PETSCII has no curly braces.)
    sub match_bracket(uword p) -> uword {
        uword end = buffer.line_end(p)
        uword depth = 1
        ubyte open
        ubyte close
        ubyte char
        bool forward
        while p < end {
            open = buffer.get(p)
            if open == '(' or open == ')' or open == '[' or open == ']'
                break
            p++
        }
        if p >= end
            return buffer.NONE
        when open {
            '(' -> close = ')'
            ')' -> close = '('
            '[' -> close = ']'
            else -> close = '['
        }
        forward = open == '(' or open == '['
        repeat {
            if forward {
                p++
                if p >= buffer.length()
                    return buffer.NONE
            } else {
                if p == 0
                    return buffer.NONE
                p--
            }
            char = buffer.get(p)
            if char == open
                depth++
            else if char == close {
                depth--
                if depth == 0
                    return p
            }
        }
    }

    ; b: start of this or the previous word
    sub word_back(uword p) -> uword {
        ubyte class
        if p == 0
            return 0
        p--
        while p > 0 and class_at(p) == 0 {
            if empty_line_at(p)
                return p
            p--
        }
        class = class_at(p)
        if class == 0
            return p
        return skip_class_back(p, class)
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
        uword start = buffer.line_start(c)
        uword end = buffer.line_end(c)
        bool forward = cmd == 'f' or cmd == 't'
        bool before = cmd == 't' or cmd == 'T'
        ; t (T) again right before (after) the character must skip it.
        ; (nothing comes before position 0, and stepping back from it would
        ; make find_prev() search from the end)
        if before {
            if forward
                p++
            else if p != 0
                p--
        }
        repeat count {
            if forward
                p = buffer.find_next(char, p + 1, end)
            else
                p = buffer.find_prev(char, p)
            if p >= end or p < start
                return buffer.NONE
        }
        if before {
            if forward
                p--
            else
                p++
        }
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
        if target != buffer.NONE {
            if features.MARKS
                set_jump()
            set_cursor(target)
            goal_col = column()
        }
    }

    ; * and #: search for the word under (or after) the cursor
    sub search_word(bool forward) -> uword {
        uword start = cursor()
        uword end = buffer.line_end(start)
        big_words = false
        while start < end and class_at(start) != 2
            start++
        if start >= end {
            status("no word")
            return buffer.NONE
        }
        ; the whole word: back to its start and on to its end
        start = skip_class_back(start, 2)
        end = start
        while class_at(end) == 2 and end - start < len(search_pat) - 1
            end++
        search_len = buffer.copy_out(start, end - start, search_pat) as ubyte
        search_pat[search_len] = 0
        search_forward = forward
        return search_from(start, forward)
    }

    ; returns the next match after (or before) the cursor, wrapping
    ; around the end of the text, or NONE
    sub search_next(bool forward) -> uword {
        return search_from(cursor(), forward)
    }

    sub search_from(uword c, bool forward) -> uword {
        uword p
        if search_len == 0
            return buffer.NONE
        if forward {
            p = buffer.find_bytes(search_pat, search_len, c + 1, buffer.length())
            if p == buffer.NONE
                p = buffer.find_bytes(search_pat, search_len, 0, c + search_len)
        } else {
            p = buffer.find_bytes_prev(search_pat, search_len, c)
            if p == buffer.NONE
                p = buffer.find_bytes_prev(search_pat, search_len, buffer.length())
        }
        if p == buffer.NONE
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
        uword lines = buffer.line_number(buffer.length()) + 1
        txt.plot(0, STATUS_LINE)
        txt.print_uw(lines)
        txt.print("L ")
        txt.print_uw(buffer.free())
        txt.chrout('F')
        status_pad(num_digits(lines) + 2 + num_digits(buffer.free()) + 1)
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
        ; the yank buffer, undo log and key buffers go in the platform's
        ; spare memory if they fit, otherwise at the top of the text memory,
        ; with the text below them.  (the page store keeps the yank buffer
        ; and undo log in its own pages, as big as there is room)
        buffer.undo_size = 2048
        buffer.yank_size = 1024
        ; (less than 8 KB: a VIC-20 without block 5, a PET)
        if platform.texttop - platform.textstart < 8192 {
            buffer.yank_size = 256
            buffer.undo_size = 512
        }
        if buffer.PAGED {
            buffer.yank_size = $ffff
            buffer.undo_size = $ffff
        } else {
            buffer.yank_buf = take_memory(buffer.yank_size)
            buffer.undo_buf = take_memory(buffer.undo_size)
        }
        if buffer.WRITE_BACK and features.ASCII
            save_buf = take_memory(SAVE_BUF_SIZE)
        rec_keys = take_memory(REPEAT_SIZE)
        dot_keys = take_memory(REPEAT_SIZE)
        insert_text = take_memory(INSERT_SIZE)
        if features.REPEAT_SUBST {
            last_subst = take_memory(len(cmdline))
            last_subst[0] = 0
        }
        buffer.init(platform.textstart, platform.texttop)
        mode = MODE_NAV
        txt.cls()
        filename[0] = 0
        new_text()
        ascii_mode()
        view.splash = features.SPLASH
    }

    ; (the font build) show the font for ascii_file's kind of text
    inline sub ascii_mode() {
        if features.FONT
            font_ascii = platform.font_mode(ascii_file)
    }

    ; returns size bytes of the platform's spare memory if there is room,
    ; otherwise takes them off the top of the text memory
    sub take_memory(uword size) -> pointer {
        if platform.sparetop - platform.sparestart >= size {
            platform.sparestart += size
            return platform.sparestart - size
        }
        platform.texttop -= size
        return platform.texttop
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
    ;   :set ascii, petscii, cr, lf, crlf   how the file is written (:set shows it)
    ;

    str cmdword = " " * 8

    sub is_cmd(str name) -> bool {
        return strings.compare(cmdword, name) == 0
    }

    sub execute() {
        ubyte i = 0
        ubyte n = 0
        bool force = false
        pointer arg

        while cmdline[i] == ' '
            i++
        if cmdline[i] == 0
            return

        ; a line range; on its own (":12", ":$", ":.") it goes to the line
        if features.SUBST and read_range(i) {
            i = cmd_pos
            if cmdline[i] == 0 {
                goto_line(range_last + 1)
                return
            }
        }

        ; :@ sends a command to the drive, :@$ shows the directory
        if features.DOS and cmdline[i] == '@' {
            dos_cmd(&cmdline + i + 1)
            return
        }

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

        if is_cmd("w")
            void write_cmd(arg, force)
        else if is_cmd("q")
            quit(force)
        else if is_cmd("wq") {
            if write_cmd(arg, force)
                quit(true)
        }
        else if is_cmd("x") {
            if not buffer.modified or write_cmd(arg, force)
                quit(true)
        }
        else if is_cmd("e")
            edit_cmd(arg, force)
        else if is_cmd("r")
            read_cmd(arg)
        else if is_cmd("se") or is_cmd("set")
            set_cmd(arg)
        else if features.SUBST and is_cmd("s")
            subst_cmd(arg)
        else if buffer.PAGED and (is_cmd("rec") or is_cmd("recover"))
            recover_cmd(force)
        else
            status("unknown cmd")
    }

    ; line ranges before a ':' command: "%" (all lines), or one or two line
    ; addresses "a,b".  an address is a line number, "." (the cursor line)
    ; or "$" (the last line).  range_first and range_last are line numbers
    ; from 0; range_first is NONE without a range.
    ubyte cmd_pos
    uword range_first
    uword range_last

    ; read a range at cmdline[start], cmd_pos ends up after it.
    ; returns false if there is none.
    sub read_range(ubyte start) -> bool {
        cmd_pos = start
        if cmdline[cmd_pos] == '%' {
            cmd_pos++
            range_first = 0
            range_last = buffer.line_number(buffer.length())
            return true
        }
        range_first = read_address()
        range_last = range_first
        if range_first == buffer.NONE
            return false
        if cmdline[cmd_pos] == ',' {
            cmd_pos++
            range_last = read_address()
            if range_last == buffer.NONE
                range_last = cur_line
        }
        return true
    }

    ; read a line address at cmdline[cmd_pos] and move cmd_pos past it.
    ; returns its line number from 0, or NONE if there is none.
    sub read_address() -> uword {
        ubyte c = cmdline[cmd_pos]
        uword line = buffer.NONE
        if c == '.'
            line = cur_line
        else if c == '$'
            line = buffer.line_number(buffer.length())
        else if c >= '0' and c <= '9' {
            line = conv.str2uword(&cmdline + cmd_pos)
            cmd_pos += str2uword_digits() - 1
            if line != 0
                line--
        } else
            return line
        cmd_pos++
        return line
    }

    ; :[range]s/old/new/[g] - replace old with new in the lines of the range
    ; (the cursor line without one): the first one in each line, or all of
    ; them with g.  old and new are plain text, and any character can take
    ; the place of the '/'.  An empty old is the last search.  :s on its own
    ; (and &) repeats the last one, without its g (features.REPEAT_SUBST).
    pointer last_subst      ; (features.REPEAT_SUBST) the last :s argument, without its flags
    sub subst_cmd(str arg) {
        ubyte @dirty delim
        ubyte old_len
        ubyte new_at
        ubyte new_len
        ubyte i
        pointer @dirty old
        bool all
        bool full = false
        uword line = range_first
        uword last = range_last
        uword lines = buffer.line_number(buffer.length())
        uword position
        uword end
        uword match
        uword found = buffer.NONE

        if features.REPEAT_SUBST {
            if arg[0] != 0
                void strings.copy(arg, last_subst)
            arg = last_subst
        }
        delim = arg[0]
        old = arg + 1
        if delim == 0 {
            status("no pattern")
            return
        }
        ; old is from arg[1] up to the next delimiter, then comes new, then
        ; the flag.  the delimiters at the ends can be left out.
        i = field_end(arg, 1, delim)
        old_len = i - 1
        if arg[i] != 0
            i++
        new_at = i
        i = field_end(arg, i, delim)
        new_len = i - new_at
        all = arg[i] != 0 and arg[i + 1] == 'g'
        if features.REPEAT_SUBST
            arg[i] = 0
        if old_len == 0 {
            old = search_pat
            old_len = search_len
            if old_len == 0 {
                status("no pattern")
                return
            }
        }
        if line == buffer.NONE {
            line = cur_line
            last = line
        }
        if last < line {
            position = line
            line = last
            last = position
        }
        if last > lines
            last = lines
        if line > last
            line = last

        position = buffer.line_offset(line)
        repeat {
            end = buffer.line_end(position)
            repeat {
                match = buffer.find_bytes(old, old_len, position, end)
                if match == buffer.NONE
                    break
                if buffer.free() + old_len < new_len {
                    full = true
                    last = line
                    break
                }
                void buffer.delete_nchar(old_len, match)
                void buffer.insert_bytes(arg + new_at, new_len, match)
                found = match
                position = match + new_len
                end = end + new_len - old_len
                if not all
                    break
            }
            if line == last
                break
            line++
            position = end + 1
        }

        if found != buffer.NONE {
            set_cursor(first_nonblank(buffer.line_start(found)))
            goal_col = column()
        }
        if full
            status("buffer full")
        else if found == buffer.NONE
            status("not found")
    }

    ; returns the index of the delimiter (or the 0 at the end) that ends
    ; the field of s starting at index i
    sub field_end(str s, ubyte i, ubyte delim) -> ubyte {
        while s[i] != 0 and s[i] != delim
            i++
        return i
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
            buffer.modified = false
            cut_short = false
        }
        return true
    }

    sub quit(bool force) {
        if buffer.modified and not force {
            status("unsaved (!)")
            return
        }
        ; nothing to recover after this
        if buffer.PAGED
            buffer.clean()
        if features.FONT or PLATFORM_STOP
            platform.stop()
        txt.cls()
        sys.exit(0)
    }

    ; :e - replace the text with another file
    sub edit_cmd(str arg, bool force) {
        pointer name = name_or_current(arg)
        if buffer.modified and not force {
            status("unsaved (!)")
            return
        }
        if name[0] == 0 {
            status("no file name")
            return
        }
        if load_file(name, false) {
            void strings.copy(name, filename)
            ; (the TRS-80) the drive the DOS found the file on goes into
            ; its name ("t/txt:1"), so :w puts it back there and not on the
            ; first drive the DOS can write to
            if DRIVE_SUFFIX {
                ubyte n = strings.length(filename)
                ubyte d = opened_drive()
                if d < 8 and (n < 2 or filename[n - 2] != ':') {
                    filename[n] = ':'
                    filename[n + 1] = '0' + d
                    filename[n + 2] = 0
                }
            }
        } else if disk_code == 62 and arg[0] != 0 {
            ; like vi, a file that does not exist yet starts out empty
            void strings.copy(name, filename)
            buffer.clear()
            new_text()
            cut_short = false
            ascii_file = false
            ascii_mode()
            line_ending = ENDING_CR
            status("new file")
        }
    }

    ; :set ascii / petscii / cr / lf / crlf - how the file is written;
    ; :set shows it
    str[] set_options = ["petscii", "ascii", "cr", "lf", "crlf"]

    sub set_cmd(str arg) {
        ubyte i = 0
        if arg[0] != 0 {
            ; (ascii and crlf only in a build with those features)
            while strings.compare(arg, set_options[i]) != 0 or
                    (i == 1 and not features.ASCII) or (i == 4 and not features.CRLF) {
                i++
                if i == len(set_options) {
                    status("bad option")
                    return
                }
            }
            if i >= 2 {
                set_line_ending(i - 2)
            } else {
                if ascii_file != (i == 1)
                    buffer.modified = true
                ascii_file = i == 1
                ascii_mode()
            }
        }
        void strings.copy(set_options[ascii_file as ubyte], status_text)
        void strings.append(status_text, " ")
        void strings.append(status_text, set_options[2 + line_ending])
        status(status_text)
    }

    ; change the line endings.  CR and LF swap in the text if the line end
    ; character changes, which undo can't undo.
    sub set_line_ending(ubyte ending) {
        ubyte eol = if ending == ENDING_LF $0a else $0d
        if ending != line_ending
            buffer.modified = true
        line_ending = ending
        if eol != buffer.eol {
            void translate_text(charset.SWAP_EOL)
            buffer.eol = eol
            buffer.undo_clear()
            cur_line = buffer.line_number(cursor())
            view.refresh(true)
        }
    }

    ; :r - insert a file below the cursor line
    sub read_cmd(str arg) {
        pointer name = name_or_current(arg)
        if name[0] == 0 {
            status("no file name")
            return
        }
        ; :r $ reads the directory
        if features.DIR and name[0] == '$' {
            dir_cmd(name, true)
            return
        }
        void load_file(name, true)
    }

    ;
    ; files
    ;

    ; read a file, replacing the text or inserting it below the cursor line.
    ; shows the result on the status line, returns false if it can't be opened
    ; (the text is not changed then).  The file's format is found from its
    ; bytes: a new or empty text takes it on, inserted text is converted to
    ; the line endings of the text around it.
    sub load_file(str name, bool insert) -> bool {
        uword size = 0
        uword position = 0
        bool cr_last = false
        ; (@dirty: these are always set before they are used, so they
        ; don't need clearing on every call)
        uword @dirty room
        uword @dirty n
        uword @dirty m
        uword @dirty start
        pointer @dirty p
        ubyte @dirty extra
        ubyte @dirty eol
        bool @dirty crlf
        bool @dirty ascii
        bool @dirty last_eol
        bool empty = buffer.length() == 0
        bool truncated = false

        if not file_exists(name) {
            status(status_text)
            return false
        }
        if not diskio.f_open(name) {
            disk_error()
            return false
        }
        if insert {
            position = buffer.next_line(cursor())
            if position == buffer.NONE {
                ; the cursor is on the last line: start a new line after it
                position = buffer.length()
                if add_eol_before(position)
                    position++
            }
        } else {
            buffer.clear()
            ; (page store) no undo log while reading: loaded() empties it
            ; anyway, and the page store's would hold all of the file
            if buffer.PAGED
                buffer.undo_off = true
        }
        start = position
        ; read the file into the room the store gives, a piece at a time
        ; (the gap buffer gives all its room at once).  the file's format
        ; comes from the first piece: CR LF pairs are held as CR.
        repeat {
            p, room = buffer.read_room(position)
            if buffer.PAGED and cr_last {
                ; a CR LF pair split between two pieces: drop the LF
                n = diskio.f_read(p, 1)
                if n == 1 and @(p) == $0a {
                    n = 0
                    size++
                }
                n += diskio.f_read(p + n, room - n)
            } else
                n = diskio.f_read(p, room)
            size += n
            m = n
            if features.CRLF and n != 0 {
                cr_last = buffer.PAGED and p[n - 1] == $0d
                m = charset.crlf_to_cr(p, n)
            }
            if not buffer.PAGED or position == start {
                crlf = m != n
                eol = file_eol(p, m)
                ascii = features.ASCII and charset.looks_ascii(p, m, eol == $0a)
                ; (page store, :e) the store counts the lines as they are
                ; read: with the file's line ending from the start, it
                ; doesn't count them all again afterwards
                if buffer.PAGED and not insert
                    buffer.eol = eol
            }
            if features.ASCII and ascii
                charset.translate(p, m, charset.TO_PETSCII)
            if insert and not empty and eol != buffer.eol
                charset.translate(p, m, charset.SWAP_EOL)
            buffer.read_done(m)
            position += m
            if not buffer.PAGED or n < room or room == 0
                break
        }
        ; the store is full: is there more in the file?
        if n == room and diskio.f_read(&extra, 1) == 1
            truncated = true
        diskio.f_close()
        if buffer.PAGED
            buffer.undo_off = false

        ; a line ending at the end of what was read ends its last line.
        ; (read into text, it is the text's line ending now)
        if features.FINAL_EOL and insert and not empty
            eol = buffer.eol
        last_eol = features.FINAL_EOL and position != start and buffer.get(position - 1) == eol
        if insert {
            ; like vi, whole lines: the file's last line must not join the
            ; line after it.  (start is the start of a line or the end of
            ; the text, so nothing read in means nothing to do here.)  at
            ; the end of the text, its line ending is taken off instead.
            if position < buffer.length()
                void add_eol_before(position)
            else if features.FINAL_EOL and last_eol
                void buffer.delete_char(position - 1)
            set_cursor(start)
            goal_col = 0
        } else {
            if features.FINAL_EOL and last_eol
                position--
            void buffer.loaded(position)
            new_text()
            cut_short = truncated
        }
        if not insert or empty {
            buffer.eol = eol
            final_eol = features.FINAL_EOL and last_eol
            ascii_file = ascii
            ascii_mode()
            line_ending = ENDING_CR
            if eol == $0a
                line_ending = ENDING_LF
            if crlf
                line_ending = ENDING_CRLF
        }
        if truncated
            status("too big, cut")
        else
            status_bytes(name, size)
        return true
    }

    ; the line end character of count bytes at p: LF when there are LFs
    ; but no CRs (files from other systems), otherwise CR
    sub file_eol(pointer p, uword count) -> ubyte {
        ubyte eol = $0d
        while count != 0 {
            if @(p) == $0d
                return $0d
            if @(p) == $0a
                eol = $0a
            p++
            count--
        }
        return eol
    }

    ; write the text's header for recovery, with the file's settings
    sub sync_text() {
        void strings.copy(filename, meta)
        meta[META_ENDING] = line_ending
        meta[META_ASCII] = ascii_file as ubyte
        meta[META_EOL] = buffer.eol
        meta[META_FINAL_EOL] = final_eol as ubyte
        buffer.sync(meta)
    }

    ; :recover - replace the text with the one left after a crash or a
    ; reset (the newest, if there are two)
    sub recover_cmd(bool force) {
        if buffer.modified and not force {
            status("unsaved (!)")
            return
        }
        if not buffer.recover(meta) {
            status("nothing to recover")
            return
        }
        new_text()
        void strings.copy(meta, filename)
        line_ending = meta[META_ENDING]
        ascii_file = meta[META_ASCII] != 0
        ascii_mode()
        buffer.eol = meta[META_EOL]
        final_eol = meta[META_FINAL_EOL] != 0
        cur_line = buffer.line_number(cursor())
        view.refresh(true)
        if buffer.recoverable != 0
            status("recovered, :rec for more")
        else
            status("recovered")
    }

    ; reset the editor for new text in the buffer
    sub new_text() {
        if features.MARKS {
            for cx16.r0L in 0 to len(mark_set) - 1
                mark_set[cx16.r0L] = false
        }
        buffer.eol = $0d
        final_eol = features.FINAL_EOL
        cur_line = 0
        goal_col = 0
    }

    ; for translate_text(): write the text to the open file
    const ubyte WRITE_TEXT = 255

    ; (page store with pages written back: buffer.WRITE_BACK) an ASCII text
    ; is translated for writing a piece at a time here, so its pages aren't
    ; changed: translating them in place and back would make each one be
    ; written back twice (to the disk in the disk build).  set up in init()
    const ubyte SAVE_BUF_SIZE = 64
    pointer save_buf

    ; translate the whole text, how is one of charset's modes, or write it
    ; to the open file (WRITE_TEXT; returns false if that fails).
    ; (buffer.WRITE_BACK) writing an ASCII text translates it on the way
    sub translate_text(ubyte how) -> bool {
        pointer p
        uword n
        uword k
        ubyte i
        for i in 0 to buffer.chunks() - 1 {
            ; (writing doesn't change the pages: not marked changed)
            if buffer.WRITE_BACK and how == WRITE_TEXT
                p, n = buffer.chunk_read(i)
            else
                p, n = buffer.chunk(i)
            if how == WRITE_TEXT {
                if buffer.WRITE_BACK and features.ASCII and ascii_file {
                    while n != 0 {
                        k = min(n, SAVE_BUF_SIZE)
                        sys.memcopy(p, save_buf, k)
                        charset.translate(save_buf, k, charset.TO_ASCII)
                        if not write_text(save_buf, k)
                            return false
                        p += k
                        n -= k
                    }
                } else if not write_text(p, n)
                    return false
            } else
                charset.translate(p, n, how)
        }
        return true
    }

    ubyte[1] lf_byte = [$0a]

    ; write count bytes at p, with CR LF for each CR in a CRLF file
    sub write_text(pointer p, uword count) -> bool {
        pointer end = p + count
        pointer start = p
        if features.CRLF and line_ending == ENDING_CRLF {
            while p != end {
                p++
                if @(p - 1) == $0d {
                    if not diskio.f_write(start, p - start) or not diskio.f_write(lf_byte, 1)
                        return false
                    start = p
                }
            }
        }
        return diskio.f_write(start, end - start)
    }

    ; the text is written to this file first, and the file it replaces is
    ; deleted only once that worked: a failed write (a full disk, a drive
    ; error, a reset) leaves the old file as it was
    str save_temp = "p8vi.tmp"
    ; (features.PREFIX) the temporary file's name with the saved file's
    ; drive or path prefix ("0:", "//dir/:"), or (DRIVE_SUFFIX) its drive
    ; suffix (":1"): the rename only works in the same place
    ubyte[40] temp_name

    ; how much of name is a drive or path prefix: up to and including its
    ; last ':', 0 for none (rfind gives 255 then)
    sub prefix_len(str name) -> ubyte {
        ubyte i
        i, void = strings.rfind(name, ':')
        return i + 1
    }

    ; write the whole text to a file, replacing it if it exists.
    ; returns false (and shows the drive status) if that fails.
    sub save_file(str name) -> bool {
        bool ok
        ; the temporary file goes where the file goes (features.PREFIX);
        ; straight into the file if that is the temporary name itself
        pointer target = save_temp
        if features.PREFIX {
            ubyte plen = prefix_len(name)
            target = &temp_name
            sys.memcopy(name, temp_name, plen)
            void strings.copy(save_temp, &temp_name + plen)
            if strings.compare(name + plen, save_temp) == 0
                target = name
        } else {
            if DRIVE_SUFFIX {
                ; (the TRS-80) the temporary file gets the name's drive spec
                ; (":1", always at the end): the rename only works on the
                ; same drive
                ubyte n = strings.length(name)
                target = &temp_name
                sys.memcopy(save_temp, target, len(save_temp) + 1)
                if n > 2 and name[n - 2] == ':' {
                    temp_name[len(save_temp)] = ':'
                    temp_name[len(save_temp) + 1] = name[n - 1]
                    temp_name[len(save_temp) + 2] = 0
                }
            }
            if strings.compare(name, target) == 0
                target = name
        }
        ; CBM DOS can't open an existing file for writing, so delete it first.
        ; (not with diskio.exists(): probing for a missing file with a read
        ; channel hangs the 1541 after a number of tries; deleting a file
        ; that isn't there is harmless)
        if features.PREFIX
            scratch(target)
        else
            diskio.delete(target)
        if not platform.open_write(target) {
            disk_error()
            return false
        }
        ; an ASCII file is translated for writing, and back afterwards.
        ; (buffer.WRITE_BACK: on the way, translate_text() does it)
        if features.ASCII and ascii_file and not buffer.WRITE_BACK
            void translate_text(charset.TO_ASCII)
        ok = translate_text(WRITE_TEXT)
        ; the line ending the text doesn't keep (see final_eol)
        if features.FINAL_EOL and ok and final_eol
            ok = write_text(&buffer.eol, 1)
        diskio.f_close_w()
        if features.ASCII and ascii_file and not buffer.WRITE_BACK
            void translate_text(charset.TO_PETSCII)
        ; (not diskio.status_code(): it only gets the first digit right,
        ; see bugs/side_effect_calls_merged.p8)
        read_disk_status()
        if not ok or disk_code != 0 {
            status(status_text)
            ; what was written is no good; the old file is still there
            if features.PREFIX
                scratch(target)
            else
                diskio.delete(target)
            return false
        }
        ; the text is safe on the disk: now the old file can go.  (the
        ; rename's old name is in the new name's place already)
        if target != name {
            if features.PREFIX {
                scratch(name)
                dos_command('r', name, save_temp)
            } else {
                diskio.delete(name)
                rename_file(target, name)
            }
            read_disk_status()
            if disk_code != 0 {
                status("saved as p8vi.tmp")
                return false
            }
        }
        status_bytes(name, buffer.length())
        return true
    }

    ; (features.CTRL_AT: the PET and the TRS-80 have no Ctrl key) @ in
    ; normal mode makes the next letter a Ctrl key: @ then g is Ctrl-G.
    ; another key after @ is just that key; in insert mode and on the
    ; command line @ is typed.
    bool ctrl_next
    sub ctrl_at(ubyte k) -> ubyte {
        if k == '@' and mode == MODE_NAV and not ctrl_next {
            ctrl_next = true
            return 0
        }
        if k != 0 and ctrl_next {
            ctrl_next = false
            if (k >= 'a' and k <= 'z') or (k >= 'A' and k <= 'Z')
                return k & 31
        }
        return k
    }

    ; show msg on the status line and wait for a key.
    ; returns false for Escape or RUN/STOP.
    sub wait_key(str msg) -> bool {
        ubyte k
        status(msg)
        do {
            k = get_key()
        } until k != 0
        return k != KEY_ESCAPE and k != KEY_STOP
    }
}

; Contains the View which is looking into a portion of the buffer.
; Maps the text rows of the screen (main.MIN_ROW..MAX_ROW, main.MIN_COL..MAX_COL)
; to buffer offsets.  Long lines wrap onto the next row.
; Works for any screen size up to txt.DEFAULT_WIDTH x txt.DEFAULT_HEIGHT.
view {
    const uword NONE = buffer.NONE

    bool splash     ; show the start screen, until the first command

    str[] splash_lines = [
        "Prog8 VI (p8vi)",
        "v0.3.1 20261110",
        "",
        "by Andrew Gillham",
        "and Claude Code",
        "",
        ":e name  edit a file",
        ":q       quit       "     ; as wide as the line above, to line up
    ]

    ubyte column    ; screen position of the cursor
    ubyte row

    ; buffer offset and length of the text on each screen row, NONE past the end
    uword[txt.DEFAULT_HEIGHT] row_start
    ubyte[txt.DEFAULT_HEIGHT] row_len
    ; the same for what is on the screen now, to redraw only rows that changed
    uword[txt.DEFAULT_HEIGHT] drawn_start
    ubyte[txt.DEFAULT_HEIGHT] drawn_len
    uword drawn_top = NONE
    uword drawn_length      ; buffer.length() when the screen was drawn

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
        ubyte k
        ; the screen is as drawn and the text didn't change: a cursor just
        ; off the screen moves it a few rows (the screen scrolls, the rows
        ; that come in are drawn)
        ; (features.SCROLL: without it the screen is drawn again)
        bool same = features.SCROLL and not force and buffer.change_start == NONE and drawn_top == buffer.get_mark(main.MARK_TOP)
        ; cursor above the screen: its row becomes the top row
        if cursor < buffer.get_mark(main.MARK_TOP)
            buffer.set_mark(main.MARK_TOP, row_of(cursor))
        ; work out the rows again only as far as needed: not at all when
        ; nothing changed and nothing scrolled (just moving the cursor)
        if force or buffer.get_mark(main.MARK_TOP) != drawn_top
            layout()
        else if buffer.change_start != NONE
            layout_changed()
        if not locate() {
            top = row_of(cursor)
            ; a few rows below the screen: the screen moves that many
            ; (MAX_SCROLL at most)
            prev = top
            if features.SCROLL and same {
                for k in 1 to MAX_SCROLL {
                    prev = prev_row(prev)
                    if prev == row_start[main.MAX_ROW] {
                        top = row_start[main.MIN_ROW + k]
                        break
                    }
                }
            }
            if prev != row_start[main.MAX_ROW] {
                ; cursor below the screen: its row becomes the bottom row
                ; (rows_up() is there for zz, features.Z_VIEW)
                if features.Z_VIEW
                    top = rows_up(top, main.MAX_ROW - main.MIN_ROW)
                else {
                    repeat main.MAX_ROW - main.MIN_ROW {
                        prev = prev_row(top)
                        if prev == NONE
                            break
                        top = prev
                    }
                }
            }
            buffer.set_mark(main.MARK_TOP, top)
            layout()
            void locate()
        }
        top = buffer.get_mark(main.MARK_TOP)
        if force or top != drawn_top {
            if features.SCROLL and same and scrolled(top)
                drawn()
            else {
                draw_all()
                if features.SPLASH and splash
                    draw_splash()
            }
        } else if buffer.change_start != NONE
            draw_changed()
        if main.mode != main.MODE_CMD
            main.status_position()
    }

    ; most rows the screen scrolls (further, it is drawn again)
    const ubyte MAX_SCROLL = 4

    ; the screen moved 1 to MAX_SCROLL rows from what is drawn (the text is
    ; the same): scroll it and draw the rows that came in.  returns false
    ; if it moved further.
    sub scrolled(uword top) -> bool {
        ubyte k
        ubyte r
        for k in 1 to MAX_SCROLL {
            if row_start[main.MIN_ROW + k] == drawn_top {
                ; down: rows came in at the top
                platform.scroll_rows(main.MIN_ROW, main.MAX_ROW, k, false)
                for r in main.MIN_ROW to main.MIN_ROW + k - 1
                    draw_row(r)
                return true
            }
            if top == drawn_start[main.MIN_ROW + k] {
                ; up: rows came in at the bottom
                platform.scroll_rows(main.MIN_ROW, main.MAX_ROW, k, true)
                for r in main.MAX_ROW - k + 1 to main.MAX_ROW
                    draw_row(r)
                return true
            }
        }
        return false
    }

    ; returns the start of the screen row (part of a wrapped line) containing position
    sub row_of(uword position) -> uword {
        uword start = buffer.line_start(position)
        uword offset = position - start
        uword rows = offset / width()
        ; at the end of a line that exactly fills its last row the
        ; cursor is shown after that row, not on an empty row below it
        if rows != 0 and offset == rows * width() and
                (position >= buffer.length() or buffer.get(position) == buffer.eol)
            rows--
        return start + rows * width()
    }

    ; returns the start of the screen row n rows above the one starting at
    ; start (as far as the text goes)
    sub rows_up(uword start, ubyte n) -> uword {
        uword prev
        repeat n {
            prev = prev_row(start)
            if prev == NONE
                break
            start = prev
        }
        return start
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
        layout_from(main.MIN_ROW, buffer.get_mark(main.MARK_TOP), false)
    }

    ; after a change (with the same top row): rows before the one the change
    ; starts in are the same, and once a row after the change starts where
    ; it did before, moved along with the change in length, the rest are the
    ; same too
    sub layout_changed() {
        ubyte first = main.MIN_ROW
        ubyte r
        for r in main.MIN_ROW to main.MAX_ROW {
            if drawn_start[r] == NONE or drawn_start[r] > buffer.change_start
                break
            first = r
        }
        if drawn_start[first] == NONE or drawn_start[first] > buffer.change_start
            layout()
        else
            layout_from(first, drawn_start[first], true)
    }

    sub layout_from(ubyte first, uword position, bool reuse) {
        uword length = buffer.length()
        uword moved = length - drawn_length
        uword limit
        uword end
        ubyte r
        ubyte rest
        for r in first to main.MAX_ROW {
            if reuse and position != NONE and position >= buffer.change_end and
                    drawn_start[r] != NONE and position == drawn_start[r] + moved {
                ; from here on the old rows, moved along
                for rest in r to main.MAX_ROW {
                    row_start[rest] = drawn_start[rest]
                    if row_start[rest] != NONE
                        row_start[rest] += moved
                    row_len[rest] = drawn_len[rest]
                }
                return
            }
            row_start[r] = position
            row_len[r] = 0
            if position == NONE
                continue
            if length - position < width()
                limit = length
            else
                limit = position + width()
            end = buffer.find_next(buffer.eol, position, limit)
            row_len[r] = (end - position) as ubyte
            if end < length {
                if buffer.get(end) == buffer.eol
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

    ; the start screen, centered over the empty rows
    sub draw_splash() {
        ubyte r = main.MIN_ROW + (main.MAX_ROW - main.MIN_ROW + 1 - len(splash_lines)) / 2
        ubyte i
        ubyte c
        uword line
        for i in 0 to len(splash_lines) - 1 {
            line = splash_lines[i]
            c = (main.SCREEN_WIDTH - strings.length(line)) / 2
            while @(line) != 0 {
                txt.setchr(c, r, main.screen_code(@(line)))
                c++
                line++
            }
            r++
        }
    }

    sub draw_all() {
        ubyte r
        for r in main.MIN_ROW to main.MAX_ROW
            draw_row(r)
        drawn()
    }

    ; redraw only the rows whose text may have changed since the last draw.
    ; a row is the same if it lies before the changed text, or after it and
    ; just moved along with the change in length, and starts on the same
    ; screen row with the same length.
    sub draw_changed() {
        uword start
        uword change_start = buffer.change_start
        uword change_end = buffer.change_end
        ; how far text after the change moved (wraps around for a shrink)
        uword moved = buffer.length() - drawn_length
        ubyte r
        for r in main.MIN_ROW to main.MAX_ROW {
            start = row_start[r]
            if start == NONE {
                if drawn_start[r] == NONE
                    continue
            } else if drawn_start[r] != NONE and row_len[r] == drawn_len[r] {
                ; (the line ending or wrap point right after the row counts too)
                if start + row_len[r] < change_start and drawn_start[r] == start
                    continue
                if start >= change_end and drawn_start[r] + moved == start
                    continue
            }
            draw_row(r)
        }
        drawn()
    }

    ; remember what is on the screen now
    sub drawn() {
        ubyte r
        for r in main.MIN_ROW to main.MAX_ROW {
            drawn_start[r] = row_start[r]
            drawn_len[r] = row_len[r]
        }
        drawn_top = buffer.get_mark(main.MARK_TOP)
        drawn_length = buffer.length()
        buffer.change_reset()
    }

    ; draw one text row straight into screen memory
    sub draw_row(ubyte r) {
        if features.FONT and main.font_ascii and row_start[r] == NONE {
            ; the font build has vi's ~ ($de in its font)
            platform.put_row(r, 0, "\xde", 1)
            return
        }
        if row_start[r] == NONE {
            ; rows past the end of the text show EMPTY_ROW (vi's ~)
            platform.put_row(r, 0, main.EMPTY_ROW, 1)
            return
        }
        void buffer.copy_out(row_start[r], row_len[r], linebuf)
        platform.put_row(r, main.MIN_COL, linebuf, row_len[r])
    }

    const ubyte SCREEN_SPACE = $20      ; screen code of a space

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
