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
    ubyte failures

    sub start() {
        gapbuffer.ramtop = sys.progend() + CAPACITY
        gapbuffer.init()

        test_empty()
        test_insert()
        test_insert_middle()
        test_insert_start_end()
        test_delete()
        test_delete_nchar()
        test_move_cursor()
        test_full()
        test_loaded()

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
        check_bool("insert", gapbuffer.insert("world", gapbuffer.point), true)
        expect("hello world")
        check_uw("point", gapbuffer.point, 11)
        check_uw("free", gapbuffer.free(), CAPACITY - 11)
    }

    sub test_insert_middle() {
        ; gap must move left to reach the insertion point
        txt.print("insert middle\n")
        gapbuffer.clear()
        void gapbuffer.insert("hello world", 0)
        void gapbuffer.insert("big ", 6)
        expect("hello big world")
        check_uw("point", gapbuffer.point, 10)
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
        check_uw("point", gapbuffer.point, 1)
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

    sub test_move_cursor() {
        txt.print("move_cursor\n")
        gapbuffer.clear()
        void gapbuffer.insert("abcdefgh", 0)
        gapbuffer.move_cursor(3)
        expect("abcdefgh")
        check_uw("point", gapbuffer.point, 3)
        gapbuffer.move_cursor(7)
        expect("abcdefgh")
        gapbuffer.move_cursor(0)
        expect("abcdefgh")
        gapbuffer.move_cursor(500)
        expect("abcdefgh")
        check_uw("clamped", gapbuffer.point, 8)
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
        gapbuffer.move_cursor(2)
        gapbuffer.move_cursor(20)
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
        if gapbuffer.gapstart - gapbuffer.ramstart != gapbuffer.point
            fail("point != gapstart")
        if gapbuffer.ramend() != gapbuffer.ramtop
            fail("ramend() != ramtop")
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
