;
; self checking tests for the gap buffer, runs on any target.
; output is compared to tests/expected/virtual_gaptest.txt by make test-gap
;
%import strings
%import textio
%zeropage basicsafe
%option no_sysinit

%import gapbuffer

main {
    ; small buffer so the full buffer cases are easy to reach
    const ubyte CAPACITY = 32

    str contents = "." * 64
    str linebuf = "." * 32
    ubyte failures

    sub start() {
        gapbuffer.init(sys.progend(), sys.progend() + CAPACITY)

        test_empty()
        test_insert()
        test_insert_middle()
        test_insert_start_end()
        test_delete()
        test_delete_nchar()
        test_move_gap()
        test_full()
        test_loaded()
        test_set()
        test_marks()
        test_lines()
        test_copy()
        test_bytes()
        test_segments()
        test_gap_ptr()
        test_modified()
        test_find_bytes()
        test_undo()
        test_change_range()

        txt.nl()
        if failures == 0 {
            txt.print("all tests passed\n")
        } else {
            txt.print_ub(failures)
            txt.print(" failures\n")
        }
    }

    sub test_empty() {
        txt.print("empty\n")
        gapbuffer.clear()
        expect("")
        check_uw("free", gapbuffer.free(), CAPACITY)
        check_ub("get(0)", gapbuffer.get(0), 0)
        check_bool("delete_char", gapbuffer.delete_char(0), false)
    }

    sub test_insert() {
        txt.print("insert\n")
        gapbuffer.clear()
        check_bool("insert", gapbuffer.insert("hello", 0), true)
        check_bool("insert_char", gapbuffer.insert_char(' ', 5), true)
        check_bool("insert", gapbuffer.insert("world", gapbuffer.gappos), true)
        expect("hello world")
        check_uw("gappos", gapbuffer.gappos, 11)
        check_uw("free", gapbuffer.free(), CAPACITY - 11)
    }

    sub test_insert_middle() {
        ; gap must move left to reach the insertion point
        txt.print("insert middle\n")
        gapbuffer.clear()
        void gapbuffer.insert("hello world", 0)
        void gapbuffer.insert("big ", 6)
        expect("hello big world")
        check_uw("gappos", gapbuffer.gappos, 10)
        ; and right again, past the text that moved after the gap
        void gapbuffer.insert_char('!', gapbuffer.length())
        expect("hello big world!")
    }

    sub test_insert_start_end() {
        txt.print("insert start/end\n")
        gapbuffer.clear()
        void gapbuffer.insert("middle", 0)
        void gapbuffer.insert("[", 0)
        void gapbuffer.insert("]", gapbuffer.length())
        void gapbuffer.insert("<", 0)
        expect("<[middle]")
        ; positions past the end are clamped to the end
        void gapbuffer.insert(">", 200)
        expect("<[middle]>")
    }

    sub test_delete() {
        txt.print("delete\n")
        gapbuffer.clear()
        void gapbuffer.insert("abcdef", 0)
        check_bool("first", gapbuffer.delete_char(0), true)
        expect("bcdef")
        check_bool("last", gapbuffer.delete_char(4), true)
        expect("bcde")
        check_bool("middle", gapbuffer.delete_char(1), true)
        expect("bde")
        check_uw("gappos", gapbuffer.gappos, 1)
        check_bool("past end", gapbuffer.delete_char(3), false)
        expect("bde")
        check_uw("free", gapbuffer.free(), CAPACITY - 3)
        ; delete everything
        repeat 3 {
            void gapbuffer.delete_char(0)
        }
        expect("")
        check_uw("free", gapbuffer.free(), CAPACITY)
    }

    sub test_delete_nchar() {
        txt.print("delete_nchar\n")
        gapbuffer.clear()
        void gapbuffer.insert("0123456789", 0)
        check_uw("count", gapbuffer.delete_nchar(3, 2), 3)
        expect("0156789")
        ; count is clamped to the end of the text
        check_uw("clamped", gapbuffer.delete_nchar(100, 4), 3)
        expect("0156")
        check_uw("past end", gapbuffer.delete_nchar(1, 4), 0)
        expect("0156")
    }

    sub test_move_gap() {
        txt.print("move_gap\n")
        gapbuffer.clear()
        void gapbuffer.insert("abcdefgh", 0)
        gap_to(3)
        expect("abcdefgh")
        check_uw("gappos", gapbuffer.gappos, 3)
        gap_to(7)
        expect("abcdefgh")
        gap_to(0)
        expect("abcdefgh")
        gap_to(500)
        expect("abcdefgh")
        check_uw("clamped", gapbuffer.gappos, 8)
    }

    sub test_full() {
        txt.print("full\n")
        gapbuffer.clear()
        ; 30 characters, 2 left
        void gapbuffer.insert("abcdefghijklmnopqrstuvwxyz0123", 0)
        check_bool("too long", gapbuffer.insert("XYZ", 5), false)
        expect("abcdefghijklmnopqrstuvwxyz0123")
        check_bool("char 1", gapbuffer.insert_char('-', 5), true)
        check_bool("char 2", gapbuffer.insert_char('-', 10), true)
        check_uw("free", gapbuffer.free(), 0)
        check_bool("char 3", gapbuffer.insert_char('-', 0), false)
        expect("abcde-fghi-jklmnopqrstuvwxyz0123")
        ; moving with no gap at all must keep the text intact
        gap_to(2)
        gap_to(20)
        expect("abcde-fghi-jklmnopqrstuvwxyz0123")
        ; deleting makes room again
        void gapbuffer.delete_char(5)
        check_bool("after delete", gapbuffer.insert_char('+', 0), true)
        expect("+abcdefghi-jklmnopqrstuvwxyz0123")
    }

    sub test_loaded() {
        txt.print("loaded\n")
        gapbuffer.clear()
        ; simulate a file load straight into buffer memory
        sys.memcopy("line one\nline two", gapbuffer.ramstart, 17)
        check_bool("loaded", gapbuffer.loaded(17), true)
        expect("line one\nline two")
        check_uw("free", gapbuffer.free(), CAPACITY - 17)
        void gapbuffer.insert(" 1", 8)
        expect("line one 1\nline two")
        check_bool("too big", gapbuffer.loaded(CAPACITY + 1), false)
    }

    sub test_set() {
        txt.print("set\n")
        gapbuffer.clear()
        void gapbuffer.insert("abc", 0)
        gap_to(1)
        check_bool("set", gapbuffer.set(1, 'X'), true)
        check_bool("set end", gapbuffer.set(3, 'X'), false)
        expect("aXc")
        check_uw("gappos", gapbuffer.gappos, 1)
    }

    sub test_marks() {
        txt.print("marks\n")
        gapbuffer.clear()
        void gapbuffer.insert("hello world", 0)
        gapbuffer.set_mark(0, 6)
        gapbuffer.set_mark(1, 0)
        gapbuffer.set_mark(2, 11)
        gapbuffer.set_mark(3, 5)
        ; marks after the insertion point move, a mark at it stays
        void gapbuffer.insert("big ", 6)
        expect("hello big world")
        check_marks(6, 0, 15, 5)
        ; marks inside a deleted range move to its start
        check_uw("deleted", gapbuffer.delete_range(2, 8), 6)
        expect("heg world")
        check_marks(2, 0, 9, 2)
        gapbuffer.set_mark(0, 500)
        check_uw("clamped", gapbuffer.get_mark(0), 9)
        gapbuffer.clear()
        check_marks(0, 0, 0, 0)
    }

    sub check_marks(uword m0, uword m1, uword m2, uword m3) {
        check_uw("mark 0", gapbuffer.get_mark(0), m0)
        check_uw("mark 1", gapbuffer.get_mark(1), m1)
        check_uw("mark 2", gapbuffer.get_mark(2), m2)
        check_uw("mark 3", gapbuffer.get_mark(3), m3)
    }

    sub test_lines() {
        ; offsets: one=0..2 eol=3 two=4..6 eol=7 eol=8 four=9..12 end=13
        txt.print("lines\n")
        gapbuffer.eol = '\n'
        gapbuffer.clear()
        void gapbuffer.insert("one\ntwo\n\nfour", 0)
        ; the searches must give the same results wherever the gap is
        gap_to(0)
        check_lines()
        gap_to(6)
        check_lines()
        gap_to(13)
        check_lines()
        gapbuffer.eol = $0d
    }

    sub check_lines() {
        const uword NONE = gapbuffer.NONE
        check_uw("find_next", gapbuffer.find_next('o', 0, 13), 0)
        check_uw("find_next", gapbuffer.find_next('o', 1, 13), 6)
        check_uw("find_next limit", gapbuffer.find_next('o', 7, 10), 10)
        check_uw("find_next", gapbuffer.find_next('o', 7, 13), 10)
        check_uw("find_prev", gapbuffer.find_prev('o', 13), 10)
        check_uw("find_prev", gapbuffer.find_prev('o', 6), 0)
        check_uw("find_prev none", gapbuffer.find_prev('x', 13), NONE)
        check_uw("line_start", gapbuffer.line_start(5), 4)
        check_uw("line_start eol", gapbuffer.line_start(3), 0)
        check_uw("line_start empty", gapbuffer.line_start(8), 8)
        check_uw("line_start end", gapbuffer.line_start(13), 9)
        check_uw("line_end", gapbuffer.line_end(0), 3)
        check_uw("line_end last", gapbuffer.line_end(9), 13)
        check_uw("next_line", gapbuffer.next_line(0), 4)
        check_uw("next_line", gapbuffer.next_line(4), 8)
        check_uw("next_line empty", gapbuffer.next_line(8), 9)
        check_uw("next_line last", gapbuffer.next_line(9), NONE)
        check_uw("prev_line", gapbuffer.prev_line(9), 8)
        check_uw("prev_line", gapbuffer.prev_line(8), 4)
        check_uw("prev_line first", gapbuffer.prev_line(2), NONE)
        check_uw("line_offset", gapbuffer.line_offset(0), 0)
        check_uw("line_offset", gapbuffer.line_offset(3), 9)
        check_uw("line_offset none", gapbuffer.line_offset(4), NONE)
        check_uw("line_number", gapbuffer.line_number(0), 0)
        check_uw("line_number", gapbuffer.line_number(3), 0)
        check_uw("line_number", gapbuffer.line_number(4), 1)
        check_uw("line_number", gapbuffer.line_number(8), 2)
        check_uw("line_number", gapbuffer.line_number(13), 3)
        expect("one\ntwo\n\nfour")
    }

    sub test_copy() {
        txt.print("copy\n")
        gapbuffer.eol = '\n'
        gapbuffer.clear()
        void gapbuffer.insert("one\ntwo\n\nfour", 0)
        ; gap in the middle of "two" so copies have to cross it
        gap_to(5)
        check_uw("copy_out", gapbuffer.copy_out(2, 5, linebuf), 5)
        linebuf[5] = 0
        check_str("copy_out", linebuf, "e\ntwo")
        check_uw("copy_out end", gapbuffer.copy_out(11, 5, linebuf), 2)
        check_uw("copy_line", gapbuffer.copy_line(4, linebuf, 20), 3)
        check_str("copy_line", linebuf, "two")
        check_uw("copy_line wrap", gapbuffer.copy_line(9, linebuf, 2), 2)
        check_str("copy_line wrap", linebuf, "fo")
        check_uw("copy_line empty", gapbuffer.copy_line(8, linebuf, 20), 0)
        check_str("copy_line empty", linebuf, "")
        check_uw("copy_line end", gapbuffer.copy_line(13, linebuf, 20), 0)
        gapbuffer.eol = $0d
    }

    sub test_bytes() {
        txt.print("insert_bytes\n")
        ubyte[] data = [1, 0, 2]
        gapbuffer.clear()
        void gapbuffer.insert("ab", 0)
        check_bool("insert_bytes", gapbuffer.insert_bytes(data, len(data), 1), true)
        check_uw("length", gapbuffer.length(), 5)
        check_ub("byte 1", gapbuffer.get(1), 1)
        check_ub("byte 2", gapbuffer.get(2), 0)
        check_ub("byte 3", gapbuffer.get(3), 2)
        check_bool("too big", gapbuffer.insert_bytes(data, CAPACITY, 0), false)
        check_uw("delete_range", gapbuffer.delete_range(1, 4), 3)
        expect("ab")
    }

    sub test_segments() {
        txt.print("segments\n")
        pointer p1
        pointer p2
        uword n1
        uword n2
        gapbuffer.clear()
        void gapbuffer.insert("hello world", 0)
        gap_to(5)
        p1, n1, p2, n2 = gapbuffer.segments()
        check_bool("start", p1 == gapbuffer.ramstart, true)
        check_uw("first", n1, 5)
        check_uw("second", n2, 6)
        check_ub("first char", @(p1), 'h')
        check_ub("second char", @(p2), ' ')
        gap_to(gapbuffer.length())
        p1, n1, p2, n2 = gapbuffer.segments()
        check_uw("whole", n1, 11)
        check_uw("empty", n2, 0)
    }

    sub test_gap_ptr() {
        txt.print("gap_ptr\n")
        pointer p
        gapbuffer.clear()
        void gapbuffer.insert("ad", 0)
        gapbuffer.set_mark(0, 1)
        gapbuffer.set_mark(1, 2)
        ; simulate reading data straight into the gap
        gap_to(1)
        p = gapbuffer.gap_ptr()
        @(p) = 'b'
        @(p + 1) = 'c'
        gapbuffer.inserted(2)
        expect("abcd")
        check_uw("mark at gap", gapbuffer.get_mark(0), 1)
        check_uw("mark after", gapbuffer.get_mark(1), 4)
    }

    sub test_modified() {
        txt.print("modified\n")
        gapbuffer.clear()
        check_bool("clear", gapbuffer.modified, false)
        void gapbuffer.insert("abc", 0)
        check_bool("insert", gapbuffer.modified, true)
        gapbuffer.modified = false
        gap_to(1)
        void gapbuffer.copy_out(0, 3, linebuf)
        check_bool("move and read", gapbuffer.modified, false)
        void gapbuffer.delete_nchar(1, 3)
        check_bool("delete past end", gapbuffer.modified, false)
        void gapbuffer.delete_char(0)
        check_bool("delete", gapbuffer.modified, true)
        gapbuffer.modified = false
        void gapbuffer.set(0, 'x')
        check_bool("set", gapbuffer.modified, true)
        void gapbuffer.loaded(0)
        check_bool("loaded", gapbuffer.modified, false)
        ; the change counter only moves on changes
        uword before = gapbuffer.changes
        void gapbuffer.insert("abc", 0)
        check_uw("insert counted", gapbuffer.changes - before, 1)
        gap_to(1)
        void gapbuffer.copy_out(0, 3, linebuf)
        void gapbuffer.delete_nchar(1, 3)
        check_uw("no change", gapbuffer.changes - before, 1)
        void gapbuffer.set(0, 'x')
        void gapbuffer.delete_char(0)
        check_uw("set and delete", gapbuffer.changes - before, 3)
    }

    sub test_find_bytes() {
        const uword NONE = gapbuffer.NONE
        txt.print("find_bytes\n")
        gapbuffer.clear()
        ; offsets: the=0 cat=4 the=8 hat=12 th=16 end=18
        void gapbuffer.insert("the cat the hat th", 0)
        ; matches must be found across the gap too
        gap_to(9)
        check_uw("first", gapbuffer.find_bytes("the", 3, 0, 18), 0)
        check_uw("next", gapbuffer.find_bytes("the", 3, 1, 18), 8)
        check_uw("across gap", gapbuffer.find_bytes("e h", 3, 0, 18), 10)
        check_uw("limit", gapbuffer.find_bytes("the", 3, 1, 10), NONE)
        check_uw("cut at end", gapbuffer.find_bytes("the", 3, 9, 18), NONE)
        check_uw("missing", gapbuffer.find_bytes("dog", 3, 0, 18), NONE)
        check_uw("prev", gapbuffer.find_bytes_prev("the", 3, 18), 8)
        check_uw("prev again", gapbuffer.find_bytes_prev("the", 3, 8), 0)
        check_uw("prev none", gapbuffer.find_bytes_prev("the", 3, 0), NONE)
        check_uw("prev cut", gapbuffer.find_bytes_prev("th ", 3, 18), NONE)
        check_bool("match", gapbuffer.match_at("hat", 3, 12), true)
        check_bool("no match", gapbuffer.match_at("hat", 3, 13), false)
        check_bool("past end", gapbuffer.match_at("th!", 3, 16), false)
        expect("the cat the hat th")
    }

    sub test_undo() {
        const uword NONE = gapbuffer.NONE
        txt.print("undo\n")
        gapbuffer.undo_init(memory("undo", 64, 0), 64)
        gapbuffer.clear()
        check_bool("empty", gapbuffer.can_undo(), false)
        void gapbuffer.insert("one two", 0)
        ; insert, undo, redo
        gapbuffer.undo_mark()
        void gapbuffer.insert(" three", 7)
        expect("one two three")
        check_uw("undo insert", gapbuffer.undo(), 7)
        expect("one two")
        check_uw("redo insert", gapbuffer.undo(), 7)
        expect("one two three")
        ; delete
        gapbuffer.undo_mark()
        void gapbuffer.delete_range(3, 7)
        expect("one three")
        check_uw("undo delete", gapbuffer.undo(), 3)
        expect("one two three")
        ; several changes in one command, across the gap
        gapbuffer.undo_mark()
        void gapbuffer.delete_char(0)
        void gapbuffer.set(0, 'N')
        void gapbuffer.insert("!", 12)
        gap_to(5)
        void gapbuffer.insert("-", 5)
        expect("Ne tw-o three!")
        check_uw("undo several", gapbuffer.undo(), 0)
        expect("one two three")
        check_uw("redo several", gapbuffer.undo(), 0)
        expect("Ne tw-o three!")
        check_uw("undo again", gapbuffer.undo(), 0)
        expect("one two three")
        ; typing extends one record, deleting typed text shrinks it
        gapbuffer.undo_mark()
        void gapbuffer.insert_char('a', 3)
        void gapbuffer.insert_char('b', 4)
        void gapbuffer.insert_char('c', 5)
        void gapbuffer.delete_char(5)
        check_uw("one record", gapbuffer.undo_len, 2 + 7)
        expect("oneab two three")
        check_uw("undo typing", gapbuffer.undo(), 3)
        expect("one two three")
        ; moving the gap or the marks starts no new log
        gapbuffer.undo_mark()
        gap_to(0)
        check_bool("still there", gapbuffer.can_undo(), true)
        ; a change too big for the log can't be undone (24 byte log here)
        gapbuffer.undo_init(memory("undo", 64, 0), 24)
        gapbuffer.undo_mark()
        void gapbuffer.delete_range(0, 13)
        check_bool("small change", gapbuffer.can_undo(), true)
        void gapbuffer.insert("abcdefghij", 0)
        check_bool("too big", gapbuffer.can_undo(), false)
        check_uw("no undo", gapbuffer.undo(), NONE)
        expect("abcdefghij")
        ; a new log after it works again
        gapbuffer.undo_mark()
        void gapbuffer.delete_range(2, 10)
        expect("ab")
        check_uw("after lost", gapbuffer.undo(), 2)
        expect("abcdefghij")
        ; loading empties the log
        void gapbuffer.loaded(0)
        check_bool("loaded", gapbuffer.can_undo(), false)
        gapbuffer.undo_init(0, 0)
    }

    sub test_change_range() {
        const uword NONE = gapbuffer.NONE
        txt.print("change range\n")
        gapbuffer.clear()
        void gapbuffer.insert("0123456789", 0)
        gapbuffer.change_reset()
        check_uw("none", gapbuffer.change_start, NONE)
        ; moving the gap or reading changes nothing
        gap_to(3)
        void gapbuffer.copy_out(0, 5, linebuf)
        check_uw("still none", gapbuffer.change_start, NONE)
        ; an insert: the inserted text
        void gapbuffer.insert("ab", 4)
        check_uw("insert start", gapbuffer.change_start, 4)
        check_uw("insert end", gapbuffer.change_end, 6)
        ; a later insert before it: start moves down, the end moves along
        void gapbuffer.insert_char('x', 1)
        check_uw("before start", gapbuffer.change_start, 1)
        check_uw("before end", gapbuffer.change_end, 7)
        ; a delete after it: the end grows to the deletion point
        void gapbuffer.delete_char(9)
        check_uw("after start", gapbuffer.change_start, 1)
        check_uw("after end", gapbuffer.change_end, 9)
        ; a delete overlapping the end: the end clamps to it
        void gapbuffer.delete_nchar(3, 6)
        check_uw("overlap end", gapbuffer.change_end, 6)
        ; set() covers one character
        gapbuffer.change_reset()
        void gapbuffer.set(2, 'S')
        check_uw("set start", gapbuffer.change_start, 2)
        check_uw("set end", gapbuffer.change_end, 3)
        ; loaded() marks everything changed
        void gapbuffer.loaded(5)
        check_uw("loaded start", gapbuffer.change_start, 0)
        check_uw("loaded end", gapbuffer.change_end, 5)
    }

    sub check_str(str name, str got, str wanted) {
        if strings.compare(got, wanted) != 0 {
            fail(name)
            txt.print("    wanted: '")
            txt.print(wanted)
            txt.print("' got: '")
            txt.print(got)
            txt.print("'\n")
        }
    }

    ; move the gap and fill it with junk, so reading gap bytes by
    ; mistake can't accidentally return stale copies of the text
    sub gap_to(uword position) {
        gapbuffer.move_gap(position)
        scramble_gap()
    }

    sub scramble_gap() {
        if gapbuffer.gapsize != 0
            sys.memset(gapbuffer.gapstart, gapbuffer.gapsize, '#')
    }

    ; copy the buffer text into contents using get()
    sub read_contents() {
        ubyte i = 0
        while i as uword < gapbuffer.length() {
            contents[i] = gapbuffer.get(i)
            i++
        }
        contents[i] = 0
    }

    ; compare the buffer text and check the invariants
    sub expect(str wanted) {
        read_contents()
        if strings.compare(contents, wanted) != 0 {
            fail("contents")
            txt.print("    wanted: '")
            txt.print(wanted)
            txt.print("'\n    got:    '")
            txt.print(contents)
            txt.print("'\n")
        }
        if gapbuffer.gapend != gapbuffer.gapstart + gapbuffer.gapsize - 1
            fail("gapend != gapstart + gapsize - 1")
        if gapbuffer.bufend + gapbuffer.gapsize != gapbuffer.ramtop - gapbuffer.ramstart
            fail("bufend + gapsize != capacity")
        if gapbuffer.gapstart - gapbuffer.ramstart != gapbuffer.gappos
            fail("gappos != gapstart")
        if gapbuffer.ramend() != gapbuffer.ramtop
            fail("ramend() != ramtop")
        scramble_gap()
    }

    sub check_uw(str name, uword got, uword wanted) {
        if got != wanted {
            fail(name)
            txt.print("    wanted: ")
            txt.print_uw(wanted)
            txt.print(" got: ")
            txt.print_uw(got)
            txt.nl()
        }
    }

    sub check_ub(str name, ubyte got, ubyte wanted) {
        check_uw(name, got, wanted)
    }

    sub check_bool(str name, bool got, bool wanted) {
        if got != wanted
            fail(name)
    }

    sub fail(str name) {
        failures++
        txt.print("  FAIL: ")
        txt.print(name)
        txt.nl()
    }
}
