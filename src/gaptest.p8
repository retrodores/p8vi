;
; self checking tests for the gap buffer, runs on any target: the shared
; text store tests (buftests.p8) and the gap's own.
; output is compared to tests/expected/virtual_gaptest.txt by make test-gap
;
%import strings
%import textio
%zeropage basicsafe
%option no_sysinit

%import gapbuffer
%import buftests

main {
    ; small buffer so the full buffer cases are easy to reach
    const ubyte CAPACITY = 32

    sub start() {
        buffer.init(sys.progend(), sys.progend() + CAPACITY)
        buffer.yank_buf = memory("yank", 32, 0)
        buffer.yank_size = 32
        buftests.run()
        test_gappos()
        test_move_gap()
        test_raw_load()
        test_chunks()
        buftests.report()
    }

    alias check_uw = buftests.check_uw
    alias check_ub = buftests.check_ub
    alias check_bool = buftests.check_bool
    alias expect = buftests.expect

    sub test_gappos() {
        txt.print("gappos\n")
        buffer.clear()
        void buffer.insert("hello", 0)
        void buffer.insert_char(' ', 5)
        void buffer.insert("world", buffer.gap_position())
        check_uw("insert", buffer.gap_position(), 11)
        void buffer.insert("big ", 6)
        check_uw("insert middle", buffer.gap_position(), 10)
        void buffer.delete_char(1)
        check_uw("delete", buffer.gap_position(), 1)
        at(4)
        void buffer.set(1, 'X')
        check_uw("set", buffer.gap_position(), 4)
        check_uw("free", buffer.free(), CAPACITY - 14)
    }

    sub test_move_gap() {
        txt.print("move_gap\n")
        buffer.clear()
        void buffer.insert("abcdefgh", 0)
        gap_to(3)
        expect("abcdefgh")
        check_uw("gappos", buffer.gap_position(), 3)
        gap_to(7)
        expect("abcdefgh")
        gap_to(0)
        expect("abcdefgh")
        gap_to(500)
        expect("abcdefgh")
        check_uw("clamped", buffer.gap_position(), 8)
    }


    sub test_raw_load() {
        txt.print("raw load\n")
        pointer p
        uword room
        buffer.clear()
        ; a file load straight into buffer memory (the gap is all of it)
        p, room = buffer.read_room(0)
        sys.memcopy("line one\nline two", p, 17)
        check_bool("loaded", buffer.loaded(17), true)
        expect("line one\nline two")
        check_uw("free", buffer.free(), CAPACITY - 17)
    }

    sub test_chunks() {
        txt.print("chunks\n")
        pointer p
        uword n
        buffer.clear()
        void buffer.insert("hello world", 0)
        gap_to(5)
        check_ub("chunks", buffer.chunks(), 2)
        p, n = buffer.chunk(0)
        check_uw("first", n, 5)
        check_ub("first char", @(p), 'h')
        p, n = buffer.chunk(1)
        check_uw("second", n, 6)
        check_ub("second char", @(p), ' ')
        gap_to(buffer.length())
        p, n = buffer.chunk(0)
        check_uw("whole", n, 11)
        p, n = buffer.chunk(1)
        check_uw("empty", n, 0)
    }


    ; move the gap and fill it with junk, so reading gap bytes by
    ; mistake can't accidentally return stale copies of the text
    sub at(uword position) {
        buffer.move_gap(position)
        scramble_gap()
    }

    sub gap_to(uword position) {
        at(position)
    }

    sub scramble_gap() {
        buffer.scramble_gap()
    }

    ; the gap buffer's invariants
    sub check_store() {
        if not buffer.check()
            buftests.fail("gap buffer invariants")
        scramble_gap()
    }
}
