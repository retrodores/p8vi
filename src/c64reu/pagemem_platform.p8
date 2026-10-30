%import reu

;
; pagemem for the C64 REU build: the page store's pages are in an REU,
; page_size bytes each, and are copied into one of SLOTS cache slots in
; main RAM to be used.  The least recently used slot is written back to
; the REU first if it was changed.  Only the last page mapped is sure to
; stay in its slot.  The first page of the REU is kept free (for a header
; to find the text again after a reset, docs/XMEM-DESIGN.md).  Without an
; REU the pages are in main RAM.
;
; Finding the REU (reu.detect()) doesn't change its memory, and a page is
; only written to the REU when it leaves a slot changed.
;
pagemem {
    const uword NO_PAGE = $ffff
    const ubyte SLOTS = 4

    uword size              ; bytes per page
    uword per_bank          ; pages per 64 KB REU bank
    bool in_reu             ; pages in the REU, not main RAM
    uword main_start        ; main RAM: where the pages are; REU: the slots
    uword last_id = NO_PAGE ; the page mapped last
    uword last_addr         ; its address
    ubyte last_slot         ; its slot

    ; the page in each slot, NO_SLOT_PAGE for none.  (ubyte, like page ids:
    ; comparing a uword array element with a ubyte goes wrong, see
    ; bugs/uword_array_eq_ubyte.p8)
    const ubyte NO_SLOT_PAGE = 255
    ubyte[SLOTS] slot_page
    bool[SLOTS] slot_dirty  ; changed since it was copied in
    ubyte[SLOTS] slot_used  ; when it was mapped last (clock)
    ubyte clock

    ; find the memory for the pages: an REU (with SLOTS pages of main RAM
    ; from start for the slots), or main RAM from start to top.  returns
    ; how many pages there are (at most max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        ubyte last_bank
        ubyte i
        size = page_size
        main_start = start
        last_bank, in_reu = reu.detect()
        if in_reu and top - start >= SLOTS * size {
            per_bank = $8000 / size * 2
            n = max_pages as uword + 1
            if last_bank < n / per_bank
                n = (last_bank as uword + 1) * per_bank
            n--
            for i in 0 to SLOTS - 1 {
                slot_page[i] = NO_SLOT_PAGE
                slot_dirty[i] = false
                slot_used[i] = 0
            }
        } else {
            in_reu = false
            n = (top - start) / size
        }
        if n > max_pages
            n = max_pages
        last_id = NO_PAGE
        return n
    }

    ; the address of page id until the next map()
    sub map(ubyte id) -> uword {
        ubyte s
        ubyte oldest = 0
        if id == last_id
            return last_addr
        last_id = id
        if not in_reu {
            last_addr = main_start + id * size
            return last_addr
        }
        clock++
        ; in a slot already?
        for s in 0 to SLOTS - 1 {
            if slot_page[s] == id
                goto found
            ; (the oldest is the one used the longest clock ticks ago)
            if clock - slot_used[s] > clock - slot_used[oldest]
                oldest = s
        }
        ; no: into the least recently used slot
        s = oldest
        if slot_dirty[s]
            transfer(s, reu.REU_STASH)
        slot_page[s] = id
        slot_dirty[s] = false
        transfer(s, reu.REU_FETCH)
found:
        slot_used[s] = clock
        last_slot = s
        last_addr = main_start + s * size
        return last_addr
    }

    ; copy slot s to or from its page in the REU
    sub transfer(ubyte s, ubyte command) {
        ; (page 0 of bank 0 is the one kept free)
        uword page = slot_page[s] as uword + 1
        reu.cmd(main_start + s * size, (page % per_bank) * size, size, lsb(page / per_bank), command)
    }

    ; the page mapped last was written to
    sub changed() {
        if in_reu
            slot_dirty[last_slot] = true
    }

    ; write changed pages back to the REU
    sub sync() {
        ubyte s
        if not in_reu
            return
        for s in 0 to SLOTS - 1 {
            if slot_dirty[s] {
                transfer(s, reu.REU_STASH)
                slot_dirty[s] = false
            }
        }
    }
}
