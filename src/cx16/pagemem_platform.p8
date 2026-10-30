%import xmem_platform

;
; pagemem for the Commander X16: the page store's pages are in banked RAM
; (xmem: from RAM bank 2), page_size bytes each, used in place.  Mapping a
; page selects its bank, so only the last page mapped can be used.  The
; first page is kept free (for a header to find the text again after a
; reset, docs/XMEM-DESIGN.md).  Without banked RAM the pages are in main
; RAM.
;
pagemem {
    const uword NO_PAGE = $ffff
    const uword BANK_SIZE = 8192

    uword size              ; bytes per page
    uword per_bank          ; pages per bank
    bool banked             ; pages in banked RAM, not main RAM
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
            if n > max_pages / per_bank + 1
                n = max_pages / per_bank + 1
            n = n * per_bank - 1
        } else {
            main_start = start
            n = (top - start) / size
        }
        if n > max_pages
            n = max_pages
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
            ; (page 0 of bank 0 is the one kept free)
            page = id as uword + 1
            xmem.select(lsb(page / per_bank))
            last_addr = $a000 + (page % per_bank) * size
        } else
            last_addr = main_start + id * size
        return last_addr
    }

    ; the page mapped last was written to (nothing to do: it is used in place)
    sub changed() {
    }

    ; write changed pages back (nothing to do)
    sub sync() {
    }
}
