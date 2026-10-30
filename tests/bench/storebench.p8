;
; timings of the text store's busiest routines, in jiffies (1/60 s), on a
; C64 in VICE.  built with the page store (-srcdirs src:src/c64reu:src/c64,
; pages in main RAM without an REU) or the gap buffer (src:src/c64):
;   make bench
;
%import textio
%zeropage basicsafe
%import store_platform

main {
    str line = "the quick brown fox jumps over the lazy dog, 0123456789 abcdefg\r"

    sub start() {
        uword t
        uword i
        uword n
        buffer.init(sys.progend(), $c000)
        txt.lowercase()
        txt.print("store bench\n")

        ; 20 KB of text, 64 bytes a line, appended
        t = cbm.RDTIM16()
        repeat 320
            void buffer.insert(line, buffer.length())
        show("fill 20k", t)

        ; typing 300 characters at the start of the text, and deleting them
        t = cbm.RDTIM16()
        repeat 300
            void buffer.insert_char('x', 10)
        show("type 300", t)
        t = cbm.RDTIM16()
        repeat 300
            void buffer.delete_char(10)
        show("delete 300", t)

        ; scanning the whole text for a byte that isn't there
        t = cbm.RDTIM16()
        repeat 3
            void buffer.find_next('#', 0, buffer.length())
        show("find_next 3x", t)
        t = cbm.RDTIM16()
        repeat 3
            void buffer.find_prev('#', buffer.length())
        show("find_prev 3x", t)

        ; line numbers: the last line, and every 20th line start
        t = cbm.RDTIM16()
        repeat 3
            n = buffer.line_number(buffer.length())
        show("line_number 3x", t)
        t = cbm.RDTIM16()
        for i in 0 to 300 step 20
            void buffer.line_offset(i)
        show("line_offset 16x", t)

        ; going down line by line, like j
        t = cbm.RDTIM16()
        i = 0
        repeat 300
            i = buffer.next_line(i)
        show("next_line 300", t)

        txt.print("lines ")
        txt.print_uw(n)
        txt.nl()
        repeat 5 sys.waitvsync()
        @($d7ff) = 0
    }

    sub show(str name, uword t) {
        txt.print(name)
        txt.column(18)
        txt.print_uw(cbm.RDTIM16() - t)
        txt.nl()
    }
}
