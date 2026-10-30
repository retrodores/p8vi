; self checking tests for a text store (the block "buffer"), runs on any
; target.  gaptest.p8 runs them on the gap buffer, pagetest.p8 on the page
; store.  main has CAPACITY (the room in the store), at(position) (moves
; the gap, or nothing) and check_store() (the store's own invariants).

buftests {
    str contents = "." * 64
    str linebuf = "." * 32
    ubyte failures

    sub run() {
        test_empty()
        test_insert()
        test_insert_middle()
        test_insert_start_end()
        test_delete()
        test_delete_nchar()
        test_full()
        test_loaded()
        test_set()
        test_marks()
        test_lines()
        test_copy()
        test_bytes()
        test_read_room()
        test_modified()
        test_find_bytes()
        test_undo()
        test_change_range()
    }

    sub report() {
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
        buffer.clear()
        expect("")
        check_uw("free", buffer.free(), main.CAPACITY)
        check_ub("get(0)", buffer.get(0), 0)
        check_bool("delete_char", buffer.delete_char(0), false)
    }

    sub test_insert() {
        txt.print("insert\n")
        buffer.clear()
        check_bool("insert", buffer.insert("hello", 0), true)
        check_bool("insert_char", buffer.insert_char(' ', 5), true)
        check_bool("insert", buffer.insert("world", buffer.length()), true)
        expect("hello world")
        check_uw("free", buffer.free(), main.CAPACITY - 11)
    }

    sub test_insert_middle() {
        ; gap must move left to reach the insertion point
        txt.print("insert middle\n")
        buffer.clear()
        void buffer.insert("hello world", 0)
        void buffer.insert("big ", 6)
        expect("hello big world")
        ; and right again, past the text that moved after the gap
        void buffer.insert_char('!', buffer.length())
        expect("hello big world!")
    }

    sub test_insert_start_end() {
        txt.print("insert start/end\n")
        buffer.clear()
        void buffer.insert("middle", 0)
        void buffer.insert("[", 0)
        void buffer.insert("]", buffer.length())
        void buffer.insert("<", 0)
        expect("<[middle]")
        ; positions past the end are clamped to the end
        void buffer.insert(">", 200)
        expect("<[middle]>")
    }

    sub test_delete() {
        txt.print("delete\n")
        buffer.clear()
        void buffer.insert("abcdef", 0)
        check_bool("first", buffer.delete_char(0), true)
        expect("bcdef")
        check_bool("last", buffer.delete_char(4), true)
        expect("bcde")
        check_bool("middle", buffer.delete_char(1), true)
        expect("bde")
        check_bool("past end", buffer.delete_char(3), false)
        expect("bde")
        check_uw("free", buffer.free(), main.CAPACITY - 3)
        ; delete everything
        repeat 3 {
            void buffer.delete_char(0)
        }
        expect("")
        check_uw("free", buffer.free(), main.CAPACITY)
    }

    sub test_delete_nchar() {
        txt.print("delete_nchar\n")
        buffer.clear()
        void buffer.insert("0123456789", 0)
        check_uw("count", buffer.delete_nchar(3, 2), 3)
        expect("0156789")
        ; count is clamped to the end of the text
        check_uw("clamped", buffer.delete_nchar(100, 4), 3)
        expect("0156")
        check_uw("past end", buffer.delete_nchar(1, 4), 0)
        expect("0156")
    }

    sub test_full() {
        txt.print("full\n")
        buffer.clear()
        ; 30 characters, 2 left
        void buffer.insert("abcdefghijklmnopqrstuvwxyz0123", 0)
        check_bool("too long", buffer.insert("XYZ", 5), false)
        expect("abcdefghijklmnopqrstuvwxyz0123")
        check_bool("char 1", buffer.insert_char('-', 5), true)
        check_bool("char 2", buffer.insert_char('-', 10), true)
        check_uw("free", buffer.free(), 0)
        check_bool("char 3", buffer.insert_char('-', 0), false)
        expect("abcde-fghi-jklmnopqrstuvwxyz0123")
        ; moving with no gap at all must keep the text intact
        main.at(2)
        main.at(20)
        expect("abcde-fghi-jklmnopqrstuvwxyz0123")
        ; deleting makes room again
        void buffer.delete_char(5)
        check_bool("after delete", buffer.insert_char('+', 0), true)
        expect("+abcdefghi-jklmnopqrstuvwxyz0123")
    }

    sub test_loaded() {
        txt.print("loaded\n")
        buffer.clear()
        ; a file load: read in with read_room() and read_done()
        read_in("line one\nline two", 0)
        check_bool("loaded", buffer.loaded(17), true)
        expect("line one\nline two")
        check_uw("free", buffer.free(), main.CAPACITY - 17)
        check_bool("modified", buffer.modified, false)
        void buffer.insert(" 1", 8)
        expect("line one 1\nline two")
        check_bool("too big", buffer.loaded(main.CAPACITY + 1), false)
    }

    ; insert s at position with read_room() and read_done(), as many
    ; pieces as that takes (like reading a file)
    sub read_in(str s, uword position) {
        pointer p
        uword room
        uword n = strings.length(s)
        uword count
        while n != 0 {
            p, room = buffer.read_room(position)
            if room == 0 {
                fail("no room")
                return
            }
            count = min(n, room)
            sys.memcopy(s, p, count)
            buffer.read_done(count)
            s += count
            position += count
            n -= count
        }
    }

    sub test_set() {
        txt.print("set\n")
        buffer.clear()
        void buffer.insert("abc", 0)
        main.at(1)
        check_bool("set", buffer.set(1, 'X'), true)
        check_bool("set end", buffer.set(3, 'X'), false)
        expect("aXc")
    }

    sub test_marks() {
        txt.print("marks\n")
        buffer.clear()
        void buffer.insert("hello world", 0)
        buffer.set_mark(0, 6)
        buffer.set_mark(1, 0)
        buffer.set_mark(2, 11)
        buffer.set_mark(3, 5)
        ; marks after the insertion point move, a mark at it stays
        void buffer.insert("big ", 6)
        expect("hello big world")
        check_marks(6, 0, 15, 5)
        ; marks inside a deleted range move to its start
        check_uw("deleted", buffer.delete_range(2, 8), 6)
        expect("heg world")
        check_marks(2, 0, 9, 2)
        buffer.set_mark(0, 500)
        check_uw("clamped", buffer.get_mark(0), 9)
        buffer.clear()
        check_marks(0, 0, 0, 0)
    }

    sub check_marks(uword m0, uword m1, uword m2, uword m3) {
        check_uw("mark 0", buffer.get_mark(0), m0)
        check_uw("mark 1", buffer.get_mark(1), m1)
        check_uw("mark 2", buffer.get_mark(2), m2)
        check_uw("mark 3", buffer.get_mark(3), m3)
    }

    sub test_lines() {
        ; offsets: one=0..2 eol=3 two=4..6 eol=7 eol=8 four=9..12 end=13
        txt.print("lines\n")
        buffer.eol = '\n'
        buffer.clear()
        void buffer.insert("one\ntwo\n\nfour", 0)
        ; the searches must give the same results wherever the gap is
        main.at(0)
        check_lines()
        main.at(6)
        check_lines()
        main.at(13)
        check_lines()
        buffer.eol = $0d
    }

    sub check_lines() {
        const uword NONE = buffer.NONE
        check_uw("find_next", buffer.find_next('o', 0, 13), 0)
        check_uw("find_next", buffer.find_next('o', 1, 13), 6)
        check_uw("find_next limit", buffer.find_next('o', 7, 10), 10)
        check_uw("find_next", buffer.find_next('o', 7, 13), 10)
        check_uw("find_prev", buffer.find_prev('o', 13), 10)
        check_uw("find_prev", buffer.find_prev('o', 6), 0)
        check_uw("find_prev none", buffer.find_prev('x', 13), NONE)
        check_uw("line_start", buffer.line_start(5), 4)
        check_uw("line_start eol", buffer.line_start(3), 0)
        check_uw("line_start empty", buffer.line_start(8), 8)
        check_uw("line_start end", buffer.line_start(13), 9)
        check_uw("line_end", buffer.line_end(0), 3)
        check_uw("line_end last", buffer.line_end(9), 13)
        check_uw("next_line", buffer.next_line(0), 4)
        check_uw("next_line", buffer.next_line(4), 8)
        check_uw("next_line empty", buffer.next_line(8), 9)
        check_uw("next_line last", buffer.next_line(9), NONE)
        check_uw("prev_line", buffer.prev_line(9), 8)
        check_uw("prev_line", buffer.prev_line(8), 4)
        check_uw("prev_line first", buffer.prev_line(2), NONE)
        check_uw("line_offset", buffer.line_offset(0), 0)
        check_uw("line_offset", buffer.line_offset(3), 9)
        check_uw("line_offset none", buffer.line_offset(4), NONE)
        check_uw("line_number", buffer.line_number(0), 0)
        check_uw("line_number", buffer.line_number(3), 0)
        check_uw("line_number", buffer.line_number(4), 1)
        check_uw("line_number", buffer.line_number(8), 2)
        check_uw("line_number", buffer.line_number(13), 3)
        expect("one\ntwo\n\nfour")
    }

    sub test_copy() {
        txt.print("copy\n")
        buffer.eol = '\n'
        buffer.clear()
        void buffer.insert("one\ntwo\n\nfour", 0)
        ; gap in the middle of "two" so copies have to cross it
        main.at(5)
        check_uw("copy_out", buffer.copy_out(2, 5, linebuf), 5)
        linebuf[5] = 0
        check_str("copy_out", linebuf, "e\ntwo")
        check_uw("copy_out end", buffer.copy_out(11, 5, linebuf), 2)
        check_uw("copy_line", buffer.copy_line(4, linebuf, 20), 3)
        check_str("copy_line", linebuf, "two")
        check_uw("copy_line wrap", buffer.copy_line(9, linebuf, 2), 2)
        check_str("copy_line wrap", linebuf, "fo")
        check_uw("copy_line empty", buffer.copy_line(8, linebuf, 20), 0)
        check_str("copy_line empty", linebuf, "")
        check_uw("copy_line end", buffer.copy_line(13, linebuf, 20), 0)
        buffer.eol = $0d
    }

    sub test_bytes() {
        txt.print("insert_bytes\n")
        ubyte[] data = [1, 0, 2]
        buffer.clear()
        void buffer.insert("ab", 0)
        check_bool("insert_bytes", buffer.insert_bytes(data, len(data), 1), true)
        check_uw("length", buffer.length(), 5)
        check_ub("byte 1", buffer.get(1), 1)
        check_ub("byte 2", buffer.get(2), 0)
        check_ub("byte 3", buffer.get(3), 2)
        check_bool("too big", buffer.insert_bytes(data, main.CAPACITY, 0), false)
        check_uw("delete_range", buffer.delete_range(1, 4), 3)
        expect("ab")
    }

    sub test_read_room() {
        txt.print("read_room\n")
        pointer p
        uword room
        buffer.clear()
        void buffer.insert("ad", 0)
        buffer.set_mark(0, 1)
        buffer.set_mark(1, 2)
        ; simulate reading data straight into the buffer
        p, room = buffer.read_room(1)
        check_bool("room", room >= 2, true)
        @(p) = 'b'
        @(p + 1) = 'c'
        buffer.read_done(2)
        expect("abcd")
        check_uw("mark at room", buffer.get_mark(0), 1)
        check_uw("mark after", buffer.get_mark(1), 4)
    }

    sub test_modified() {
        txt.print("modified\n")
        buffer.clear()
        check_bool("clear", buffer.modified, false)
        void buffer.insert("abc", 0)
        check_bool("insert", buffer.modified, true)
        buffer.modified = false
        main.at(1)
        void buffer.copy_out(0, 3, linebuf)
        check_bool("move and read", buffer.modified, false)
        void buffer.delete_nchar(1, 3)
        check_bool("delete past end", buffer.modified, false)
        void buffer.delete_char(0)
        check_bool("delete", buffer.modified, true)
        buffer.modified = false
        void buffer.set(0, 'x')
        check_bool("set", buffer.modified, true)
        void buffer.loaded(0)
        check_bool("loaded", buffer.modified, false)
        ; the change counter only moves on changes
        uword before = buffer.changes
        void buffer.insert("abc", 0)
        check_uw("insert counted", buffer.changes - before, 1)
        main.at(1)
        void buffer.copy_out(0, 3, linebuf)
        void buffer.delete_nchar(1, 3)
        check_uw("no change", buffer.changes - before, 1)
        void buffer.set(0, 'x')
        void buffer.delete_char(0)
        check_uw("set and delete", buffer.changes - before, 3)
    }

    sub test_find_bytes() {
        const uword NONE = buffer.NONE
        txt.print("find_bytes\n")
        buffer.clear()
        ; offsets: the=0 cat=4 the=8 hat=12 th=16 end=18
        void buffer.insert("the cat the hat th", 0)
        ; matches must be found across the gap too
        main.at(9)
        check_uw("first", buffer.find_bytes("the", 3, 0, 18), 0)
        check_uw("next", buffer.find_bytes("the", 3, 1, 18), 8)
        check_uw("across gap", buffer.find_bytes("e h", 3, 0, 18), 10)
        check_uw("limit", buffer.find_bytes("the", 3, 1, 10), NONE)
        check_uw("cut at end", buffer.find_bytes("the", 3, 9, 18), NONE)
        check_uw("missing", buffer.find_bytes("dog", 3, 0, 18), NONE)
        check_uw("prev", buffer.find_bytes_prev("the", 3, 18), 8)
        check_uw("prev again", buffer.find_bytes_prev("the", 3, 8), 0)
        check_uw("prev none", buffer.find_bytes_prev("the", 3, 0), NONE)
        check_uw("prev cut", buffer.find_bytes_prev("th ", 3, 18), NONE)
        check_bool("match", buffer.match_at("hat", 3, 12), true)
        check_bool("no match", buffer.match_at("hat", 3, 13), false)
        check_bool("past end", buffer.match_at("th!", 3, 16), false)
        expect("the cat the hat th")
    }

    sub test_undo() {
        const uword NONE = buffer.NONE
        txt.print("undo\n")
        buffer.undo_init(memory("undo", 64, 0), 64)
        buffer.clear()
        check_bool("empty", buffer.can_undo(), false)
        void buffer.insert("one two", 0)
        ; insert, undo, redo
        buffer.undo_mark()
        void buffer.insert(" three", 7)
        expect("one two three")
        check_uw("undo insert", buffer.undo(), 7)
        expect("one two")
        check_uw("redo insert", buffer.undo(), 7)
        expect("one two three")
        ; delete
        buffer.undo_mark()
        void buffer.delete_range(3, 7)
        expect("one three")
        check_uw("undo delete", buffer.undo(), 3)
        expect("one two three")
        ; several changes in one command, across the gap
        buffer.undo_mark()
        void buffer.delete_char(0)
        void buffer.set(0, 'N')
        void buffer.insert("!", 12)
        main.at(5)
        void buffer.insert("-", 5)
        expect("Ne tw-o three!")
        check_uw("undo several", buffer.undo(), 0)
        expect("one two three")
        check_uw("redo several", buffer.undo(), 0)
        expect("Ne tw-o three!")
        check_uw("undo again", buffer.undo(), 0)
        expect("one two three")
        ; typing extends one record, deleting typed text shrinks it
        buffer.undo_mark()
        void buffer.insert_char('a', 3)
        void buffer.insert_char('b', 4)
        void buffer.insert_char('c', 5)
        void buffer.delete_char(5)
        check_uw("one record", buffer.undo_len, 2 + 7)
        expect("oneab two three")
        check_uw("undo typing", buffer.undo(), 3)
        expect("one two three")
        ; moving the gap or the marks starts no new log
        buffer.undo_mark()
        main.at(0)
        check_bool("still there", buffer.can_undo(), true)
        ; a change too big for the log can't be undone (24 byte log here)
        buffer.undo_init(memory("undo", 64, 0), 24)
        buffer.undo_mark()
        void buffer.delete_range(0, 13)
        check_bool("small change", buffer.can_undo(), true)
        void buffer.insert("abcdefghij", 0)
        check_bool("too big", buffer.can_undo(), false)
        check_uw("no undo", buffer.undo(), NONE)
        expect("abcdefghij")
        ; a new log after it works again
        buffer.undo_mark()
        void buffer.delete_range(2, 10)
        expect("ab")
        check_uw("after lost", buffer.undo(), 2)
        expect("abcdefghij")
        ; loading empties the log
        void buffer.loaded(0)
        check_bool("loaded", buffer.can_undo(), false)
        buffer.undo_init(0, 0)
    }

    sub test_change_range() {
        const uword NONE = buffer.NONE
        txt.print("change range\n")
        buffer.clear()
        void buffer.insert("0123456789", 0)
        buffer.change_reset()
        check_uw("none", buffer.change_start, NONE)
        ; moving the gap or reading changes nothing
        main.at(3)
        void buffer.copy_out(0, 5, linebuf)
        check_uw("still none", buffer.change_start, NONE)
        ; an insert: the inserted text
        void buffer.insert("ab", 4)
        check_uw("insert start", buffer.change_start, 4)
        check_uw("insert end", buffer.change_end, 6)
        ; a later insert before it: start moves down, the end moves along
        void buffer.insert_char('x', 1)
        check_uw("before start", buffer.change_start, 1)
        check_uw("before end", buffer.change_end, 7)
        ; a delete after it: the end grows to the deletion point
        void buffer.delete_char(9)
        check_uw("after start", buffer.change_start, 1)
        check_uw("after end", buffer.change_end, 9)
        ; a delete overlapping the end: the end clamps to it
        void buffer.delete_nchar(3, 6)
        check_uw("overlap end", buffer.change_end, 6)
        ; set() covers one character
        buffer.change_reset()
        void buffer.set(2, 'S')
        check_uw("set start", buffer.change_start, 2)
        check_uw("set end", buffer.change_end, 3)
        ; loaded() marks everything changed
        void buffer.loaded(5)
        check_uw("loaded start", buffer.change_start, 0)
        check_uw("loaded end", buffer.change_end, 5)
    }

    ; compare the store's text and check the store
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
        main.check_store()
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
    sub read_contents() {
        ubyte i = 0
        while i as uword < buffer.length() {
            contents[i] = buffer.get(i)
            i++
        }
        contents[i] = 0
    }

    ; compare the buffer text and check the invariants
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
