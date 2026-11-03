;
; pagemem on disk (p8vi-c64disk): the page store's pages are SEQ files on
; the drive the text files are on, page_size bytes each, copied into one of
; up to SLOTS cache slots in main RAM to be used, as in the C64 REU build
; (src/c64reu/pagemem_platform.p8).  The least recently used slot is
; written back first if it was changed.  Only the last page mapped is sure
; to stay in its slot.  SEQ files, not REL: some modern storage devices
; don't do REL files well.
;
; A SEQ file can't be rewritten in place, and replacing one means
; scratching it, through the command channel; closing the command channel
; closes every file open on the drive, and pages are written while the
; editor has a text file open too (reading a file fills pages, saving an
; ASCII file changes them).  So each page has four names,
; p8vi.swp<id><n> (id two hex digits, n 0-3; like vi's .swp files): a
; page is written to a name it isn't using, and the file it was in is
; garbage, scratched before a later write when no file is open (the
; KERNAL's count of open files, platform.KERNAL_OPEN_FILES: the editor's
; :r $ reads the directory without diskio).  Only if a page used all four
; names while a file stayed open would one be scratched then.
;
; Not tied to the C64: it needs only the KERNAL's file calls and
; platform.KERNAL_OPEN_FILES.  Built with src/diskpage before the
; target's directory (-srcdirs src:src/diskpage:src/c64).
;
; At the start the page files of an earlier session are scratched
; (p8vi.swp*: not p8vi.p*, which would take p8vi.prg or p8vi.p8 too).
; Not yet: recovery after a crash (persistent is false), and
; scratching the page files on quitting (the next start does it).
;
; Logical files 4 (write), 5 (read) and 6 (commands): the editor uses 1,
; 11, 12 and 15, diskio 12 and 13.  The drive is diskio.drivenumber's.
;
pagemem {
    const uword NO_PAGE = $ffff
    ; bytes per page
    const uword PAGE_SIZE = 1024
    ; changed pages are copies that have to be written back (the editor
    ; avoids changing pages it only reads: buffer.WRITE_BACK)
    const bool WRITE_BACK = true
    ; most pages the page store has room for: 128 KB on the disk
    const ubyte MAX_PAGES = 128
    ; SCRATCH_SIZE bytes for the page store's buffers (608 with 128 pages)
    const uword SCRATCH_SIZE = 640
    uword scratch = memory("pagescratch", SCRATCH_SIZE, 0) as uword
    ; up to SLOTS cache slots in main RAM, as many as there is room for
    const ubyte SLOTS = 4
    const bool persistent = false

    const ubyte LF_WRITE = 4
    const ubyte LF_READ = 5
    const ubyte LF_CMD = 6
    const ubyte NAMES = 4               ; names per page
    const ubyte NONE = $ff

    uword size                  ; bytes per page
    ; how much disk work there has been (to see how usable it is)
    uword @shared reads
    uword @shared writes
    uword @shared commands
    ubyte nslots                ; cache slots in use
    uword main_start            ; where the slots are
    uword last_id = NO_PAGE     ; the page mapped last
    uword last_addr             ; its address
    ubyte last_slot             ; its slot

    ; the page in each slot, NO_SLOT_PAGE for none
    const ubyte NO_SLOT_PAGE = 255
    ubyte[SLOTS] slot_page
    bool[SLOTS] slot_dirty      ; changed since it was copied in
    ubyte[SLOTS] slot_used      ; when it was mapped last (clock)
    ubyte clock

    ; per page: the name (0-3) its file is under, NONE if it has none yet;
    ; and the names (bits 0-3) whose files are garbage, to be scratched
    ubyte[MAX_PAGES] page_name
    ubyte[MAX_PAGES] page_garbage

    ; "p8vi.swp" id n, then ",s,w" or ",s,r"; "s:" in front for scratching
    str filename = "s:p8vi.swp000,s,w"
    const ubyte NAME_AT = 2             ; where the file name starts
    const ubyte NAME_LEN = 11           ; p8vi.swpXXn
    const ubyte ID_AT = NAME_AT + 8

    ; up to SLOTS slots in main RAM from start to top; the pages are on the
    ; disk.  returns how many pages there are (at most max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        ubyte i
        size = page_size
        main_start = start
        n = (top - start) / size
        nslots = SLOTS
        if n < SLOTS
            nslots = lsb(n)
        for i in 0 to SLOTS - 1 {
            slot_page[i] = NO_SLOT_PAGE
            slot_dirty[i] = false
            slot_used[i] = 0
        }
        for i in 0 to MAX_PAGES - 1 {
            page_name[i] = NONE
            page_garbage[i] = 0
        }
        ; the page files of an earlier session
        filename[ID_AT] = '*'
        command(NAME_AT + 9)            ; s:p8vi.swp*
        last_id = NO_PAGE
        if max_pages > MAX_PAGES
            max_pages = MAX_PAGES
        if nslots == 0
            return 0
        return max_pages
    }

    ; the address of page id until the next map()
    sub map(ubyte id) -> uword {
        ubyte s
        ubyte oldest = 0
        if id == last_id
            return last_addr
        last_id = id
        clock++
        ; in a slot already?
        for s in 0 to nslots - 1 {
            if slot_page[s] == id
                goto found
            ; (the oldest is the one used the longest clock ticks ago)
            if clock - slot_used[s] > clock - slot_used[oldest]
                oldest = s
        }
        ; no: into the least recently used slot
        s = oldest
        if slot_dirty[s]
            write_page(s)
        slot_page[s] = id
        slot_dirty[s] = false
        read_page(s)
found:
        slot_used[s] = clock
        last_slot = s
        last_addr = main_start + s * size
        return last_addr
    }

    ; the file name of page id, name n, in filename (after the "s:")
    sub set_name(ubyte id, ubyte n) {
        filename[ID_AT] = hex_digit(id >> 4)
        filename[ID_AT + 1] = hex_digit(id & 15)
        filename[ID_AT + 2] = '0' + n
    }

    sub hex_digit(ubyte d) -> ubyte {
        if d < 10
            return '0' + d
        return 'a' - 10 + d
    }

    ; send filename[0:n] to the drive as a command (and close the command
    ; channel: every file on the drive is closed with it)
    sub command(ubyte n) {
        commands++
        cbm.SETNAM(n, filename)
        cbm.SETLFS(LF_CMD, diskio.drivenumber, 15)
        void cbm.OPEN()
        cbm.CLRCHN()
        cbm.CLOSE(LF_CMD)
    }

    ; scratch all the garbage files, if no file is open: three names to a
    ; command ("s:a,b,c": a CBM drive's command buffer takes 40 characters)
    bool any_garbage
    str scratch_cmd = "s:" + "p8vi.swp000," * 3
    sub scratch_garbage() {
        ubyte id
        ubyte n
        ubyte names = 0
        uword at = &scratch_cmd + 2
        if not any_garbage or @(platform.KERNAL_OPEN_FILES) != 0
            return
        for id in 0 to MAX_PAGES - 1 {
            if page_garbage[id] != 0 {
                for n in 0 to NAMES - 1 {
                    if page_garbage[id] & (1 << n) != 0 {
                        set_name(id, n)
                        sys.memcopy(&filename + NAME_AT, at, NAME_LEN)
                        at += NAME_LEN + 1
                        names++
                        if names == 3 {
                            send_scratch(at)
                            at = &scratch_cmd + 2
                            names = 0
                        }
                    }
                }
                page_garbage[id] = 0
            }
        }
        if names != 0
            send_scratch(at)
        any_garbage = false
    }

    ; send scratch_cmd up to the comma before end
    sub send_scratch(uword end) {
        commands++
        cbm.SETNAM(lsb(end - 1 - &scratch_cmd), scratch_cmd)
        cbm.SETLFS(LF_CMD, diskio.drivenumber, 15)
        void cbm.OPEN()
        cbm.CLRCHN()
        cbm.CLOSE(LF_CMD)
    }

    ; write slot s to its page's file, under a name it isn't using
    sub write_page(ubyte s) {
        writes++
        ubyte id = slot_page[s]
        ubyte n = page_name[id]
        ubyte i
        uword p = main_start + s * size
        scratch_garbage()
        ; the next name that is neither its file nor garbage
        repeat NAMES {
            n = (n + 1) & (NAMES - 1)
            if n != page_name[id] and page_garbage[id] & (1 << n) == 0
                goto free_name
        }
        ; all garbage (a text file stayed open): scratch one now
        n = (page_name[id] + 1) & (NAMES - 1)
        set_name(id, n)
        command(NAME_AT + NAME_LEN)
        page_garbage[id] &= ~(1 << n)
free_name:
        set_name(id, n)
        filename[NAME_AT + NAME_LEN + 3] = 'w'
        cbm.SETNAM(NAME_LEN + 4, &filename + NAME_AT)
        cbm.SETLFS(LF_WRITE, diskio.drivenumber, LF_WRITE)
        void cbm.OPEN()
        cbm.CHKOUT(LF_WRITE)
        repeat size {
            cbm.CHROUT(@(p))
            p++
        }
        cbm.CLRCHN()
        cbm.CLOSE(LF_WRITE)
        if page_name[id] != NONE {
            page_garbage[id] |= 1 << page_name[id]
            any_garbage = true
        }
        page_name[id] = n
    }

    ; read slot s from its page's file (a page that was never written has
    ; no file: its slot is left as it is)
    sub read_page(ubyte s) {
        ubyte id = slot_page[s]
        uword p = main_start + s * size
        uword count = size
        if page_name[id] == NONE
            return
        reads++
        set_name(id, page_name[id])
        filename[NAME_AT + NAME_LEN + 3] = 'r'
        cbm.SETNAM(NAME_LEN + 4, &filename + NAME_AT)
        cbm.SETLFS(LF_READ, diskio.drivenumber, LF_READ)
        void cbm.OPEN()
        void cbm.CHKIN(LF_READ)
        while count != 0 {
            @(p) = cbm.CHRIN()
            p++
            count--
            if cbm.READST() != 0
                break
        }
        cbm.CLRCHN()
        cbm.CLOSE(LF_READ)
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest: no headers (not persistent), so nothing
    sub header_put(ubyte h, uword offset, uword src, uword count) {
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
    }

    ; the page mapped last was written to
    sub changed() {
        slot_dirty[last_slot] = true
    }

    ; write changed pages back
    sub sync() {
        ubyte s
        for s in 0 to nslots - 1 {
            if slot_dirty[s] {
                write_page(s)
                slot_dirty[s] = false
            }
        }
    }
}
