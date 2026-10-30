%import xmem_platform

;
; pagemem for the Commander X16: the page store's pages are in banked RAM
; (xmem: from RAM bank 2), page_size bytes each, used in place.  Mapping a
; page selects its bank, so only the last page mapped can be used.  The
; first bank starts with two header slots of HEADER_SIZE bytes (to find
; the text again after a reset, docs/XMEM-DESIGN.md); the pages come after
; them.  Without banked RAM the pages are in main RAM.
;
pagemem {
    const uword NO_PAGE = $ffff
    ; bytes per page (the X16 is fast enough to shift 2 KB pages, and the
    ; page table, in main RAM, can be smaller)
    const uword PAGE_SIZE = 2048
    ; most pages the page store has room for (its tables are in main RAM)
    const ubyte MAX_PAGES = 128
    ; SCRATCH_SIZE bytes for the page store's buffers: golden RAM
    const uword SCRATCH_SIZE = 1024
    const uword scratch = $0400
    const uword BANK_SIZE = 8192
    const uword HEADER_SIZE = 1024

    uword size              ; bytes per page
    uword per_bank          ; pages per bank
    bool banked             ; pages in banked RAM, not main RAM
    bool persistent         ; the pages survive a reset: there are headers
    uword first_page        ; page of page id 0 (after the headers)
    uword main_start        ; where the pages are in main RAM
    uword last_id = NO_PAGE ; the page mapped last
    uword last_addr         ; its address

    ; find the memory for the pages: banked RAM, or main RAM from start to
    ; top.  returns how many pages there are (at most max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        size = page_size
        per_bank = BANK_SIZE / size
        n = xmem.init()
        banked = n != 0
        if banked {
            first_page = 2 * HEADER_SIZE / size
            if n > max_pages / per_bank + 2
                n = max_pages / per_bank + 2
            n = n * per_bank - first_page
        } else {
            main_start = start
            n = (top - start) / size
        }
        if n > max_pages
            n = max_pages
        persistent = banked
        last_id = NO_PAGE
        return n
    }

    ; the address of page id until the next map()
    sub map(ubyte id) -> uword {
        uword page
        if id == last_id
            return last_addr
        last_id = id
        if banked {
            page = id as uword + first_page
            xmem.select(lsb(page / per_bank))
            last_addr = $a000 + (page % per_bank) * size
        } else
            last_addr = main_start + id * size
        return last_addr
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest.  (src and dest in main RAM; the headers are at the
    ; start of the first bank)
    sub header_put(ubyte h, uword offset, uword src, uword count) {
        xmem.select(0)
        last_id = NO_PAGE
        sys.memcopy(src, $a000 + h * HEADER_SIZE + offset, count)
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
        xmem.select(0)
        last_id = NO_PAGE
        sys.memcopy($a000 + h * HEADER_SIZE + offset, dest, count)
    }

    ; the page mapped last was written to (nothing to do: it is used in place)
    sub changed() {
    }

    ; write changed pages back (nothing to do)
    sub sync() {
    }
}
