%import conv
%import strings
%import console_platform

;
; txt for p8vi under CP/M: a screen kept in memory and sent to the
; terminal when it changed, as no CP/M console can be read back and each
; terminal has its own codes.  It replaces the library's txt (the z80-cpm
; profile's is a stream with ANSI codes and no getchr).
;
; The program draws into `want` (setchr, chrout, plot ...).  flush() sends
; the rows that differ from `shown` (what the terminal has) and puts the
; terminal's cursor where show_cursor() asked; getkey() flushes first, so
; the screen is up to date whenever the program waits for a key.
;
; The terminal (select() from platform.init, the -T option):
;   ANSI   VT100 and later, xterm and the like: ESC [ row ; col H
;   VT52   ESC Y row+32 col+32 (tnylpo's full screen console)
;   ADM3A  ESC = row+32 col+32, clear screen ^Z, no clear to end of line
;          (the Lear Siegler ADM-3A, and many CP/M machines' consoles)
; The console is src/cpm/console_platform.p8's (BDOS function 6), or in
; the host build src/host/console_platform.p8's (the terminal).
;
txt {
    ; the largest screen (console.MAX_WIDTH x MAX_HEIGHT): the rows of want
    ; and shown are DEFAULT_WIDTH apart.  The screen used is columns x rows
    ; (80 x 24 to start; resize())
    const ubyte DEFAULT_WIDTH = console.MAX_WIDTH
    const ubyte DEFAULT_HEIGHT = console.MAX_HEIGHT
    const uword SIZE = (DEFAULT_WIDTH as uword) * DEFAULT_HEIGHT

    const ubyte ANSI = 0
    const ubyte VT52 = 1
    const ubyte ADM3A = 2
    ubyte term = ANSI

    ubyte[SIZE] want            ; the screen as the program drew it
    ubyte[SIZE] shown           ; the screen as the terminal shows it
    bool[DEFAULT_HEIGHT] dirty  ; rows of want that may differ from shown
    ubyte col                   ; where chrout writes
    ubyte row
    ubyte tcol = 255            ; the terminal's cursor (255: not known)
    ubyte trow = 255
    ubyte ccol                  ; where flush() leaves the cursor
    ubyte crow
    bool follow = true          ; or where chrout writes next (the : line)
    ubyte columns = 80          ; the screen's width (-40: 40)
    ubyte rows = 24             ; and height

    sub width() -> ubyte {
        return columns
    }

    sub height() -> ubyte {
        return rows
    }

    ; a new screen size, kept within MIN_ and DEFAULT_WIDTH x HEIGHT; the
    ; caller draws it all again
    const ubyte MIN_WIDTH = 20
    const ubyte MIN_HEIGHT = 4
    sub resize(ubyte c, ubyte r) {
        columns = clamp(c, MIN_WIDTH, DEFAULT_WIDTH)
        rows = clamp(r, MIN_HEIGHT, DEFAULT_HEIGHT)
    }

    ; the terminal by name ("ANSI", "VT52", "ADM3A", any case); false if
    ; there is no such one
    sub select(str name) -> bool {
        ubyte i = 0
        while name[i] != 0 {
            if name[i] >= 'a' and name[i] <= 'z'
                name[i] -= 32
            i++
        }
        if strings.compare(name, "ANSI") == 0
            term = ANSI
        else if strings.compare(name, "VT52") == 0
            term = VT52
        else if strings.compare(name, "ADM3A") == 0
            term = ADM3A
        else
            return false
        return true
    }

    sub out(ubyte char) {
        console.out(char)
    }

    sub out_str(str s) {
        while @(s) != 0 {
            out(@(s))
            s++
        }
    }

    sub out_dec(ubyte value) {
        if value >= 10
            out_dec(value / 10)
        out('0' + value % 10)
    }

    ; the terminal's cursor to a place
    sub term_goto(ubyte c, ubyte r) {
        if c == tcol and r == trow
            return
        when term {
            ANSI -> {
                out(27)
                out('[')
                out_dec(r + 1)
                out(';')
                out_dec(c + 1)
                out('H')
            }
            VT52 -> {
                out(27)
                out('Y')
                out(r + 32)
                out(c + 32)
            }
            else -> {
                out(27)
                out('=')
                out(r + 32)
                out(c + 32)
            }
        }
        tcol = c
        trow = r
    }

    sub term_clear() {
        when term {
            ANSI -> out_str("\x1b[H\x1b[2J")
            VT52 -> out_str("\x1bH\x1bJ")
            else -> out($1a)
        }
        tcol = 0
        trow = 0
    }

    ; clear from the cursor to the end of its row; false if the terminal
    ; can't
    sub term_clear_eol() -> bool {
        when term {
            ANSI -> out_str("\x1b[K")
            VT52 -> out_str("\x1bK")
            else -> return false
        }
        return true
    }

    ; send what changed, then the cursor to where show_cursor() put it
    sub flush() {
        ubyte r
        for r in 0 to rows - 1 {
            if dirty[r] {
                dirty[r] = false
                flush_row(r)
            }
        }
        if follow
            term_goto(col, row)
        else
            term_goto(ccol, crow)
    }

    sub flush_row(ubyte r) {
        uword base = (r as uword) * DEFAULT_WIDTH
        ubyte first = 0
        ubyte last = columns - 1
        ; (not the bottom right corner: writing there scrolls some terminals)
        if r == rows - 1
            last--
        while first <= last and want[base + first] == shown[base + first]
            first++
        if first > last
            return
        while want[base + last] == shown[base + last]
            last--
        ; the row's text ends before last: clear to the end of the row
        ; instead of writing spaces, if the terminal can
        ubyte end = columns - 1
        while end > first and want[base + end] == ' '
            end--
        bool clear = false
        if end + 4 < last and term != ADM3A
            clear = true
        else
            end = last
        term_goto(first, r)
        ubyte i
        ubyte c
        for i in first to end {
            c = want[base + i]
            out(c)
            shown[base + i] = c
            if i & 15 == 15
                poll_key()
        }
        tcol = end + 1
        if tcol >= columns
            tcol = 255
        if clear {
            void term_clear_eol()
            for i in end + 1 to columns - 1
                shown[base + i] = ' '
        }
    }

    ; where the cursor is shown when the program waits for a key
    sub show_cursor(ubyte c, ubyte r) {
        ccol = c
        crow = r
        follow = false
    }

    ; the cursor shown where chrout writes next
    sub follow_output() {
        follow = true
    }

    sub put(ubyte c, ubyte r, ubyte char) {
        if c >= columns or r >= rows
            return
        if char < ' ' or char >= $7f
            char = '.'
        uword i = (r as uword) * DEFAULT_WIDTH + c
        if want[i] != char {
            want[i] = char
            dirty[r] = true
        }
    }

    sub setchr(ubyte c, ubyte r, ubyte char) {
        put(c, r, char)
    }

    sub getchr(ubyte c, ubyte r) -> ubyte {
        return want[(r as uword) * DEFAULT_WIDTH + c]
    }

    sub plot(ubyte c, ubyte r) {
        col = c
        row = r
    }

    sub chrout(ubyte char) {
        if char == 13 or char == 10 {
            col = 0
            row++
            return
        }
        put(col, row, char)
        col++
    }

    sub print(str s) {
        while @(s) != 0 {
            chrout(@(s))
            s++
        }
    }

    sub print_uw(uword value) {
        print(conv.str_uw(value))
    }

    sub print_l(long value) {
        print(conv.str_l(value))
    }

    sub print_ub(ubyte value) {
        print(conv.str_ub(value))
    }

    sub spc() {
        chrout(' ')
    }

    sub nl() {
        chrout(13)
    }

    sub cls() {
        sys.memset(&want, SIZE, ' ')
        sys.memset(&shown, SIZE, ' ')
        sys.memset(&dirty, DEFAULT_HEIGHT, 0)
        term_clear()
        col = 0
        row = 0
    }

    ; send the whole screen again (Ctrl-L): the terminal is cleared and its
    ; copy forgotten, so the next flush() sends every row as want has it.
    ; (the editor's redraw alone only changes want)
    sub repaint() {
        term_clear()
        sys.memset(&shown, SIZE, ' ')
        sys.memset(&dirty, DEFAULT_HEIGHT, 1)
    }

    ; (the CBM machines' charset switch; nothing to do here)
    sub lowercase() {
    }

    ; keys typed while the screen is sent: a console without type-ahead
    ; (Montezuma's on the TRS-80 Model 4) loses a key that comes and goes
    ; while nobody asks for one, so flush() asks every 16 characters
    ubyte[16] keys
    ubyte key_head
    ubyte key_tail

    sub poll_key() {
        if (key_tail + 1) & 15 == key_head
            return
        ubyte k = console.poll()
        if k != 0 {
            keys[key_tail] = k
            key_tail = (key_tail + 1) & 15
        }
    }

    ; a key, 0 for none: one typed earlier, or else (after the screen is
    ; sent) the console's
    sub getkey() -> ubyte {
        if key_head == key_tail {
            flush()
            if key_head == key_tail
                return console.wait()
        }
        ubyte k = keys[key_head]
        key_head = (key_head + 1) & 15
        return k
    }

    ; the arrow and editing keys: after an Escape from getkey(), the key
    ; its escape sequence stands for, as the editor's code: ANSI's ESC [
    ; ... (from any terminal: vi has no ESC [ of its own), and with -T VT52
    ; ESC A to D.  0 for a sequence it doesn't know (dropped, or its
    ; letters would be taken as commands), 27 for a lone Escape (what came
    ; after it is kept for the next getkey).  (on the host the runtime's
    ; getkey gives the arrows' codes itself, ESC [ A and ESC O A alike: the
    ; rest comes here)
    ;   ESC [ A B C D      up, down, right, left
    ;   ESC [ H, ESC [ 1~ or 7~   Home (0)
    ;   ESC [ 5~, ESC [ 6~ Page Up, Page Down (Ctrl-B, Ctrl-F)
    sub escape_key() -> ubyte {
        ubyte k = next_key()
        if k == '[' {
            ubyte n = 0
            repeat {
                k = next_key()
                if k >= '0' and k <= '9'
                    n = n * 10 + k - '0'
                else if k != ';'
                    break
            }
            when k {
                'A' -> return main.KEY_UP
                'B' -> return main.KEY_DOWN
                'C' -> return main.KEY_RIGHT
                'D' -> return main.KEY_LEFT
                'H' -> return main.KEY_HOME
                '~' -> {
                    when n {
                        1, 7 -> return main.KEY_HOME
                        5 -> return main.KEY_CONTROL_B
                        6 -> return main.KEY_CONTROL_F
                    }
                }
            }
            return 0
        }
        if term == VT52 {
            when k {
                'A' -> return main.KEY_UP
                'B' -> return main.KEY_DOWN
                'C' -> return main.KEY_RIGHT
                'D' -> return main.KEY_LEFT
            }
        }
        if k != 0
            unget(k)
        return 27
    }

    ; (escape_key) the next key: a queued one, or the console's, asked a
    ; number of times (a sequence's bytes come one right after the other;
    ; the host's runtime gives an Escape on its own only when nothing
    ; follows it); 0 if none came
    const ubyte SEQ_TRIES = 255
    sub next_key() -> ubyte {
        ubyte k
        if key_head != key_tail {
            k = keys[key_head]
            key_head = (key_head + 1) & 15
            return k
        }
        repeat SEQ_TRIES {
            k = console.poll()
            if k != 0
                return k
        }
        return 0
    }

    ; a key typed ahead (the queue's first), or the console's if it has one;
    ; 0 for none (the host's size question: its answer may be queued
    ; already)
    sub poll_once() -> ubyte {
        ubyte k
        if key_head != key_tail {
            k = keys[key_head]
            key_head = (key_head + 1) & 15
            return k
        }
        return console.poll()
    }

    ; a key back in front of the queue
    sub unget(ubyte k) {
        if (key_head - 1) & 15 == key_tail
            return
        key_head = (key_head - 1) & 15
        keys[key_head] = k
    }

    sub waitkey() -> ubyte {
        ubyte k
        repeat {
            k = getkey()
            if k != 0
                return k
        }
    }

    ; before the program ends (the editor clears the screen next, which
    ; leaves the cursor at the top for the CCP)
    sub done() {
        flush()
    }
}
