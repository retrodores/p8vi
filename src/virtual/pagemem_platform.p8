;
; pagemem for the virtual target (the page store's tests): the pages are
; kept in main RAM, but are only seen through one window, a copy that is
; written back when another page is mapped, and only if changed() was
; called.  That is the strictest of the real ones (the X16 shows one bank
; at a time, the C64 copies pages from the REU): using a page after
; mapping another, or writing to one without changed(), shows up as
; wrong text in the tests.  Two header slots of HEADER_SIZE bytes come
; before the pages; nothing here clears them, so calling init() again on
; the same memory is like a reset.
;
pagemem {
    const uword NO_PAGE = $ffff
    ; bytes per page (the tests set smaller ones)
    const uword PAGE_SIZE = 1024
    ; most pages the page store has room for
    const ubyte MAX_PAGES = 255
    ; SCRATCH_SIZE bytes for the page store's buffers
    const uword SCRATCH_SIZE = 1024
    uword scratch = memory("pagescratch", SCRATCH_SIZE, 0) as uword
    const uword HEADER_SIZE = 1024
    const bool persistent = true

    uword size              ; bytes per page
    uword window            ; where the mapped page is seen
    uword headers           ; the header slots
    uword pages             ; where the pages are kept
    uword last_id = NO_PAGE ; the page in the window
    uword last_addr         ; its address (window)
    bool dirty              ; changed() since it was mapped
    ubyte maps_done         ; counts map() calls that changed the window

    ; use start to top for the window and the pages; returns how many
    ; pages there are (at most max_pages)
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword {
        uword n
        size = page_size
        window = start
        headers = start + size
        pages = headers + 2 * HEADER_SIZE
        n = (top - pages) / size
        if n > max_pages
            n = max_pages
        last_id = NO_PAGE
        last_addr = window
        dirty = false
        return n
    }

    ; the address of page id until the next map()
    sub map(ubyte id) -> uword {
        if id == last_id
            return window
        if dirty
            sys.memcopy(window, pages + last_id * size, size)
        ; anything left in the window from the page before is gone
        sys.memset(window, size, '#')
        sys.memcopy(pages + id * size, window, size)
        last_id = id
        dirty = false
        maps_done++
        return window
    }

    ; copy count bytes from src to header slot h at offset, or (get) from
    ; there to dest
    sub header_put(ubyte h, uword offset, uword src, uword count) {
        sys.memcopy(src, headers + h * HEADER_SIZE + offset, count)
    }

    sub header_get(ubyte h, uword offset, uword dest, uword count) {
        sys.memcopy(headers + h * HEADER_SIZE + offset, dest, count)
    }

    ; the page mapped last was written to
    sub changed() {
        dirty = true
    }

    ; write changed pages back to where they are kept
    sub sync() {
        if dirty and last_id != NO_PAGE
            sys.memcopy(window, pages + last_id * size, size)
        dirty = false
    }
}
