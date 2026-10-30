;
; pagemem for the virtual target (the page store's tests): the pages are
; kept in main RAM, but are only seen through one window, a copy that is
; written back when another page is mapped, and only if changed() was
; called.  That is the strictest of the real ones (the X16 shows one bank
; at a time, the C64 copies pages from the REU): using a page after
; mapping another, or writing to one without changed(), shows up as
; wrong text in the tests.
;
pagemem {
    const uword NO_PAGE = $ffff

    uword size              ; bytes per page
    uword window            ; where the mapped page is seen
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
        pages = start + size
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
