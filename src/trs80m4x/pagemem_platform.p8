;
; pagemem for the TRS-80 Model 4 128 KB build (p8vi-trs80m4x): the page
; store's pages are in the second 64 KB, page_size bytes each, and are
; copied into one of up to SLOTS cache slots in main RAM to be used (at
; least MIN_SLOTS: as many as there is room for).  The least
; recently used slot is written back first if it was changed.  Only the
; last page mapped is sure to stay in its slot.  The second 64 KB starts
; with two header slots of HEADER_SIZE bytes (to find the text again after
; a reset: the memory keeps its contents, docs/XMEM-DESIGN.md); the pages
; come after them: 62 of 1 KB.
;
; The second 64 KB is two 32 KB pages that port $84 puts at $0000-$7fff in
; place of the normal RAM there (bankcopy.p8).  So everything the copying
; touches in main RAM is above $8000: the scratch buffers and the copy
; routine are in the spare memory (or the text memory), the slots come off
; the top of the text memory (both at the top of memory, see
; src/trs80m4/platform.p8), and header data goes through bounce.
;
; Without the second 64 KB (a 64 KB Model 4) the pages are in main RAM,
; from start to top (the text memory), and there are no headers.
;
%import bankcopy

pagemem {
    const uword NO_PAGE = $ffff
    ; bytes per page
    const uword PAGE_SIZE = 1024
    ; changed pages are copies that have to be written back (the editor
    ; avoids changing pages it only reads: buffer.WRITE_BACK)
    const bool WRITE_BACK = true
    ; (a page can't fail to be written here: see src/diskpage)
    const bool CAN_FAIL = false
    const bool failed = false
    sub retry() -> bool {
        return true
    }
    ; the pages the second 64 KB holds (the page store's tables are this size)
    const ubyte MAX_PAGES = 62
    ; SCRATCH_SIZE bytes for the page store's buffers (above $8000)
    const uword SCRATCH_SIZE = 768
    uword scratch
    const uword BOUNCE_SIZE = 256
    uword bounce            ; header data goes through it (above $8000)
    const ubyte SLOTS = 4
    const ubyte MIN_SLOTS = 2
    ubyte nslots            ; slots in use
    uword slot_start        ; the slots, nslots * size bytes (above $8000)
    const uword HEADER_SIZE = 1024
    ; the second 64 KB, as page (0 or 1) and address in the window: the
    ; headers at the start of page 0, then the pages
    const uword WINDOW = $0000
    const ubyte PAGES_PER_BANK = 32
    uword size              ; bytes per page
    bool banked             ; the pages are in the second 64 KB (not main RAM)
    bool persistent         ; the pages survive a reset: there are headers
    uword main_start        ; (no second 64 KB) where the pages are
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

    ; find the memory for the pages: the second 64 KB (with the slots below
    ; $8000), or main RAM from start to top.  returns how many pages there
    ; are (at most max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        ubyte i
        uword small = SCRATCH_SIZE + BOUNCE_SIZE + bankcopy.ROUTINE_SIZE
        size = page_size
        banked = false
        ; the scratch buffers and the copy routine: in the spare memory if
        ; they fit (src/trs80m4/platform.p8: above the heap), else off the top
        ; of the text memory; then the slots off the top of the text memory.
        ; all of it above $8000: the window hides what is below.
        if platform.sparetop - platform.sparestart >= small {
            scratch = platform.sparestart
            platform.sparestart += small
        } else if top - start >= small {
            top -= small
            scratch = top
        } else
            scratch = 0
        nslots = lsb(min((top - start) / size, SLOTS))
        if scratch >= $8000 and nslots >= MIN_SLOTS {
            bounce = scratch + SCRATCH_SIZE
            bankcopy.init(bounce + BOUNCE_SIZE)
            top -= nslots * size
            slot_start = top
            if slot_start >= $8000
                banked = bankcopy.present(bounce)
            if not banked
                top += nslots * size
        }
        main_start = start
        if banked {
            n = MAX_PAGES
            for i in 0 to nslots - 1 {
                slot_page[i] = NO_SLOT_PAGE
                slot_dirty[i] = false
                slot_used[i] = 0
            }
        } else
            n = (top - start) / size
        persistent = banked
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
        if not banked {
            last_addr = main_start + id * size
            return last_addr
        }
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
            stash(s)
        slot_page[s] = id
        slot_dirty[s] = false
        fetch(s)
found:
        slot_used[s] = clock
        last_slot = s
        last_addr = slot_address(s)
        return last_addr
    }

    sub slot_address(ubyte s) -> uword {
        return slot_start + (s as uword) * size
    }

    ; page id's place in the second 64 KB: the two headers first
    ; (page 0 at $0000 and $0400), then the pages
    sub page_bank(ubyte id) -> ubyte {
        return (id + 2) / PAGES_PER_BANK
    }
    sub page_address(ubyte id) -> uword {
        return WINDOW + (((id + 2) % PAGES_PER_BANK) as uword) * size
    }

    ; copy slot s to its page, or (fetch) its page into it
    sub stash(ubyte s) {
        bankcopy.copy(page_bank(slot_page[s]), slot_address(s), page_address(slot_page[s]), size)
    }
    sub fetch(ubyte s) {
        bankcopy.copy(page_bank(slot_page[s]), page_address(slot_page[s]), slot_address(s), size)
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest.  src and dest may be below $8000, which the page hides:
    ; through bounce.
    sub header_put(ubyte h, uword offset, uword src, uword count) {
        uword n
        uword at = WINDOW + h * HEADER_SIZE + offset
        while count != 0 {
            n = min(count, BOUNCE_SIZE)
            sys.memcopy(src, bounce, n)
            bankcopy.copy(0, bounce, at, n)
            src += n
            at += n
            count -= n
        }
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
        uword n
        uword at = WINDOW + h * HEADER_SIZE + offset
        while count != 0 {
            n = min(count, BOUNCE_SIZE)
            bankcopy.copy(0, at, bounce, n)
            sys.memcopy(bounce, dest, n)
            dest += n
            at += n
            count -= n
        }
    }

    ; the page mapped last was written to
    sub changed() {
        if banked
            slot_dirty[last_slot] = true
    }

    ; write changed pages back
    sub sync() {
        ubyte s
        if not banked
            return
        for s in 0 to nslots - 1 {
            if slot_dirty[s] {
                stash(s)
                slot_dirty[s] = false
            }
        }
    }
}
