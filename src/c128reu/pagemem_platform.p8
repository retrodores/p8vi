%import reu
%import bank1

;
; pagemem for the C128 REU build (p8vi-c128reu): the page store's pages
; are in an REU (1700, 1750, 1764 or bigger), page_size bytes each, or
; without one in RAM bank 1 (as p8vi-c128x, src/c128bank1), and are copied
; into one of up to SLOTS cache slots in bank 0 to be used.  The least
; recently used slot is written back first if it was changed.  Only the
; last page mapped is sure to stay in its slot.
;
; Both keep their contents over a reset: they start with two header slots
; of HEADER_SIZE bytes (to find the text again, docs/XMEM-DESIGN.md), the
; pages come after them.  The REU's as in the C64 REU build (src/c64reu,
; with src/c64/reu.p8); bank 1: headers at $0400 and $0800, 60 pages of
; 1 KB from $0c00 (src/c128/bank1.p8 copies).
;
; The scratch buffer and, if there is room, one slot are in the golden RAM
; the editor's key buffers leave (platform.sparestart); the other slots
; are at the start of the text memory.
;
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
    ; most pages the page store has room for (its tables are this size):
    ; MAX_PAGES KB with an REU, for the text, the yank buffer and the undo
    ; log together (128 was too few to undo deleting a 30 KB text, which
    ; also goes to the yank buffer; 255 would leave no room for a slot in
    ; main RAM)
    const ubyte MAX_PAGES = 192
    ; SCRATCH_SIZE bytes for the page store's buffers (golden RAM, see init)
    const uword SCRATCH_SIZE = 768
    uword scratch = $1300
    const ubyte SLOTS = 4
    const uword HEADER_SIZE = 1024
    ; bank 1: the headers, then the pages
    const uword BANK1_HEADERS = $0400
    const uword BANK1_PAGES = BANK1_HEADERS + 2 * HEADER_SIZE
    const uword BANK1_TOP = $fc00

    uword size              ; bytes per page
    bool in_reu             ; the pages in an REU, not bank 1
    const bool persistent = true
    uword per_bank          ; pages per 64 KB REU bank
    uword first_page        ; REU page of page id 0 (after the headers)
    uword last_id = NO_PAGE ; the page mapped last
    uword last_addr         ; its address
    ubyte last_slot         ; its slot
    ubyte nslots            ; slots in use

    ; the page in each slot, NO_SLOT_PAGE for none.  (ubyte, like page ids:
    ; comparing a uword array element with a ubyte goes wrong, see
    ; bugs/uword_array_eq_ubyte.p8)
    const ubyte NO_SLOT_PAGE = 255
    ubyte[SLOTS] slot_page
    bool[SLOTS] slot_dirty  ; changed since it was copied in
    ubyte[SLOTS] slot_used  ; when it was mapped last (clock)
    uword[SLOTS] slot_addr  ; where it is in bank 0
    ubyte clock

    ; the slots: golden RAM first (after the scratch buffer), then main RAM
    ; from start to top.  the pages: an REU, or bank 1.  returns how many
    ; pages there are (at most max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        ubyte last_bank
        ubyte i
        size = page_size
        nslots = 0
        if platform.sparetop - platform.sparestart >= SCRATCH_SIZE {
            scratch = platform.sparestart
            platform.sparestart += SCRATCH_SIZE
        } else {
            scratch = top - SCRATCH_SIZE
            top -= SCRATCH_SIZE
        }
        if platform.sparetop - platform.sparestart >= size {
            slot_addr[0] = platform.sparestart
            platform.sparestart += size
            nslots = 1
        }
        while nslots < SLOTS and top - start >= size {
            slot_addr[nslots] = start
            start += size
            nslots++
        }
        ; with no slot the store hangs: say so when code growth has taken
        ; the room (one slot is enough; docs/TODO.md, v0.4)
        if nslots == 0 {
            platform.stop()
            txt.print("no room for the page slots\n")
            sys.exit(1)
        }
        for i in 0 to SLOTS - 1 {
            slot_page[i] = NO_SLOT_PAGE
            slot_dirty[i] = false
            slot_used[i] = 0
        }
        last_bank, in_reu = reu.detect()
        if in_reu {
            per_bank = $8000 / size * 2
            first_page = 2 * HEADER_SIZE / size
            n = max_pages as uword + first_page
            if last_bank < n / per_bank
                n = (last_bank as uword + 1) * per_bank
            n -= first_page
        } else {
            n = (BANK1_TOP - BANK1_PAGES) / size
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
            transfer(s, true)
        slot_page[s] = id
        slot_dirty[s] = false
        transfer(s, false)
found:
        slot_used[s] = clock
        last_slot = s
        last_addr = slot_addr[s]
        return last_addr
    }

    ; copy slot s to its page (stash), or from it
    sub transfer(ubyte s, bool stash) {
        uword page = slot_page[s]
        if in_reu {
            page += first_page
            reu.cmd(slot_addr[s], (page % per_bank) * size, size, lsb(page / per_bank),
                    if stash reu.REU_STASH else reu.REU_FETCH)
        } else if stash {
            bank1.stash(slot_addr[s], BANK1_PAGES + page * size, size)
        } else {
            bank1.fetch(BANK1_PAGES + page * size, slot_addr[s], size)
        }
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest.  (in REU bank 0, or bank 1)
    sub header_put(ubyte h, uword offset, uword src, uword count) {
        if count == 0
            return
        if in_reu
            reu.cmd(src, h * HEADER_SIZE + offset, count, 0, reu.REU_STASH)
        else
            bank1.stash(src, BANK1_HEADERS + h * HEADER_SIZE + offset, count)
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
        if count == 0
            return
        if in_reu
            reu.cmd(dest, h * HEADER_SIZE + offset, count, 0, reu.REU_FETCH)
        else
            bank1.fetch(BANK1_HEADERS + h * HEADER_SIZE + offset, dest, count)
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
                transfer(s, true)
                slot_dirty[s] = false
            }
        }
    }
}
