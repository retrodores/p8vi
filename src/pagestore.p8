; The page store: a text store (see buffer.p8) that keeps the text in
; pages of page_size bytes, so it can live in extended memory (see
; docs/XMEM-DESIGN.md).  Where the pages are is up to pagemem
; (src/<target>/pagemem_platform.p8): pagemem.map(id) gives the address of
; page id, valid until the next map(), and pagemem.changed() must follow
; every write to it (an REU copy is then written back).  So only one page
; is used at a time; bytes going from one page to another go through
; a small buffer in main RAM.
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
%import pagemem_platform
%import fastmem_platform

buffer {
    ; (variables marked private are the page store's own: use the routines.
    ; page_size and stream_min are settings for init(); recoverable and
    ; synced_changes are read by the editor)

    ; bytes per page: pagemem's, or set it before init() (the tests use
    ; small pages)
    uword page_size = pagemem.PAGE_SIZE
    ; a page store: read_room() gives one page at a time, so a file is read
    ; in pieces, and a delete over several pages is logged a page at a time
    const bool PAGED = true
    ; changed pages are written back (to an REU, the disk...), so the editor
    ; avoids changing pages it only reads (pagemem.WRITE_BACK)
    const bool WRITE_BACK = pagemem.WRITE_BACK
    ; most pages the store can have (the text's, the streams' and free
    ; ones together); page ids are 0 to MAX_PAGES - 1
    const ubyte MAX_PAGES = pagemem.MAX_PAGES
    ; pages kept for the streams (the yank buffer and the undo log) when
    ; there are few pages (set it before init(); the tests change it)
    ubyte stream_min = 3

    ; the page table: page i of the text is page page_id[i], holds
    ; page_len[i] bytes of text, page_lines[i] of them lines_eol
    private ubyte npages
    private ubyte[MAX_PAGES] page_id
    private uword[MAX_PAGES] page_len
    private uword[MAX_PAGES] page_lines
    ; the eol page_lines counts, 0 if they must be counted again (eol
    ; changed, or chunk() handed out the text to change)
    private ubyte lines_eol

    ; the buffers below are in pagemem.scratch (on the X16 that is golden
    ; RAM, which leaves main RAM for the program): 2 * BOUNCE_SIZE +
    ; MAX_PAGES + H_IDS + 32 + 2 * STREAM_PAGES bytes

    ; pages not in the text (MAX_PAGES bytes)
    private ubyte nfree
    private ^^ubyte free_id

    ; bytes going from one page to another pass through bounce, and bytes
    ; going from a stream into the text through put_buf (bounce is used
    ; while inserting them)
    const ubyte BOUNCE_SIZE = 128
    private ^^ubyte bounce
    private ^^ubyte put_buf

    ; all pages, and how many of them the text may have: the rest is kept
    ; for the streams.  page_size is 1 << page_shift.
    private ubyte total_pages
    private ubyte text_max
    private ubyte page_shift

    ; the streams: the yank buffer (YANK) and the undo log (UNDO), each a
    ; list of pages outside the text, s_count[s] of them at
    ; s_page[s * STREAM_PAGES]
    const ubyte YANK = 0
    const ubyte UNDO = 1
    const ubyte STREAM_PAGES = 64
    private ubyte[2] s_count
    private ^^ubyte s_page          ; 2 * STREAM_PAGES bytes
    private uword s_word

    ; text that fits in all pages (at most $fffe, positions are uwords)
    private uword capacity

    ; the page found last: page cur starts at position cur_start
    private ubyte cur
    private uword cur_start

    ; where read_room() handed out room: read_size bytes at read_off in
    ; page read_page (the rest of the page is after the room), text
    ; position read_pos
    private ubyte read_page
    private uword read_off
    private uword read_pos
    private uword read_size

    ; use the memory from start up to (not including) top, or extended
    ; memory if there is some (pagemem decides), and empty the store
    sub init(pointer start, pointer top) {
        ubyte n = lsb(pagemem.init(start as uword, top as uword, page_size, MAX_PAGES))
        uword size = 1
        ubyte i
        total_pages = n
        page_shift = 0
        while size != page_size {
            size <<= 1
            page_shift++
        }
        ; the buffers
        bounce = pagemem.scratch as ^^ubyte
        put_buf = bounce + BOUNCE_SIZE
        free_id = put_buf + BOUNCE_SIZE
        hdr = free_id + MAX_PAGES
        held = hdr + H_IDS
        s_page = held + 32
        ; texts to recover keep their pages
        sys.memset(held, 32, 0)
        recoverable = 0
        session_slot = NO_SLOT
        synced_changes = changes
        if pagemem.persistent
            find_texts(n)
        npages = 0
        nfree = 0
        s_count[YANK] = 0
        s_count[UNDO] = 0
        i = n
        while i != 0 {
            ; (the free pages are taken from the end: page 0 first)
            i--
            if held[i >> 3] & (1 << (i & 7)) == 0 {
                free_id[nfree] = i
                nfree++
            }
        }
        set_text_max()
        clear()
    }

    ; the pages the text may have: all free ones but stream_min, and no
    ; more than 64 KB of text takes (and a few, to split pages into).  and
    ; so the capacity.
    private sub set_text_max() {
        ubyte n = nfree + npages + s_count[YANK] + s_count[UNDO]
        text_max = n
        if n > stream_min
            text_max = n - stream_min
        if text_max as uword > $fffe / page_size + 8
            text_max = lsb($fffe / page_size + 8)
        capacity = $fffe
        if text_max < $fffe / page_size
            capacity = text_max * page_size
    }

    ; empty the text: one empty page
    sub clear() {
        while npages != 0 {
            npages--
            free_id[nfree] = page_id[npages]
            nfree++
        }
        nfree--
        page_id[0] = free_id[nfree]
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
        s_free(UNDO)
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

    ; the address of position in its page (which becomes cur), until the
    ; next pagemem.map()
    private sub page_at(uword position) -> uword {
        find_page(position)
        return pagemem.map(page_id[cur]) + position - cur_start
    }

    ; page k got count more bytes, lines more of them line endings (both
    ; may be negative: 0 - n)
    private sub grow(ubyte k, uword count, uword lines) {
        page_len[k] += count
        page_lines[k] += lines
    }

    ; copy count bytes from src to dest, also when they overlap
    alias move_bytes = fastmem.move

    ; the number of lines_eol in count bytes at p
    private sub count_eol(uword p, uword count) -> uword {
        return fastmem.count(p, count, lines_eol)
    }

    ; count the lines in every page again if eol changed
    private sub count_lines() {
        ubyte i
        if lines_eol == eol
            return
        lines_eol = eol
        for i in 0 to npages - 1
            page_lines[i] = count_eol(pagemem.map(page_id[i]), page_len[i])
    }

    ; put a free page into the text as page k, empty
    private sub new_page(ubyte k) {
        ubyte i = npages
        while i != k {
            page_id[i] = page_id[i - 1]
            page_len[i] = page_len[i - 1]
            page_lines[i] = page_lines[i - 1]
            i--
        }
        nfree--
        page_id[k] = free_id[nfree]
        page_len[k] = 0
        page_lines[k] = 0
        npages++
        forget_page()
    }

    ; take page k out of the text (it should be empty)
    private sub drop_page(ubyte k) {
        free_id[nfree] = page_id[k]
        nfree++
        npages--
        while k != npages {
            page_id[k] = page_id[k + 1]
            page_len[k] = page_len[k + 1]
            page_lines[k] = page_lines[k + 1]
            k++
        }
        forget_page()
    }

    ; move count bytes from page k to the page next to it, j: the last
    ; bytes to the start of the page after, or the first bytes to the end
    ; of the page before.  through bounce, a piece at a time.
    private sub move_over(ubyte k, ubyte j, uword count) {
        uword src = 0
        uword dest = page_len[j]
        uword lines = 0
        uword p
        uword n
        if j > k {
            ; room at the start of page j
            src = page_len[k] - count
            dest = 0
            p = pagemem.map(page_id[j])
            move_bytes(p, p + count, page_len[j])
            pagemem.changed()
        }
        n = count
        while n != 0 {
            if n > BOUNCE_SIZE
                n = BOUNCE_SIZE
            sys.memcopy(pagemem.map(page_id[k]) + src, bounce, n)
            lines += count_eol(bounce, n)
            sys.memcopy(bounce, pagemem.map(page_id[j]) + dest, n)
            pagemem.changed()
            src += n
            dest += n
            n = count - src
            if j > k
                n = page_len[k] - src
        }
        if j < k {
            ; close the start of page k
            p = pagemem.map(page_id[k])
            move_bytes(p + count, p, page_len[k] - count)
            pagemem.changed()
        }
        grow(k, 0 - count, 0 - lines)
        grow(j, count, lines)
        forget_page()
    }

    ; make cur a page to insert at position into, with room for at least
    ; one byte, and return the address of position in it.  there must be
    ; room somewhere (free() != 0).
    private sub room_at(uword position) -> uword {
        repeat {
            find_page(position)
            if page_len[cur] != page_size
                break
            ; at the start of a full page: the end of the page before
            if position == cur_start and cur != 0 and page_len[cur - 1] != page_size {
                cur--
                cur_start -= page_len[cur]
                break
            }
            make_room(position)
        }
        return pagemem.map(page_id[cur]) + position - cur_start
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
                    move_over(k, k + 1, page_len[k] - offset)
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
            count = page_size - page_len[j]
            if count > page_len[k] - offset
                count = page_len[k] - offset
            while j != k {
                j--
                move_over(j, j + 1, count)
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
        count = page_size - page_len[j]
        if count > offset
            count = offset
        while j != k {
            j++
            move_over(j, j - 1, count)
        }
    }

    ; merge page k with the page after it if both together are small
    private sub merge(ubyte k) {
        if k + 1 < npages and page_len[k] + page_len[k + 1] <= page_size - page_size / 4 {
            move_over(k + 1, k, page_len[k + 1])
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
        return @(page_at(offset))
    }

    ; overwrite the character at offset (for overtype / replace).
    ; returns false past the end of the text.
    sub set(uword offset, ubyte value) -> bool {
        uword p
        if offset >= bufend
            return false
        log_change('s', offset, 1)
        p = page_at(offset)
        if @(p) == lines_eol
            page_lines[cur]--
        if value == lines_eol
            page_lines[cur]++
        @(p) = value
        pagemem.changed()
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
            p = room_at(position)
            n = page_size - page_len[cur]
            if n > count
                n = count
            move_bytes(p, p + n, page_len[cur] - (position - cur_start))
            sys.memcopy(src, p, n)
            pagemem.changed()
            grow(cur, n, count_eol(p, n))
            bufend += n
            log_change('i', position, n)
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
        if nfree != 0 and page_len[k] > page_size / 2 {
            ; little room in this page: a new page at position, or after
            ; it with the bytes after position (then the next read goes
            ; into the start of that)
            if offset == 0
                new_page(k)
            else {
                new_page(k + 1)
                if offset == page_len[k] {
                    k++
                    offset = 0
                } else
                    move_over(k, k + 1, page_len[k] - offset)
            }
        } else {
            void room_at(position)
            k = cur
            offset = position - cur_start
        }
        ; the room is at position: the rest of the page moves to its end
        read_page = k
        read_off = offset
        read_size = page_size - page_len[k]
        ; (no more than the text can grow: positions are uwords)
        if read_size > capacity - bufend
            read_size = capacity - bufend
        p = pagemem.map(page_id[k]) + offset
        move_bytes(p, p + read_size, page_len[k] - offset)
        pagemem.changed()
        return p, read_size
    }

    ; count bytes were written at read_room(), make them part of the text
    sub read_done(uword count) {
        uword p
        if read_size == 0
            return
        ; (the line counts are for eol: the editor may have just set it, at
        ; the start of reading a file into an empty text)
        count_lines()
        if count > read_size
            count = read_size
        ; close the room: the rest of the page moves back
        p = pagemem.map(page_id[read_page]) + read_off
        move_bytes(p + read_size, p + count, page_len[read_page] - read_off)
        pagemem.changed()
        read_size = 0
        if count != 0 {
            grow(read_page, count, count_eol(p, count))
            bufend += count
            log_change('i', read_pos, count)
            note_change(read_pos, count, 0)
            marks_inserted(read_pos, count)
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
        uword lines
        uword left
        uword n
        uword p
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        left = count
        while left != 0 {
            find_page(position)
            n = page_len[cur] - (position - cur_start)
            if n > left
                n = left
            log_change('d', position, n)
            p = page_at(position)
            lines = count_eol(p, n)
            move_bytes(p + n, p, page_len[cur] - (position - cur_start) - n)
            pagemem.changed()
            grow(cur, 0 - n, 0 - lines)
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
        uword p
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        left = count
        while left != 0 {
            p = page_at(position)
            n = page_len[cur] - (position - cur_start)
            if n > left
                n = left
            sys.memcopy(p, dest, n)
            dest += n
            position += n
            left -= n
        }
        return count
    }

    ; the text in pieces, to go through all of it in order without
    ; moving it (saving, translating): chunk(0) to chunk(chunks() - 1)
    ; return the ram address and length of each piece, one per page.  the
    ; bytes may be changed in place, but not their number, and a piece is
    ; only there until the store is used again.
    sub chunks() -> ubyte {
        return npages
    }

    sub chunk(ubyte n) -> pointer, uword {
        uword p = pagemem.map(page_id[n])
        ; (the caller may change the bytes, line endings too)
        pagemem.changed()
        lines_eol = 0
        return p, page_len[n]
    }

    ; the same, for reading only (saving): the page isn't marked changed,
    ; so it isn't written back (to the REU, or the disk in the disk build)
    ; and the line counts stay
    sub chunk_read(ubyte n) -> pointer, uword {
        return pagemem.map(page_id[n]), page_len[n]
    }

    ;
    ; streams: bytes in pages outside the text, for the yank buffer and the
    ; undo log.  a stream takes free pages as it grows, but leaves the text
    ; as many as it may still need (up to text_max): so an insert still
    ; fits whenever free() says so.
    ;

    ; free pages the text may still need
    private sub reserved() -> ubyte {
        if npages >= text_max
            return 0
        return text_max - npages
    }

    ; give stream s pages for end bytes, more or fewer.  returns false if
    ; there aren't enough (it may have more pages then, its bytes are kept)
    private sub s_size(ubyte s, uword end) -> bool {
        uword need = 0
        if end != 0
            need = ((end - 1) >> page_shift) + 1
        if need > STREAM_PAGES
            return false
        while s_count[s] > need {
            s_count[s]--
            free_id[nfree] = s_page[s * STREAM_PAGES + s_count[s]]
            nfree++
        }
        while s_count[s] < need {
            if nfree <= reserved()
                return false
            nfree--
            s_page[s * STREAM_PAGES + s_count[s]] = free_id[nfree]
            s_count[s]++
        }
        return true
    }

    ; give back all pages of stream s
    private sub s_free(ubyte s) {
        void s_size(s, 0)
    }

    ; the address of byte offset of stream s, until the next pagemem.map()
    private sub s_at(ubyte s, uword offset) -> uword {
        return pagemem.map(s_page[s * STREAM_PAGES + lsb(offset >> page_shift)]) + (offset & (page_size - 1))
    }

    ; copy count bytes between mem and stream s at offset: into the stream
    ; if write, out of it if not
    private sub s_copy(ubyte s, uword offset, uword mem, uword count, bool write) {
        uword n
        uword p
        while count != 0 {
            p = s_at(s, offset)
            n = page_size - (offset & (page_size - 1))
            if n > count
                n = count
            if write {
                sys.memcopy(mem, p, n)
                pagemem.changed()
            } else
                sys.memcopy(p, mem, n)
            offset += n
            mem += n
            count -= n
        }
    }

    private sub s_peek(ubyte s, uword offset) -> ubyte {
        return @(s_at(s, offset))
    }

    private sub s_poke(ubyte s, uword offset, ubyte value) {
        @(s_at(s, offset)) = value
        pagemem.changed()
    }

    private sub s_peekw(ubyte s, uword offset) -> uword {
        s_copy(s, offset, &s_word as uword, 2, false)
        return s_word
    }

    private sub s_pokew(ubyte s, uword offset, uword value) {
        s_word = value
        s_copy(s, offset, &s_word as uword, 2, true)
    }

    ;
    ; the yank buffer, in stream YANK
    ;

    ; copy count bytes of text at start into the yank buffer, with a line
    ; ending after them if lines is set and they don't end with one.
    ; returns false (and keeps what was in it) if they don't fit.
    sub yank(uword start, uword count, bool lines) -> bool {
        uword done = 0
        uword n
        if count > yank_size - 1 or not s_size(YANK, count + 1)
            return false
        while done != count {
            n = count - done
            if n > BOUNCE_SIZE
                n = BOUNCE_SIZE
            void copy_out(start + done, n, bounce)
            s_copy(YANK, done, bounce, n, true)
            done += n
        }
        yank_len = count
        if lines and (yank_len == 0 or s_peek(YANK, yank_len - 1) != eol) {
            s_poke(YANK, yank_len, eol)
            yank_len++
        }
        return true
    }

    ; insert the yank buffer at position.  returns false (and inserts
    ; nothing) if it doesn't fit.
    sub put(uword position) -> bool {
        uword done = 0
        uword n
        if yank_len > capacity - bufend
            return false
        while done != yank_len {
            n = yank_len - done
            if n > BOUNCE_SIZE
                n = BOUNCE_SIZE
            s_copy(YANK, done, put_buf, n, false)
            void insert_bytes(put_buf, n, position + done)
            done += n
        }
        return true
    }

    ;
    ; the undo log (see buffer.p8), in stream UNDO
    ;

    ; log a change of count bytes of text at position: after inserting
    ; them ('i'), before deleting ('d') or changing ('s') them.  (maps
    ; other pages)
    private sub log_change(ubyte kind, uword position, uword count) {
        uword start
        uword last_pos
        uword last_count
        if undo_size == 0 or undo_off
            return
        if undo_new {
            undo_new = false
            undo_len = 0
            undo_lost = false
            undo_reversed = false
            s_free(UNDO)
        }
        if undo_lost
            return
        if undo_len != 0 and s_peek(UNDO, undo_len - 1) == 'i' {
            last_count = s_peekw(UNDO, undo_len - 3)
            last_pos = s_peekw(UNDO, undo_len - 5)
            start = undo_len - 7 - last_count
            ; typing on after the last insert: make that insert longer
            if kind == 'i' and position == last_pos + last_count and undo_len + count <= undo_size {
                if log_text(undo_len - 5, position, count)
                    put_record(start, last_count + count, last_pos, 'i')
                return
            }
            ; deleting the end of what the last insert added: make it shorter
            if kind == 'd' and position >= last_pos and position + count == last_pos + last_count {
                last_count -= count
                undo_len = start
                if last_count != 0
                    put_record(start, last_count, last_pos, 'i')
                return
            }
        }
        if count > undo_size - undo_len or undo_size - undo_len - count < 7 {
            undo_lost = true
            return
        }
        if log_text(undo_len + 2, position, count)
            put_record(undo_len, count, position, kind)
    }

    ; copy count bytes of text at position into the log at offset, with
    ; room for a record's end after them.  false (and the change is lost)
    ; if there are no pages for it.
    private sub log_text(uword offset, uword position, uword count) -> bool {
        uword n
        if not s_size(UNDO, offset + count + 5) {
            undo_lost = true
            return false
        }
        while count != 0 {
            n = count
            if n > BOUNCE_SIZE
                n = BOUNCE_SIZE
            void copy_out(position, n, bounce)
            s_copy(UNDO, offset, bounce, n, true)
            offset += n
            position += n
            count -= n
        }
        return true
    }

    ; write the rest of the record whose count data bytes follow start:
    ; the count before the data, the position, count and kind after it.
    ; the log ends after the record.
    private sub put_record(uword start, uword count, uword position, ubyte kind) {
        s_pokew(UNDO, start, count)
        start += count + 2
        s_pokew(UNDO, start, position)
        s_pokew(UNDO, start + 2, count)
        s_poke(UNDO, start + 4, kind)
        undo_len = start + 5
    }

    ; revert the logged change (or re-do it, if it was just undone).
    ; returns the lowest position changed, or NONE if there is nothing to undo.
    sub undo() -> uword {
        uword lowest = NONE
        uword at
        uword count
        uword position
        if not can_undo()
            return NONE
        undo_off = true
        if undo_reversed {
            ; re-do: the records in the order they were made
            at = 0
            while at < undo_len {
                count = s_peekw(UNDO, at)
                position = s_peekw(UNDO, at + count + 2)
                undo_record(at + count + 7, count, position)
                lowest = min(lowest, position)
                at += count + 7
            }
        } else {
            ; undo: the last record first
            at = undo_len
            while at != 0 {
                count = s_peekw(UNDO, at - 3)
                position = s_peekw(UNDO, at - 5)
                undo_record(at, count, position)
                lowest = min(lowest, position)
                at -= count + 7
            }
        }
        undo_off = false
        undo_reversed = not undo_reversed
        undo_new = false
        return lowest
    }

    ; apply the opposite of the record ending at end, and turn the record
    ; into that opposite so the next undo() reverses it again
    private sub undo_record(uword end, uword count, uword position) {
        uword data = end - 5 - count
        uword done = 0
        uword n
        ubyte old
        when s_peek(UNDO, end - 1) {
            'i' -> {
                void delete_nchar(count, position)
                s_poke(UNDO, end - 1, 'd')
            }
            'd' -> {
                while done != count {
                    n = count - done
                    if n > BOUNCE_SIZE
                        n = BOUNCE_SIZE
                    s_copy(UNDO, data + done, put_buf, n, false)
                    void insert_bytes(put_buf, n, position + done)
                    done += n
                }
                s_poke(UNDO, end - 1, 'i')
            }
            's' -> {
                old = get(position)
                void set(position, s_peek(UNDO, data))
                s_poke(UNDO, data, old)
            }
        }
    }

    ;
    ; recovery after a crash or a reset (docs/XMEM-DESIGN.md): pagemem has
    ; two header slots, each can describe a text: its page table, length,
    ; cursor and the editor's data (meta).  a text found at startup waits
    ; for recover(), and its pages are left alone.  the session writes its
    ; own header with sync(), into a free slot, or the recovered text's, or
    ; (if two texts wait) the older text's, which is dropped then.
    ;

    const ubyte META_SIZE = 48
    const ubyte NO_SLOT = 255
    const ubyte HEADER_VERSION = 1
    ; a header: the fixed part (H_IDS bytes), then the page ids, the low
    ; bytes of the page lengths, the high bytes, and a checksum
    const ubyte H_STATE = 5         ; 1: in use, 0: clean
    const ubyte H_SEQ = 6           ; the newer text has the higher one
    const ubyte H_PAGE_SIZE = 8
    const ubyte H_LENGTH = 10
    const ubyte H_NPAGES = 12
    const ubyte H_CURSOR = 13
    const ubyte H_META = 16
    const ubyte H_IDS = 64
    private ^^ubyte hdr                     ; H_IDS bytes

    private ubyte session_slot = NO_SLOT    ; the slot sync() writes, NO_SLOT: none
    private uword session_seq
    uword synced_changes            ; changes at the last sync()
    ubyte recoverable               ; texts waiting
    private bool[2] waiting                 ; per slot: a text waits there
    ; (@nosplit: comparing two elements of a split array doesn't assemble,
    ; see bugs/split_array_compare_elements.p8)
    private uword[2] @nosplit slot_seq
    private ubyte[2] slot_pages
    private ^^ubyte held                    ; (init) 32 bytes, a bit per page: a waiting text's
    private uword checksum

    ; find the texts to recover and keep their pages (bits in held)
    private sub find_texts(ubyte n) {
        ubyte h
        ubyte i
        session_seq = 0
        for h in 0 to 1 {
            waiting[h] = read_header(h, n)
            if waiting[h] {
                recoverable++
                if slot_seq[h] >= session_seq
                    session_seq = slot_seq[h] + 1
                ; (read_header left its page ids in page_id)
                for i in 0 to slot_pages[h] - 1
                    held[page_id[i] >> 3] |= 1 << (page_id[i] & 7)
            }
        }
    }

    ; give the session a header slot if it has none: a free one, or the
    ; older text's (which is dropped)
    private sub take_slot() {
        if session_slot != NO_SLOT
            return
        session_slot = 0
        if waiting[0] {
            session_slot = 1
            if waiting[1] and slot_seq[0] < slot_seq[1]
                session_slot = 0
        }
        drop_text(session_slot)
    }

    ; whether header slot h holds a text to recover, with pages below n
    private sub read_header(ubyte h, ubyte n) -> bool {
        ubyte np
        ubyte i
        uword piece
        pagemem.header_get(h, 0, hdr, H_IDS)
        if hdr[0] != 'p' or hdr[1] != '8' or hdr[2] != 'v' or hdr[3] != 'i' or hdr[4] != HEADER_VERSION
            return false
        np = hdr[H_NPAGES]
        if hdr[H_STATE] != 1 or peekw(hdr + H_PAGE_SIZE) != page_size or np == 0
            return false
        ; the page table (into page_id: at init the text has no pages yet;
        ; the lengths are checked with the checksum only)
        checksum = 0
        add_sum(hdr, H_IDS)
        header_table(h, np, false)
        for i in 0 to np - 1 {
            if page_id[i] >= n
                return false
        }
        pagemem.header_get(h, H_IDS + 3 * np as uword, &piece as uword, 2)
        if piece != checksum
            return false
        slot_seq[h] = peekw(hdr + H_SEQ)
        slot_pages[h] = np
        return true
    }

    ; the page table, np pages, to header slot h (write) or from it: the
    ; page ids (page_id), the low bytes of the lengths (put_buf) and the
    ; high bytes (bounce), each added to checksum
    private sub header_table(ubyte h, ubyte np, bool write) {
        uword offset = H_IDS
        uword p = &page_id as uword
        repeat 3 {
            if write
                pagemem.header_put(h, offset, p, np)
            else
                pagemem.header_get(h, offset, p, np)
            add_sum(p, np)
            offset += np
            if p == (&page_id as uword)
                p = put_buf as uword
            else
                p = bounce as uword
        }
    }

    ; add count bytes at p to checksum
    private sub add_sum(uword p, uword count) {
        repeat count {
            checksum = (checksum << 1) + (checksum >> 15) + @(p)
            p++
        }
    }

    ; header slot h no longer holds a text to recover (marked clean); a
    ; text waiting there is dropped and its pages are free
    private sub drop_text(ubyte h) {
        ubyte clean = 0
        ubyte i
        if waiting[h] {
            waiting[h] = false
            recoverable--
            pagemem.header_get(h, H_IDS, bounce, slot_pages[h])
            for i in 0 to slot_pages[h] - 1 {
                free_id[nfree] = bounce[i]
                nfree++
            }
            set_text_max()
        }
        pagemem.header_put(h, H_STATE, &clean as uword, 1)
    }

    ; write the text's header (and first its pages, if they are copies),
    ; with META_SIZE bytes of the editor's at meta, unless nothing changed
    ; since the last time.  afterwards the text can be recovered as it is.
    sub sync(uword meta) {
        ubyte i
        if changes == synced_changes
            return
        if not pagemem.persistent {
            ; nothing is kept, but the editor asks when the keys stop, and
            ; would ask again on every pass of its key loop
            synced_changes = changes
            return
        }
        take_slot()
        pagemem.sync()
        hdr[0] = 'p'
        hdr[1] = '8'
        hdr[2] = 'v'
        hdr[3] = 'i'
        hdr[4] = HEADER_VERSION
        hdr[H_STATE] = 1
        pokew(hdr + H_SEQ, session_seq)
        pokew(hdr + H_PAGE_SIZE, page_size)
        pokew(hdr + H_LENGTH, bufend)
        hdr[H_NPAGES] = npages
        pokew(hdr + H_CURSOR, marks[0])
        sys.memcopy(meta, hdr + H_META, META_SIZE)
        ; the lengths: low bytes in put_buf, high bytes in bounce
        for i in 0 to npages - 1 {
            put_buf[i] = lsb(page_len[i])
            bounce[i] = msb(page_len[i])
        }
        checksum = 0
        add_sum(hdr, H_IDS)
        pagemem.header_put(session_slot, 0, hdr, H_IDS)
        header_table(session_slot, npages, true)
        pagemem.header_put(session_slot, H_IDS + 3 * npages as uword, &checksum as uword, 2)
        synced_changes = changes
    }

    ; the text needn't be recovered (when the editor quits)
    sub clean() {
        if session_slot != NO_SLOT
            drop_text(session_slot)
    }

    ; replace the text with the newest one waiting, and its META_SIZE bytes
    ; of the editor's data to meta.  the cursor is where it was; the text
    ; counts as changed.  returns false if no text waits.
    sub recover(uword meta) -> bool {
        ubyte h = NO_SLOT
        ubyte np
        ubyte i
        if waiting[0]
            h = 0
        if waiting[1] and (h == NO_SLOT or slot_seq[1] > slot_seq[0])
            h = 1
        if h == NO_SLOT
            return false
        ; the session's header described the text that goes now; the
        ; session takes the recovered text's slot
        if session_slot != NO_SLOT
            drop_text(session_slot)
        session_slot = h
        waiting[h] = false
        recoverable--
        ; the text's pages are free now
        while npages != 0 {
            npages--
            free_id[nfree] = page_id[npages]
            nfree++
        }
        pagemem.header_get(h, 0, hdr, H_IDS)
        np = hdr[H_NPAGES]
        header_table(h, np, false)
        for i in 0 to np - 1
            page_len[i] = mkword(bounce[i], put_buf[i])
        npages = np
        bufend = peekw(hdr + H_LENGTH)
        sys.memcopy(hdr + H_META, meta, META_SIZE)
        ; (the line endings are counted again)
        lines_eol = 0
        forget_page()
        set_text_max()
        void loaded(bufend)
        marks[0] = min(peekw(hdr + H_CURSOR), bufend)
        modified = true
        changes++
        sync(meta)
        return true
    }

    ;
    ; searching
    ;

    ; returns the offset of the first value at or after position and
    ; before limit (limit is clamped to the end of the text).
    ; returns limit if it is not found.
    sub find_next(ubyte value, uword position, uword limit) -> uword {
        uword end
        if limit > bufend
            limit = bufend
        ; a page at a time (to its end: limit is checked after)
        while position < limit {
            find_page(position)
            end = cur_start + page_len[cur]
            position += fastmem.find(pagemem.map(page_id[cur]) + position - cur_start, end - position, value)
            if position != end
                break
        }
        if position > limit
            position = limit
        return position
    }

    ; returns the offset of the last value before position, or NONE.
    sub find_prev(ubyte value, uword position) -> uword {
        uword found
        if position > bufend
            position = bufend
        ; a page at a time, from the end
        while position != 0 {
            find_page(position - 1)
            found = fastmem.find_back(pagemem.map(page_id[cur]), position - cur_start, value)
            if found != NONE
                return cur_start + found
            position = cur_start
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
                ; the line-th eol in this page ends the line before.  (each
                ; search is found within the page: page_lines counts them)
                p = pagemem.map(page_id[k])
                repeat {
                    p += fastmem.find(p, page_len[k], eol)
                    line--
                    if line == 0
                        return start + p - pagemem.last_addr + 1
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
        return line + count_eol(pagemem.map(page_id[k]), position - start)
    }


    ;
    ; for the tests (the editor doesn't call these, so they are left out of
    ; its builds)
    ;

    ; the pages the text is in
    sub pages() -> ubyte {
        return npages
    }

    ; the pages stream s (YANK or UNDO) has
    sub stream_pages(ubyte s) -> ubyte {
        return s_count[s]
    }

    ; the pages kept for texts waiting to be recovered
    sub held_pages() -> ubyte {
        ubyte n = 0
        if waiting[0]
            n += slot_pages[0]
        if waiting[1]
            n += slot_pages[1]
        return n
    }

    ; the header slot the session writes (NO_SLOT: none yet)
    sub header_slot() -> ubyte {
        return session_slot
    }

    ; the page store's invariants: page lengths add up and fit, only an
    ; empty text has an empty page, the line counts are right, the pages
    ; read in order are the text get() gives, and no page is lost.
    ; returns what is wrong, or "".
    sub check() -> str {
        ubyte k
        ubyte j
        uword start = 0
        uword i
        uword n
        uword lines
        if npages == 0
            return "no pages"
        for k in 0 to npages - 1 {
            if page_len[k] > page_size
                return "page too long"
            if page_len[k] == 0 and npages != 1
                return "empty page"
            lines = 0
            i = 0
            while i != page_len[k] {
                ; (a copy: get() maps other pages)
                n = page_len[k] - i
                if n > BOUNCE_SIZE
                    n = BOUNCE_SIZE
                sys.memcopy(pagemem.map(page_id[k]) + i, bounce, n)
                for j in 0 to lsb(n) - 1 {
                    if bounce[j] != get(start + i + j)
                        return "page bytes"
                    if bounce[j] == lines_eol
                        lines++
                }
                i += n
            }
            if lines_eol != 0 and lines != page_lines[k]
                return "page lines"
            start += page_len[k]
        }
        if start != bufend
            return "page lengths"
        if npages + nfree + s_count[YANK] + s_count[UNDO] + held_pages() != total_pages
            return "pages lost"
        return ""
    }

} ; end of buffer block (page store)
