;
; self checking tests for the page store, runs on any target: the shared
; text store tests (buftests.p8) and the page store's own, with 8 byte
; pages so the text spreads over several.
; output is compared to tests/expected/virtual_pagetest.txt by make test-gap
;
%import strings
%import textio
%zeropage basicsafe
%option no_sysinit

%import pagestore
%import buftests

main {
    ; 4 pages of 8 bytes
    const ubyte PAGE = 8
    const ubyte CAPACITY = 32

    str big = "." * 80

    sub start() {
        buffer.page_size = PAGE
        buffer.init(sys.progend(), sys.progend() + CAPACITY + PAGE - 1)
        check_uw("capacity", buffer.capacity, CAPACITY)
        buftests.run()
        test_pages()
        test_full_pages()
        test_merge()
        test_page_lines()
        test_read_pages()
        test_eol_change()
        test_chunks()
        ; a bigger store: 10 pages
        buffer.init(sys.progend(), sys.progend() + 10 * PAGE)
        test_many_pages()
        buftests.report()
    }

    alias check_uw = buftests.check_uw
    alias check_ub = buftests.check_ub
    alias check_bool = buftests.check_bool
    alias expect = buftests.expect
    alias fail = buftests.fail

    ; nothing to move in the page store
    sub at(uword position) {
    }

    sub test_pages() {
        txt.print("pages\n")
        buffer.clear()
        check_ub("empty", buffer.npages, 1)
        void buffer.insert("abcdefgh", 0)
        check_ub("one full", buffer.npages, 1)
        ; appending to a full page starts a new one
        void buffer.insert("ij", 8)
        check_ub("two", buffer.npages, 2)
        expect("abcdefghij")
        ; inserting in the middle of a full page splits it there
        void buffer.insert("XY", 3)
        expect("abcXYdefghij")
        check_ub("split", buffer.npages, 3)
        ; one long insert over several pages
        buffer.clear()
        void buffer.insert("0123456789abcdefghijklmn", 0)
        expect("0123456789abcdefghijklmn")
        check_ub("long", buffer.npages, 3)
        void buffer.insert("<>", 12)
        expect("0123456789ab<>cdefghijklmn")
    }

    sub test_full_pages() {
        txt.print("full pages\n")
        buffer.clear()
        ; fill all 4 pages, then make room in the last one only: inserting
        ; in the first page has to move bytes along to it
        void buffer.insert("ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", 0)
        check_uw("full", buffer.free(), 0)
        check_ub("pages", buffer.npages, 4)
        void buffer.delete_char(31)
        check_bool("into the last page", buffer.insert_char('+', 2), true)
        expect("AB+CDEFGHIJKLMNOPQRSTUVWXYZ01234")
        ; the same to the left: room in the first page, insert at the end
        void buffer.delete_char(0)
        check_bool("into the first page", buffer.insert_char('-', 31), true)
        expect("B+CDEFGHIJKLMNOPQRSTUVWXYZ01234-")
        ; and at the start of a full page, with room only to the left
        void buffer.delete_char(0)
        check_bool("page start", buffer.insert_char('*', 16), true)
        expect("+CDEFGHIJKLMNOPQ*RSTUVWXYZ01234-")
        check_bool("now full", buffer.insert_char('!', 0), false)
        ; room spread over all pages
        buffer.clear()
        void buffer.insert("ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", 0)
        void buffer.delete_char(28)
        void buffer.delete_char(20)
        void buffer.delete_char(12)
        void buffer.delete_char(4)
        check_bool("spread", buffer.insert("1234", 10), true)
        expect("ABCDFGHIJK1234LNOPQRSTVWXYZ01345")
        check_uw("free", buffer.free(), 0)
    }

    sub test_merge() {
        txt.print("merge\n")
        buffer.clear()
        void buffer.insert("ABCDEFGHIJKLMNOPQRSTUVWX", 0)
        check_ub("three", buffer.npages, 3)
        ; emptying a page drops it
        check_uw("drop", buffer.delete_range(8, 16), 8)
        expect("ABCDEFGHQRSTUVWX")
        check_ub("dropped", buffer.npages, 2)
        ; two small neighbours become one
        void buffer.delete_range(2, 7)
        void buffer.delete_range(5, 10)
        expect("ABHQRX")
        check_ub("merged", buffer.npages, 1)
        ; deleting everything leaves one empty page
        void buffer.delete_range(0, 6)
        expect("")
        check_ub("empty", buffer.npages, 1)
    }

    sub test_page_lines() {
        txt.print("page lines\n")
        buffer.eol = '\n'
        buffer.clear()
        void buffer.insert("ab\ncd\n\nefghijk\nl\nmnop\n", 0)
        check_lines()
        void buffer.delete_range(4, 9)
        check_lines()
        void buffer.set(1, '\n')
        void buffer.set(2, 'x')
        check_lines()
        void buffer.insert("\n\n", 0)
        check_lines()
        buffer.eol = $0d
    }

    ; line_number() and line_offset() against counting with get()
    sub check_lines() {
        uword pos
        uword line = 0
        for pos in 0 to buffer.length() {
            check_uw("line_number", buffer.line_number(pos), line)
            if pos != buffer.length() and buffer.get(pos) == buffer.eol {
                line++
                check_uw("line_offset", buffer.line_offset(line), pos + 1)
            }
        }
        check_uw("line_offset none", buffer.line_offset(line + 1), buffer.NONE)
        check_uw("line_offset 0", buffer.line_offset(0), 0)
        check_store()
    }

    sub test_read_pages() {
        txt.print("read pages\n")
        buffer.clear()
        ; a read longer than a page takes several rooms
        buftests.read_in("0123456789abcdefghij", 0)
        expect("0123456789abcdefghij")
        check_bool("loaded", buffer.loaded(20), true)
        ; into the middle of a page
        buftests.read_in("ABCDEFGHIJ", 5)
        expect("01234ABCDEFGHIJ56789abcdefghij")
        ; at a page boundary
        buffer.clear()
        void buffer.insert("abcdefgh12345678", 0)
        buftests.read_in("XYZ", 8)
        expect("abcdefghXYZ12345678")
        ; no room left at all: nothing
        void buffer.insert("0123456789abc", 0)
        pointer p
        uword room
        p, room = buffer.read_room(3)
        check_uw("no room", room, 0)
        buffer.read_done(0)
        expect("0123456789abcabcdefghXYZ12345678")
    }

    sub test_eol_change() {
        txt.print("eol change\n")
        buffer.eol = $0d
        buffer.clear()
        void buffer.insert("a\nb\nc\rd", 0)
        check_uw("cr", buffer.line_number(7), 1)
        buffer.eol = '\n'
        check_uw("lf", buffer.line_number(7), 2)
        check_uw("lf offset", buffer.line_offset(2), 4)
        buffer.eol = $0d
        check_uw("cr again", buffer.line_number(7), 1)
    }

    sub test_chunks() {
        txt.print("chunks\n")
        pointer p
        uword n
        buffer.clear()
        void buffer.insert("hello world, hello pages", 0)
        check_ub("chunks", buffer.chunks(), buffer.npages)
        p, n = buffer.chunk(0)
        check_uw("first", n, PAGE)
        check_ub("first char", @(p), 'h')
        ; changing the text in place (like translating it for saving)
        p, n = buffer.chunk(1)
        @(p) = '\n'
        buffer.eol = '\n'
        check_uw("lines", buffer.line_number(24), 1)
        buffer.eol = $0d
        expect("hello wo\nld, hello pages")
    }

    sub test_many_pages() {
        txt.print("many pages\n")
        ubyte i
        uword pos
        buffer.clear()
        model_len = 0
        check_uw("capacity", buffer.capacity, 10 * PAGE)
        ; typing a character at a time, in different places
        for i in 0 to 69 {
            pos = (i as uword * 7) % (model_len + 1)
            void buffer.insert_char('a' + i % 26, pos)
            model_insert('a' + i % 26, pos)
        }
        check_model("typed")
        ; deleting most of it a few characters at a time
        while buffer.length() > 6 {
            pos = buffer.length() / 3
            void buffer.delete_nchar(3, pos)
            model_delete(3, pos)
        }
        check_model("deleted")
        check_bool("few pages", buffer.npages <= 2, true)
        ; undo of a change over many pages
        buffer.undo_init(memory("undo2", 200, 0), 200)
        buffer.clear()
        void buffer.insert("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRST", 0)
        buffer.undo_mark()
        void buffer.delete_range(5, 50)
        check_uw("deleted", buffer.length(), 11)
        check_uw("undo", buffer.undo(), 5)
        read_contents_big()
        check_bool("undone", strings.compare(big, "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRST") == 0, true)
        check_store()
        buffer.undo_init(0, 0)
    }

    ; the text as it should be, changed the simple way
    ubyte[80] model
    ubyte model_len

    sub model_insert(ubyte c, uword pos) {
        ubyte i = model_len
        while i as uword != pos {
            model[i] = model[i - 1]
            i--
        }
        model[lsb(pos)] = c
        model_len++
    }

    sub model_delete(uword n, uword pos) {
        ubyte i
        if pos + n > model_len
            n = model_len - pos
        for i in lsb(pos) to model_len - lsb(n) - 1
            model[i] = model[i + lsb(n)]
        model_len -= lsb(n)
    }

    sub check_model(str name) {
        ubyte i
        check_uw(name, buffer.length(), model_len)
        for i in 0 to model_len - 1 {
            if buffer.get(i) != model[i] {
                fail(name)
                break
            }
        }
        check_store()
    }

    sub read_contents_big() {
        ubyte i = 0
        while i as uword < buffer.length() {
            big[i] = buffer.get(i)
            i++
        }
        big[i] = 0
    }

    ; the page store's invariants: page lengths add up, only an empty text
    ; has an empty page, line counts, and the pages read in order are the
    ; text that get() gives
    sub check_store() {
        ubyte k
        uword total = 0
        uword i
        uword lines
        pointer p
        if buffer.npages == 0
            fail("no pages")
        for k in 0 to buffer.npages - 1 {
            p = buffer.page_mem[k]
            if buffer.page_len[k] > buffer.page_size
                fail("page too long")
            if buffer.page_len[k] == 0 and buffer.npages != 1
                fail("empty page")
            lines = 0
            for i in 0 to buffer.page_len[k] - 1 {
                if buffer.page_len[k] == 0
                    break
                if p[i] != buffer.get(total + i)
                    fail("page bytes")
                if p[i] == buffer.lines_eol
                    lines++
            }
            if buffer.lines_eol != 0 and lines != buffer.page_lines[k]
                fail("page lines")
            total += buffer.page_len[k]
        }
        if total != buffer.length()
            fail("page lengths")
        if (buffer.npages + buffer.nfree) as uword * buffer.page_size != buffer.capacity
            fail("pages lost")
    }
}
