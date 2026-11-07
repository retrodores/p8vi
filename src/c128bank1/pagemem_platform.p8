;
; pagemem for the C128 bank 1 build (p8vi-c128x): the page store's pages
; are in the C128's RAM bank 1, page_size bytes each, and are copied into
; one of up to SLOTS cache slots in bank 0 to be used.  The least recently
; used slot is written back first if it was changed.  Only the last page
; mapped is sure to stay in its slot.  Bank 1 starts with two header slots
; of HEADER_SIZE bytes (to find the text again after a reset: bank 1 keeps
; its contents, docs/XMEM-DESIGN.md); the pages come after them.
;
; Bank 1, $0400-$fbff: headers at $0400 and $0800, pages from $0c00 (60
; of 1 KB).  ($0000-$03ff is the RAM both banks share; the top is left
; alone, where the KERNAL keeps code in each bank.)  BASIC keeps its
; variables and strings in bank 1 too: they are gone after p8vi.
;
; The MMU can only show the CPU all of one bank or the other (apart from
; the shared RAM), so the copy runs from the shared RAM, at $0200 (BASIC's
; input buffer, unused while p8vi runs; copied there again for every
; transfer), switching banks for every byte through the MMU's preset
; configurations: a write to $ff02 selects PCRB, bank 1 all RAM ($7f);
; $ff01 PCRA, bank 0 all RAM ($3f), as the KERNAL sets them up.  About 24
; cycles a byte, 25 ms for a 1 KB page at 1 MHz; with interrupts off (bank
; 1 all RAM has no KERNAL for them), and the program's own configuration
; ($0e: bank 0, KERNAL and I/O) back after.
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
    ; the pages bank 1 holds (the page store's tables are this size)
    const ubyte MAX_PAGES = 60
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
    const bool persistent = true
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
    ; from start to top.  returns how many pages there are (at most
    ; max_pages).
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
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
        for i in 0 to SLOTS - 1 {
            slot_page[i] = NO_SLOT_PAGE
            slot_dirty[i] = false
            slot_used[i] = 0
        }
        n = (BANK1_TOP - BANK1_PAGES) / size
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
            stash(slot_addr[s], page_address(slot_page[s]), size)
        slot_page[s] = id
        slot_dirty[s] = false
        fetch(page_address(id), slot_addr[s], size)
found:
        slot_used[s] = clock
        last_slot = s
        last_addr = slot_addr[s]
        return last_addr
    }

    ; where page id is in bank 1
    sub page_address(ubyte id) -> uword {
        return BANK1_PAGES + id * size
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest
    sub header_put(ubyte h, uword offset, uword src, uword count) {
        if count != 0
            stash(src, BANK1_HEADERS + h * HEADER_SIZE + offset, count)
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
        if count != 0
            fetch(BANK1_HEADERS + h * HEADER_SIZE + offset, dest, count)
    }

    ; the page mapped last was written to
    sub changed() {
        slot_dirty[last_slot] = true
    }

    ; write changed pages back to bank 1
    sub sync() {
        ubyte s
        for s in 0 to nslots - 1 {
            if slot_dirty[s] {
                stash(slot_addr[s], page_address(slot_page[s]), size)
                slot_dirty[s] = false
            }
        }
    }

    ; copy count bytes from bank 1 at src to bank 0 at dest
    sub fetch(uword src, uword dest, uword count) {
        copy(src, dest, count, 0)
    }

    ; copy count bytes from bank 0 at src to bank 1 at dest
    sub stash(uword src, uword dest, uword count) {
        copy(src, dest, count, COPY_STASH - COPY_FETCH)
    }

    ; the copy loops go to the shared RAM, then run from there
    const uword COPY_AT = $0200
    sub copy(uword src, uword dest, uword count, ubyte entry) {
        sys.memcopy(&copy_code, COPY_AT, COPY_SIZE)
        %asm {{
            lda  p8v_src
            sta  P8ZP_SCRATCH_W1
            lda  p8v_src+1
            sta  P8ZP_SCRATCH_W1+1
            lda  p8v_dest
            sta  P8ZP_SCRATCH_W2
            lda  p8v_dest+1
            sta  P8ZP_SCRATCH_W2+1
            lda  p8v_count
            sta  P8ZP_SCRATCH_B1        ; the bytes after the whole pages
            ldx  p8v_count+1            ; whole pages
            lda  p8v_entry
            beq  +
            jmp  $0200 + (p8b_pagemem.p8s_copy_code.stash - p8b_pagemem.p8s_copy_code)
+           jmp  $0200                  ; COPY_AT
        }}
    }

    ; the two loops: fetch at the start, stash after it.  relocatable (only
    ; relative branches inside), run at COPY_AT.  in: P8ZP_SCRATCH_W1 the
    ; source, P8ZP_SCRATCH_W2 the destination, X whole pages, then
    ; P8ZP_SCRATCH_B1 more bytes
    const ubyte COPY_FETCH = 0
    const ubyte COPY_STASH = 1          ; (only != COPY_FETCH matters)
    const ubyte COPY_SIZE = 112         ; (BASIC's input buffer has 161 bytes)
    asmsub copy_code() {
        %asm {{
            ; ---- fetch: bank 1 to bank 0
            sei
            ldy  #0
            cpx  #0
            beq  _frest
_fpage      sta  $ff02                  ; bank 1
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff01                  ; bank 0
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _fpage
            inc  P8ZP_SCRATCH_W1+1
            inc  P8ZP_SCRATCH_W2+1
            dex
            bne  _fpage
_frest      cpy  P8ZP_SCRATCH_B1
            beq  _fdone
            sta  $ff02
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff01
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _frest
_fdone      lda  #$0e                   ; the program's configuration
            sta  $ff00
            cli
            rts
stash
            ; ---- stash: bank 0 to bank 1
            sei
            ldy  #0
            cpx  #0
            beq  _srest
_spage      sta  $ff01                  ; bank 0
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff02                  ; bank 1
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _spage
            inc  P8ZP_SCRATCH_W1+1
            inc  P8ZP_SCRATCH_W2+1
            dex
            bne  _spage
_srest      cpy  P8ZP_SCRATCH_B1
            beq  _sdone
            sta  $ff01
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff02
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _srest
_sdone      lda  #$0e
            sta  $ff00
            cli
            rts
_end
            .cerror _end - p8b_pagemem.p8s_copy_code > 112, "copy_code is longer than COPY_SIZE"
            ; !notreached!
        }}
    }
}
