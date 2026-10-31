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
        ; 4 pages for the text, 8 for the streams (yank buffer, undo log),
        ; one more for pagemem's window
        buffer.stream_min = 8
        ; (and the header slots)
        buffer.init(sys.progend(), sys.progend() + CAPACITY + 9 * PAGE + 2 * pagemem.HEADER_SIZE)
        buffer.yank_size = 32
        check_uw("capacity", buffer.free(), CAPACITY)
        buftests.run()
        test_pages()
        test_full_pages()
        test_merge()
        test_page_lines()
        test_read_pages()
        test_eol_change()
        test_chunks()
        ; a bigger store: 10 pages for the text, 40 for the streams
        buffer.stream_min = 40
        reinit()
        test_many_pages()
        test_streams()
        test_delete_lines()
        test_recovery()
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
        check_ub("empty", buffer.pages(), 1)
        void buffer.insert("abcdefgh", 0)
        check_ub("one full", buffer.pages(), 1)
        ; appending to a full page starts a new one
        void buffer.insert("ij", 8)
        check_ub("two", buffer.pages(), 2)
        expect("abcdefghij")
        ; inserting in the middle of a full page splits it there
        void buffer.insert("XY", 3)
        expect("abcXYdefghij")
        check_ub("split", buffer.pages(), 3)
        ; one long insert over several pages
        buffer.clear()
        void buffer.insert("0123456789abcdefghijklmn", 0)
        expect("0123456789abcdefghijklmn")
        check_ub("long", buffer.pages(), 3)
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
        check_ub("pages", buffer.pages(), 4)
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
        check_ub("three", buffer.pages(), 3)
        ; emptying a page drops it
        check_uw("drop", buffer.delete_range(8, 16), 8)
        expect("ABCDEFGHQRSTUVWX")
        check_ub("dropped", buffer.pages(), 2)
        ; two small neighbours become one
        void buffer.delete_range(2, 7)
        void buffer.delete_range(5, 10)
        expect("ABHQRX")
        check_ub("merged", buffer.pages(), 1)
        ; deleting everything leaves one empty page
        void buffer.delete_range(0, 6)
        expect("")
        check_ub("empty", buffer.pages(), 1)
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
        check_ub("chunks", buffer.chunks(), buffer.pages())
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
        check_uw("capacity", buffer.free(), 10 * PAGE)
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
        check_bool("few pages", buffer.pages() <= 2, true)
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

    sub test_streams() {
        txt.print("streams\n")
        ubyte i
        buffer.clear()
        void buffer.insert("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRST", 0)
        ; a yank over several pages, put twice
        check_bool("yank", buffer.yank(10, 30, false), true)
        check_ub("yank pages", buffer.stream_pages(buffer.YANK), 4)
        void buffer.delete_range(10, 56)
        expect("0123456789")
        check_bool("put", buffer.put(10), true)
        check_bool("put again", buffer.put(10), true)
        read_contents_big()
        check_bool("put twice", strings.compare(big, "0123456789abcdefghijklmnopqrstuvwxyzABCDabcdefghijklmnopqrstuvwxyzABCD") == 0, true)
        check_store()
        ; the streams don't take what the text may still need: free() is
        ; still all there
        check_uw("free", buffer.free(), 80 - 70)
        buffer.clear()
        check_uw("free empty", buffer.free(), 80)
        ; a big undo log, then fill the text: the log gives way
        buffer.undo_init(memory("undo2", 200, 0), $ffff)
        void buffer.insert("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRST", 0)
        buffer.undo_mark()
        void buffer.delete_range(0, 56)
        check_bool("can undo", buffer.can_undo(), true)
        buffer.undo_mark()
        for i in 0 to 79
            check_bool("fill", buffer.insert_char('x', 0), true)
        check_uw("full", buffer.free(), 0)
        check_store()
        buffer.undo_init(0, 0)
    }

    ; deletes over line endings keep the line counts right
    sub test_delete_lines() {
        txt.print("delete lines\n")
        ubyte i
        buffer.eol = '\n'
        buffer.clear()
        for i in 0 to 15
            void buffer.insert("a\nb\n\n", 0)
        for i in 0 to 9 {
            void buffer.delete_nchar(i % 4 + 1, (i as uword * 5) % (buffer.length() - 4))
            check_lines()
        }
        buffer.eol = $0d
    }

    ; init() on the same memory: like a reset
    sub reinit() {
        buffer.init(sys.progend(), sys.progend() + 51 * PAGE + 2 * pagemem.HEADER_SIZE)
        buffer.yank_size = $ffff
    }

    ubyte[buffer.META_SIZE] meta

    ; the text and a mark into the header
    sub save_text(str text, ubyte tag) {
        buffer.clear()
        void buffer.insert(text, 0)
        buffer.set_mark(0, 3)
        meta[0] = tag
        buffer.sync(meta)
    }

    sub recover_text(str name, str text, ubyte tag) {
        meta[0] = 0
        check_bool(name, buffer.recover(meta), true)
        expect(text)
        check_ub("meta", meta[0], tag)
        check_uw("cursor", buffer.get_mark(0), 3)
        check_bool("modified", buffer.modified, true)
    }

    sub test_recovery() {
        txt.print("recovery\n")
        ubyte i
        ; nothing in fresh memory
        check_ub("none", buffer.recoverable, 0)
        check_bool("nothing", buffer.recover(meta), false)
        ; a synced text waits after a reset
        save_text("first text\nline two", 'a')
        reinit()
        check_ub("one", buffer.recoverable, 1)
        expect("")
        ; its pages are left alone: fill the new text and more
        for i in 0 to 79
            void buffer.insert_char('x', 0)
        check_uw("full", buffer.free(), 0)
        check_store()
        ; a second session's text, and a second reset: two wait
        save_text("second", 'b')
        reinit()
        check_ub("two", buffer.recoverable, 2)
        ; the newer comes back first, then the older
        recover_text("newer", "second", 'b')
        check_ub("left", buffer.recoverable, 1)
        recover_text("older", "first text\nline two", 'a')
        check_ub("none left", buffer.recoverable, 0)
        ; (the line endings are counted again, with the eol the editor sets)
        buffer.eol = '\n'
        check_uw("lines", buffer.line_number(buffer.length()), 1)
        buffer.eol = $0d
        check_store()
        ; the recovered text is the session's now: after a reset it waits
        reinit()
        check_ub("again", buffer.recoverable, 1)
        recover_text("again", "first text\nline two", 'a')
        ; two waiting and a new text: the older is dropped at the first sync
        save_text("third", 'c')
        reinit()
        save_text("fourth", 'd')
        reinit()
        check_ub("third and fourth", buffer.recoverable, 2)
        save_text("fifth", 'e')
        check_ub("one dropped", buffer.recoverable, 1)
        reinit()
        check_ub("fourth and fifth", buffer.recoverable, 2)
        recover_text("fifth", "fifth", 'e')
        recover_text("fourth", "fourth", 'd')
        ; clean(): nothing to recover
        buffer.clean()
        reinit()
        check_ub("clean", buffer.recoverable, 0)
        ; a damaged header doesn't count
        save_text("sixth", 'f')
        pagemem.header_put(buffer.header_slot(), buffer.H_LENGTH, &i as uword, 1)
        reinit()
        check_ub("damaged", buffer.recoverable, 0)
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

    ; the page store's invariants (buffer.check())
    sub check_store() {
        uword problem = buffer.check()
        if @(problem) != 0
            fail(problem)
    }


}
