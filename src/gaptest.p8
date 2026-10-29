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
