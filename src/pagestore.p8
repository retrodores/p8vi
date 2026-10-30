; The page store: a text store (see buffer.p8) that keeps the text in
; pages of page_size bytes, so it can later live in extended memory (see
; docs/XMEM-DESIGN.md).  For now the pages are in main RAM.
;
; A page holds 0 to page_size bytes of text.  The page table lists the
; pages in text order with their memory, length and number of line
; endings.  An insert shifts the rest of one page; a full page is split
; when there is a free page, otherwise bytes move on to the nearest page
; with room, so an insert fits whenever free() says it does.  Pages left
; small by deletes are merged with a neighbour.
;
; Every page in the text holds at least one byte, except the only page of
; an empty text (and briefly the page read_room() hands out).

%import buffer

buffer {
    ; bytes per page: set it before init() (the tests use small pages)
    uword page_size = 1024
    ; a page store: read_room() gives one page at a time, so a file is read
    ; in pieces, and a delete over several pages is logged a page at a time
    const bool PAGED = true
    ; most pages the store can have (in the text and free together)
    const ubyte MAX_PAGES = 64

    ; the page table: page i of the text is at page_mem[i], holds
    ; page_len[i] bytes of text, page_lines[i] of them lines_eol
    ubyte npages
    uword[MAX_PAGES] page_mem
    uword[MAX_PAGES] page_len
    uword[MAX_PAGES] page_lines
    ; the eol page_lines counts, 0 if they must be counted again (eol
    ; changed, or chunk() handed out the text to change)
    ubyte lines_eol

    ; pages not in the text
    ubyte nfree
    uword[MAX_PAGES] free_mem

    ; text that fits in all pages (at most $fffe, positions are uwords)
    uword capacity

    ; the page found last: page cur starts at position cur_start
    ubyte cur
    uword cur_start

    ; where read_room() handed out room: read_size bytes at read_off in
    ; page read_page (the rest of the page is after the room), text
    ; position read_pos
    ubyte read_page
    uword read_off
    uword read_pos
    uword read_size

    ; use the memory from start up to (not including) top and empty the store
    sub init(pointer start, pointer top) {
        uword total = 0
        uword mem = start as uword
        nfree = 0
        npages = 0
        while top as uword - mem >= page_size and nfree < MAX_PAGES {
            free_mem[nfree] = mem
            nfree++
            mem += page_size
            total += page_size
            if total > $fffe - page_size
                break
        }
        capacity = total
        clear()
    }

    ; empty the text: one empty page
    sub clear() {
        while npages != 0 {
            npages--
            free_mem[nfree] = page_mem[npages]
            nfree++
        }
        nfree--
        page_mem[0] = free_mem[nfree]
        page_len[0] = 0
        page_lines[0] = 0
        npages = 1
        lines_eol = eol
        bufend = 0
        cur = 0
        cur_start = 0
        void loaded(0)
    }

    ; call when the whole text was read in with read_room() and read_done()
    ; after clear() (a file load): its first count bytes become a new text,
    ; with all marks at 0, not modified and nothing to undo.  returns
    ; false if the text is shorter than count.
    sub loaded(uword count) -> bool {
        ubyte i
        if count > bufend
            return false
        if count != bufend
            void delete_nchar(bufend - count, count)
        for i in 0 to NUM_MARKS - 1
            marks[i] = 0
        modified = false
        change_start = 0
        change_end = count
        undo_len = 0
        undo_lost = false
        return true
    }

    ; returns free memory
    sub free() -> uword {
        return capacity - bufend
    }

    ; returns the length of the text
    sub length() -> uword {
        return bufend
    }

    ;
    ; pages
    ;

    ; make cur the page holding position: cur_start <= position <
    ; cur_start + page_len[cur], or at the end of the last page.  (a
    ; position at the end of one page is at the start of the next)
    private sub find_page(uword position) {
        while position < cur_start {
            cur--
            cur_start -= page_len[cur]
        }
        while cur != npages - 1 and position >= cur_start + page_len[cur] {
            cur_start += page_len[cur]
            cur++
        }
    }

    ; after the page table changed: start finding pages from the first
    private sub forget_page() {
        cur = 0
        cur_start = 0
    }

    ; copy count bytes from src to dest, also when they overlap
    ; (sys.memcopy can't do that).  256 bytes at a time with a byte index,
    ; which is fast on the 6502.  (not "@(dest) = @(src)" with src++ and
    ; dest++: the virtual target gets that wrong, see
    ; bugs/vm_loadp_inc_copy.p8)
    private sub move_bytes(uword src, uword dest, uword count) {
        ubyte i
        ubyte n
        if dest < src {
            ; upwards
            while count >= 256 {
                i = 0
                repeat 256 {
                    @(dest + i) = @(src + i)
                    i++
                }
                src += 256
                dest += 256
                count -= 256
            }
            i = 0
            repeat lsb(count) {
                @(dest + i) = @(src + i)
                i++
            }
        } else if dest > src {
            ; downwards from the end
            src += count
            dest += count
            while count >= 256 {
                src -= 256
                dest -= 256
                i = 255
                repeat 256 {
                    @(dest + i) = @(src + i)
                    i--
                }
                count -= 256
            }
            n = lsb(count)
            src -= n
            dest -= n
            i = n
            repeat n {
                i--
                @(dest + i) = @(src + i)
            }
        }
    }

    ; the number of lines_eol in count bytes at p
    private sub count_eol(pointer p, uword count) -> uword {
        uword lines = 0
        repeat count {
            if @(p) == lines_eol
                lines++
            p++
        }
        return lines
    }

    ; count the lines in every page again if eol changed
    private sub count_lines() {
        ubyte i
        if lines_eol == eol
            return
        lines_eol = eol
        for i in 0 to npages - 1
            page_lines[i] = count_eol(page_mem[i], page_len[i])
    }

    ; put a free page into the text as page k, empty
    private sub new_page(ubyte k) {
        ubyte i = npages
        while i != k {
            page_mem[i] = page_mem[i - 1]
            page_len[i] = page_len[i - 1]
            page_lines[i] = page_lines[i - 1]
            i--
        }
        nfree--
        page_mem[k] = free_mem[nfree]
        page_len[k] = 0
        page_lines[k] = 0
        npages++
        forget_page()
    }

    ; take page k out of the text (it should be empty)
    private sub drop_page(ubyte k) {
        free_mem[nfree] = page_mem[k]
        nfree++
        npages--
        while k != npages {
            page_mem[k] = page_mem[k + 1]
            page_len[k] = page_len[k + 1]
            page_lines[k] = page_lines[k + 1]
            k++
        }
        forget_page()
    }

    ; move the last count bytes of page k to the start of page k + 1
    private sub move_tail(ubyte k, uword count) {
        uword src = page_mem[k] + page_len[k] - count
        uword dest = page_mem[k + 1]
        uword lines = count_eol(src, count)
        move_bytes(dest, dest + count, page_len[k + 1])
        sys.memcopy(src, dest, count)
        page_len[k] -= count
        page_len[k + 1] += count
        page_lines[k] -= lines
        page_lines[k + 1] += lines
        forget_page()
    }

    ; move the first count bytes of page k to the end of page k - 1
    private sub move_head(ubyte k, uword count) {
        uword src = page_mem[k]
        uword lines = count_eol(src, count)
        sys.memcopy(src, page_mem[k - 1] + page_len[k - 1], count)
        move_bytes(src + count, src, page_len[k] - count)
        page_len[k] -= count
        page_len[k - 1] += count
        page_lines[k] -= lines
        page_lines[k - 1] += lines
        forget_page()
    }

    ; make cur a page to insert at position into, with room for at least
    ; one byte.  there must be room somewhere (free() != 0).
    private sub room_at(uword position) {
        repeat {
            find_page(position)
            if page_len[cur] < page_size
                return
            ; at the start of a full page: the end of the page before
            if position == cur_start and cur != 0 and page_len[cur - 1] < page_size {
                cur--
                cur_start -= page_len[cur]
                return
            }
            make_room(position)
        }
    }

    ; page cur, which holds position, is full: make room in it, or in
    ; the page before it if position is at its start
    private sub make_room(uword position) {
        uword offset = position - cur_start
        uword count
        ubyte k = cur
        ubyte j
        if nfree != 0 {
            ; a new page: before this one, or after it with the bytes
            ; after position
            if offset == 0
                new_page(k)
            else {
                new_page(k + 1)
                if offset != page_len[k]
                    move_tail(k, page_len[k] - offset)
            }
            return
        }
        ; no free page: move bytes along to the nearest page with room.
        ; to the right, the bytes after position (there are some: only the
        ; last page can end at position, and nothing is right of it)
        j = k + 1
        while j < npages and page_len[j] == page_size
            j++
        if j < npages {
            count = min(page_size - page_len[j], page_len[k] - offset)
            while j != k {
                j--
                move_tail(j, count)
            }
            return
        }
        ; to the left, the bytes before position (of the page before, if
        ; position is at the start of this one)
        if offset == 0 {
            k--
            offset = page_len[k]
        }
        j = k
        while page_len[j] == page_size
            j--
        count = min(page_size - page_len[j], offset)
        while j != k {
            j++
            move_head(j, count)
        }
    }

    ; merge page k with the page after it if both together are small
    private sub merge(ubyte k) {
        if k + 1 < npages and page_len[k] + page_len[k + 1] <= page_size - page_size / 4 {
            move_head(k + 1, page_len[k + 1])
            drop_page(k + 1)
        }
    }

    ;
    ; reading and changing
    ;

    ; get the character at a specific offset
    ; returns 0 for offsets past the end of the text
    sub get(uword offset) -> ubyte {
        if offset >= bufend
            return 0
        find_page(offset)
        return @(page_mem[cur] + offset - cur_start)
    }

    ; overwrite the character at offset (for overtype / replace).
    ; returns false past the end of the text.
    sub set(uword offset, ubyte value) -> bool {
        uword p
        if offset >= bufend
            return false
        find_page(offset)
        p = page_mem[cur] + offset - cur_start
        log_change('s', offset, p, 1)
        if @(p) == lines_eol
            page_lines[cur]--
        if value == lines_eol
            page_lines[cur]++
        @(p) = value
        modified = true
        changes++
        note_change(offset, 1, 1)
        return true
    }

    ; insert a character at position.
    ; returns false if the store is full.
    sub insert_char(ubyte input, uword position) -> bool {
        return insert_bytes(&input, 1, position)
    }

    ; insert count bytes from src at position, any byte values allowed.
    ; src must not point into the store itself (use copy_out first).
    ; returns false (and inserts nothing) if it doesn't fit.
    sub insert_bytes(pointer src, uword count, uword position) -> bool {
        uword n
        uword offset
        uword p
        if count > capacity - bufend
            return false
        if count == 0
            return true
        if position > bufend
            position = bufend
        note_change(position, count, 0)
        marks_inserted(position, count)
        repeat {
            room_at(position)
            offset = position - cur_start
            n = min(count, page_size - page_len[cur])
            p = page_mem[cur] + offset
            move_bytes(p, p + n, page_len[cur] - offset)
            sys.memcopy(src, p, n)
            page_len[cur] += n
            page_lines[cur] += count_eol(p, n)
            bufend += n
            log_change('i', position, p, n)
            count -= n
            if count == 0
                break
            src += n
            position += n
        }
        modified = true
        changes++
        return true
    }

    ; room to read text into at position (e.g. from a file): returns its
    ; ram address and how many bytes fit (0 if none).  write at most that
    ; many there, then call read_done() with the number written, before
    ; using the store again.  the room is in one page, so a long read
    ; takes several.
    sub read_room(uword position) -> pointer, uword {
        ubyte k
        uword offset
        uword p
        read_size = 0
        if bufend == capacity
            return 0, 0
        if position > bufend
            position = bufend
        read_pos = position
        find_page(position)
        k = cur
        offset = position - cur_start
        if nfree != 0 and page_size - page_len[k] < page_size / 2 {
            ; little room in this page: a new page at position (after
            ; moving what follows position to a page of its own)
            if offset == 0
                new_page(k)
            else {
                if offset != page_len[k] {
                    new_page(k + 1)
                    move_tail(k, page_len[k] - offset)
                }
                if nfree != 0 {
                    k++
                    new_page(k)
                    offset = 0
                }
            }
        } else {
            room_at(position)
            k = cur
            offset = position - cur_start
        }
        ; the room is at position: the rest of the page moves to its end
        read_page = k
        read_off = offset
        read_size = page_size - page_len[k]
        p = page_mem[k] + offset
        move_bytes(p, p + read_size, page_len[k] - offset)
        return p, read_size
    }

    ; count bytes were written at read_room(), make them part of the text
    sub read_done(uword count) {
        uword p
        if read_size == 0
            return
        if count > read_size
            count = read_size
        ; close the room: the rest of the page moves back
        p = page_mem[read_page] + read_off
        move_bytes(p + read_size, p + count, page_len[read_page] - read_off)
        read_size = 0
        if count != 0 {
            log_change('i', read_pos, p, count)
            note_change(read_pos, count, 0)
            marks_inserted(read_pos, count)
            page_len[read_page] += count
            page_lines[read_page] += count_eol(p, count)
            bufend += count
            modified = true
            changes++
        }
        ; read_room() may have put in an empty page
        if page_len[read_page] == 0 and npages > 1
            drop_page(read_page)
        forget_page()
    }

    ; delete up to count characters starting at position.
    ; returns the number of characters actually deleted.
    sub delete_nchar(uword count, uword position) -> uword {
        ubyte k
        uword left
        uword n
        uword offset
        uword p
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        left = count
        while left != 0 {
            find_page(position)
            offset = position - cur_start
            n = min(left, page_len[cur] - offset)
            p = page_mem[cur] + offset
            log_change('d', position, p, n)
            page_lines[cur] -= count_eol(p, n)
            move_bytes(p + n, p, page_len[cur] - offset - n)
            page_len[cur] -= n
            bufend -= n
            left -= n
            if page_len[cur] == 0 and npages > 1
                drop_page(cur)
        }
        note_change(position, 0, count)
        marks_deleted(position, count)
        modified = true
        changes++
        ; merge the pages around position if they got small
        find_page(position)
        k = cur
        merge(k)
        if k != 0
            merge(k - 1)
        return count
    }

    ; copy up to count characters starting at position to dest.
    ; returns the number of characters copied.
    sub copy_out(uword position, uword count, pointer dest) -> uword {
        uword left
        uword n
        uword offset
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        left = count
        while left != 0 {
            find_page(position)
            offset = position - cur_start
            n = min(left, page_len[cur] - offset)
            sys.memcopy(page_mem[cur] + offset, dest, n)
            dest += n
            position += n
            left -= n
        }
        return count
    }

    ; the text in pieces, to go through all of it in order without
    ; moving it (saving, translating): chunk(0) to chunk(chunks() - 1)
    ; return the ram address and length of each piece, one per page.  the
    ; bytes may be changed in place, but not their number.
    sub chunks() -> ubyte {
        return npages
    }

    sub chunk(ubyte n) -> pointer, uword {
        ; (the caller may change line endings)
        lines_eol = 0
        return page_mem[n], page_len[n]
    }

    ;
    ; searching
    ;

    ; returns the offset of the first value at or after position and
    ; before limit (limit is clamped to the end of the text).
    ; returns limit if it is not found.
    sub find_next(ubyte value, uword position, uword limit) -> uword {
        uword p
        uword stop
        if limit > bufend
            limit = bufend
        while position < limit {
            find_page(position)
            p = page_mem[cur] + position - cur_start
            stop = min(limit, cur_start + page_len[cur])
            while position < stop {
                if @(p) == value
                    return position
                p++
                position++
            }
        }
        return limit
    }

    ; returns the offset of the last value before position, or NONE.
    sub find_prev(ubyte value, uword position) -> uword {
        uword p
        if position > bufend
            position = bufend
        while position != 0 {
            find_page(position - 1)
            p = page_mem[cur] + position - cur_start
            while position != cur_start {
                p--
                position--
                if @(p) == value
                    return position
            }
        }
        return NONE
    }

    ;
    ; lines
    ;

    ; returns the start of line number line, or NONE if there aren't
    ; that many lines
    sub line_offset(uword line) -> uword {
        uword start = 0
        uword p
        ubyte k
        if line == 0
            return 0
        count_lines()
        for k in 0 to npages - 1 {
            if line <= page_lines[k] {
                ; the line-th eol in this page ends the line before
                p = page_mem[k]
                repeat {
                    if @(p) == eol {
                        line--
                        if line == 0
                            return start + (p - page_mem[k]) + 1
                    }
                    p++
                }
            }
            line -= page_lines[k]
            start += page_len[k]
        }
        return NONE
    }

    ; returns the line number of position
    sub line_number(uword position) -> uword {
        uword line = 0
        uword start = 0
        ubyte k = 0
        if position > bufend
            position = bufend
        count_lines()
        while k != npages - 1 and start + page_len[k] <= position {
            line += page_lines[k]
            start += page_len[k]
            k++
        }
        return line + count_eol(page_mem[k], position - start)
    }

} ; end of buffer block (page store)
