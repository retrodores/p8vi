%import dma

;
; pagemem for the MEGA65 page store build (p8vi-mega65dma): the page
; store's pages are in attic RAM (256 KB of it from $8000000) if the
; MEGA65 has it, otherwise in chip RAM banks 4 and 5 (128 KB), page_size
; bytes each, and are copied with DMA into one of up to SLOTS cache slots
; in main RAM to be used, as in the C64 REU build
; (src/c64reu/pagemem_platform.p8).
; The least recently used slot is written back first if it was changed.
; Only the last page mapped is sure to stay in its slot.
;
; Slot 0 is at LOW_SLOT, in the free memory below the program
; ($1600-$1fdf: the scratch buffers, slot 0, then the editor's key
; buffers), so there is always one; the others come from the memory after
; the program, as many as fit.  The page store copies between pages through
; its scratch buffers, so one slot is enough to work.  The memory starts
; with two header slots of HEADER_SIZE bytes (to find the text again after
; a reset, docs/XMEM-DESIGN.md); the pages come after them.
;
; Attic RAM: release boards, the development kit and xemu have it; the
; Nexys4 boards that can run the MEGA65 core don't (attic_present()).
;
; Why not the $a000-$bfff window and cx16.rambank(): MAP's upper four
; blocks share one offset, so while $a000 shows another bank the KERNAL
; isn't mapped at $e000, and an interrupt or KERNAL call crashes.  And the
; program would have to end below $a000.  DMA leaves the map alone.
;
; Banks 4 and 5 are free while BASIC 65 isn't running (its graphics
; commands use them).  BASIC 65 doesn't use attic RAM; some resident
; utilities might.
;
pagemem {
    const uword NO_PAGE = $ffff
    ; bytes per page
    const uword PAGE_SIZE = 1024
    ; most pages the page store has room for
    const ubyte MAX_PAGES = 255
    ; SCRATCH_SIZE bytes for the page store's buffers: at $1600, free in
    ; MEGA65 mode, then slot 0 (platform.p8 gives the editor the rest,
    ; $1d00-$1fdf)
    const uword SCRATCH_SIZE = 768
    uword scratch = $1600
    const uword LOW_SLOT = $1900
    ; up to SLOTS cache slots: slot 0 at LOW_SLOT, the others after the
    ; program as far as there is room (nslots)
    const ubyte SLOTS = 4
    const uword HEADER_SIZE = 1024
    ; where the pages are: megabyte, first 64 KB bank, banks.  attic RAM
    ; ($8000000: megabyte $80) or chip RAM banks 4 and 5
    const ubyte ATTIC_MB = $80
    bool attic
    ubyte ext_mb
    ubyte ext_bank
    ubyte ext_banks

    uword size              ; bytes per page
    ubyte nslots            ; cache slots in use
    uword per_bank          ; pages per 64 KB bank
    bool persistent = true  ; the pages survive a reset: there are headers
    uword first_page        ; page of page id 0 (after the headers)
    uword main_start        ; where slot 1 is (after the program)
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

    ; the pages in attic RAM or banks 4 and 5, with slot 0 at LOW_SLOT and up
    ; to SLOTS-1 more slots in main RAM from start to top.  returns how many
    ; pages there are (at most max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        ubyte i
        attic = attic_present()
        ext_mb = 0
        ext_bank = 4
        ext_banks = 2
        if attic {
            ext_mb = ATTIC_MB
            ext_bank = 0
            ext_banks = 4
        }
        size = page_size
        main_start = start
        n = (top - start) / size
        nslots = SLOTS
        if n < SLOTS - 1
            nslots = lsb(n) + 1
        per_bank = $8000 / size * 2
        first_page = 2 * HEADER_SIZE / size
        n = ext_banks * per_bank - first_page
        for i in 0 to SLOTS - 1 {
            slot_page[i] = NO_SLOT_PAGE
            slot_dirty[i] = false
            slot_used[i] = 0
        }
        if n > max_pages
            n = max_pages
        last_id = NO_PAGE
        return n
    }

    ; is there attic RAM?  not on the Nexys4 boards (model IDs $40-$42 at
    ; $d629, in the MEGA65 I/O personality, which BASIC 65 selects).  on any
    ; other board a byte is written to it and read back, twice.  the byte
    ; goes to $8000000 + scratch: a board that ignored the megabyte would
    ; write it to scratch in chip RAM (not in use yet), and that shows.
    ubyte probe
    sub attic_present() -> bool {
        ubyte pattern = $a5
        if @($d629) >= $40 and @($d629) <= $42
            return false
        repeat 2 {
            @(scratch) = pattern ^ $ff
            probe = pattern
            dma.far(0, &probe, 0, ATTIC_MB, scratch, 0, 1)
            if @(scratch) != pattern ^ $ff
                return false
            probe = 0
            dma.far(ATTIC_MB, scratch, 0, 0, &probe, 0, 1)
            if probe != pattern
                return false
            pattern = $5a
        }
        return true
    }

    ; where slot s is
    sub slot_addr(ubyte s) -> uword {
        if s == 0
            return LOW_SLOT
        return main_start + (s - 1) * size
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
        last_addr = slot_addr(s)
        return last_addr
    }

    ; copy slot s to (out) or from its page
    sub transfer(ubyte s, bool out) {
        uword page = slot_page[s] as uword + first_page
        uword slot = slot_addr(s)
        uword addr = (page % per_bank) * size
        ubyte bank = ext_bank + lsb(page / per_bank)
        if out
            dma.far(0, slot, 0, ext_mb, addr, bank, size)
        else
            dma.far(ext_mb, addr, bank, 0, slot, 0, size)
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest.  (at the start of the pages' memory)
    sub header_put(ubyte h, uword offset, uword src, uword count) {
        if count != 0
            dma.far(0, src, 0, ext_mb, h * HEADER_SIZE + offset, ext_bank, count)
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
        if count != 0
            dma.far(ext_mb, h * HEADER_SIZE + offset, ext_bank, 0, dest, 0, count)
    }

    ; the page mapped last was written to
    sub changed() {
        slot_dirty[last_slot] = true
    }

    ; write changed pages back to the banks
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
