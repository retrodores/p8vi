; Contains the Gap Buffer, various variables and routines.
; Could become a struct allowing multiple buffers.
;
; Memory layout (ram addresses):
;
;   ramstart           gapstart        gapend          ramtop
;   |  text before gap  |      gap      |  text after gap |
;
; - The gap is all of the free memory, so text always ends at ramtop
;   and the buffer never needs to "grow".  free() is simply gapsize.
; - gapend is *inclusive* (last byte of the gap), so an empty gap
;   has gapend == gapstart - 1.
; - Invariants kept by every routine:
;     gapsize == gapend - gapstart + 1
;     bufend + gapsize == ramtop - ramstart
;     gappos == gapstart - ramstart
;
; Buffer offsets (bufend, gappos, positions, marks) are zero relative
; and never include the gap.  All positions passed in are clamped to
; 0..bufend.
;
; The gap position is internal: editors keep their cursor (and the top
; of the screen etc.) in marks, which are adjusted by inserts and deletes.
; The variables below should be treated as read-only outside this block.
gapbuffer {
    ; returned by searches and line routines when there is no result
    const uword NONE = $ffff
    ; marks are positions that move along with inserts and deletes
    const ubyte NUM_MARKS = 4

    ; ram address based coordinates
    pointer ramstart  ; start of buffer ram
    pointer ramtop    ; 1 byte past the last usable byte

    ; zero relative buffer coordinates
    uword bufend    ; length of the text (1 past the last character)
    uword gappos    ; buffer offset of the gap

    ; gap buffer coordinates are ram addresses
    pointer gapstart  ; first byte of the gap, moves
    pointer gapend    ; last byte of the gap (inclusive), moves
    uword gapsize     ; current size of the gap, also the free memory

    ; line ending character used by the line routines
    ubyte eol = $0d

    ; set by every change to the text, cleared by loaded() / clear().
    ; the editor clears it after saving.
    bool modified

    uword[NUM_MARKS] marks

    ; undo log for one change (see undo_init); disabled while undo_size is 0
    pointer undo_buf
    uword undo_size
    uword undo_len          ; bytes used
    bool undo_new           ; the next change starts a new log
    bool undo_lost          ; the change didn't fit, it can't be undone
    bool undo_reversed      ; the log was undone, undoing again redoes it
    bool undo_off           ; not logging (while undoing)

    ; use the memory from start up to (not including) top and empty the buffer
    sub init(pointer start, pointer top) {
        ramstart = start
        ramtop = top
        clear()
    }

    ; empty the buffer, the gap becomes all of ramstart..ramtop-1
    sub clear() {
        void loaded(0)
    }

    ; call after placing count bytes of text at ramstart (e.g. a file load).
    ; the gap is placed after the text and all marks are reset to 0.
    ; returns false if it can't fit.
    sub loaded(uword count) -> bool {
        ubyte i
        if count > ramtop - ramstart
            return false
        bufend = count
        gappos = count
        gapstart = ramstart + count
        gapend = ramtop - 1
        gapsize = (ramtop - gapstart) as uword
        for i in 0 to NUM_MARKS - 1
            marks[i] = 0
        modified = false
        undo_len = 0
        undo_lost = false
        return true
    }

    ; returns free memory
    sub free() -> uword {
        return gapsize
    }

    ; returns the length of the text
    sub length() -> uword {
        return bufend
    }

    ; get the character at a specific offset
    ; returns 0 for offsets past the end of the text
    sub get(uword offset) -> ubyte {
        if offset >= bufend
            return 0
        return @(buffer2ram(offset))
    }

    ; overwrite the character at offset (for overtype / replace).
    ; the gap does not move.  returns false past the end of the text.
    sub set(uword offset, ubyte value) -> bool {
        pointer p
        if offset >= bufend
            return false
        p = buffer2ram(offset)
        log_change('s', offset, p, 1)
        @(p) = value
        modified = true
        return true
    }

    ;
    ; marks
    ;

    ; set mark m to position (clamped to the end of the text)
    sub set_mark(ubyte m, uword position) {
        if position > bufend
            position = bufend
        marks[m] = position
    }

    sub get_mark(ubyte m) -> uword {
        return marks[m]
    }

    ; count bytes were inserted at position: marks after it move right.
    ; a mark exactly at position stays, so text inserted there ends up after it.
    private sub marks_inserted(uword position, uword count) {
        ubyte i
        for i in 0 to NUM_MARKS - 1 {
            if marks[i] > position
                marks[i] += count
        }
    }

    ; count bytes were deleted at position: marks inside the deleted
    ; range move to position, marks after it move left.
    private sub marks_deleted(uword position, uword count) {
        ubyte i
        for i in 0 to NUM_MARKS - 1 {
            if marks[i] > position {
                if marks[i] - position <= count
                    marks[i] = position
                else
                    marks[i] -= count
            }
        }
    }

    ;
    ; moving the gap
    ;

    ; move the gap to position, clamped to the end of the text.
    ; editing routines do this themselves, it is only needed before
    ; using gap_ptr() or to make segments() return the text in one piece.
    sub move_gap(uword position) {
        if position > bufend
            position = bufend
        if position < gappos
            left(position)
        else if position > gappos
            right(position)
        gappos = position
    }

    ; move the gap left so it starts at buffer offset position.
    ; text between position and gapstart moves to just after the gap.
    ; copies in chunks no larger than the gap so they never overlap.
    private sub left(uword position) {
        pointer target = ramstart + position
        uword n
        if gapsize == 0 {
            ; no gap: ram and buffer coordinates are the same
            gapstart = target
            gapend = target - 1
            return
        }
        while gapstart > target {
            n = min((gapstart - target) as uword, gapsize)
            gapstart -= n
            gapend -= n
            sys.memcopy(gapstart, gapend + 1, n)
        }
    }

    ; move the gap right so it starts at buffer offset position.
    ; text between the gap and position moves to just before the gap.
    private sub right(uword position) {
        pointer target = ramstart + position
        uword n
        if gapsize == 0 {
            gapstart = target
            gapend = target - 1
            return
        }
        while gapstart < target {
            n = min((target - gapstart) as uword, gapsize)
            sys.memcopy(gapend + 1, gapstart, n)
            gapstart += n
            gapend += n
        }
    }

    ;
    ; inserting
    ;

    ; insert a character at position.
    ; returns false if the buffer is full.
    sub insert_char(ubyte input, uword position) -> bool {
        if gapsize == 0
            return false
        move_gap(position)
        @(gapstart) = input
        inserted(1)
        return true
    }

    ; insert a string at position.
    ; returns false (and inserts nothing) if it doesn't fit.
    sub insert(str input, uword position) -> bool {
        return insert_bytes(input, strings.length(input), position)
    }

    ; insert count bytes from src at position, any byte values allowed.
    ; src must not point into the buffer itself (use copy_out first).
    ; returns false (and inserts nothing) if it doesn't fit.
    sub insert_bytes(pointer src, uword count, uword position) -> bool {
        if count > gapsize
            return false
        move_gap(position)
        sys.memcopy(src, gapstart, count)
        inserted(count)
        return true
    }

    ; returns the ram address of the gap, to read data (e.g. a file)
    ; straight into the buffer at the gap position.  at most free() bytes
    ; may be written, then call inserted() with the number written.
    sub gap_ptr() -> pointer {
        return gapstart
    }

    ; count bytes were written at gap_ptr(), make them part of the text.
    sub inserted(uword count) {
        if count > gapsize
            count = gapsize
        if count != 0
            log_change('i', gappos, gapstart, count)
        gapstart += count
        gapsize -= count
        marks_inserted(gappos, count)
        gappos += count
        bufend += count
        if count != 0
            modified = true
    }

    ;
    ; deleting
    ;

    ; delete the character at position (like vi 'x').
    ; returns false if there is no character at position.
    sub delete_char(uword position) -> bool {
        return delete_nchar(1, position) == 1
    }

    ; delete up to count characters starting at position.
    ; returns the number of characters actually deleted.
    sub delete_nchar(uword count, uword position) -> uword {
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        move_gap(position)
        log_change('d', position, gapend + 1, count)
        gapend += count
        gapsize += count
        bufend -= count
        marks_deleted(position, count)
        modified = true
        return count
    }

    ; delete the characters from position start up to (not including) end.
    ; returns the number of characters actually deleted.
    sub delete_range(uword start, uword end) -> uword {
        if end <= start
            return 0
        return delete_nchar(end - start, start)
    }

    ;
    ; undo
    ;
    ; every insert, delete and set() is recorded in the undo log, until
    ; undo_mark() says the next change starts a new log.  so the log holds
    ; one editor command (e.g. a whole insert session).  undo() reverts it,
    ; and undo() again re-does it.  loaded() and clear() empty the log.
    ;
    ; each log record is: count (2 bytes), count data bytes, position
    ; (2 bytes), count (2 bytes) and the kind: 'i' inserted, 'd' deleted,
    ; 's' set (the data is the byte it replaced).  the count at both ends
    ; lets the log be walked in both directions.
    ;

    ; use size bytes at buf for the undo log
    sub undo_init(pointer buf, uword size) {
        undo_buf = buf
        undo_size = size
        undo_len = 0
        undo_lost = false
    }

    ; the next change starts a new undo log (call before each editor command)
    sub undo_mark() {
        undo_new = true
    }

    ; true if there is a change to undo (or redo)
    sub can_undo() -> bool {
        return undo_len != 0 and not undo_lost
    }

    private sub log_change(ubyte kind, uword position, pointer data, uword count) {
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
        }
        if undo_lost
            return
        if undo_len != 0 and undo_buf[undo_len - 1] == 'i' {
            last_count = peekw(undo_buf + undo_len - 3)
            last_pos = peekw(undo_buf + undo_len - 5)
            start = undo_len - 7 - last_count
            ; typing on after the last insert: make that insert longer
            if kind == 'i' and position == last_pos + last_count and undo_len + count <= undo_size {
                sys.memcopy(data, undo_buf + undo_len - 5, count)
                last_count += count
                undo_len += count
                pokew(undo_buf + start, last_count)
                pokew(undo_buf + undo_len - 5, last_pos)
                pokew(undo_buf + undo_len - 3, last_count)
                undo_buf[undo_len - 1] = 'i'
                return
            }
            ; deleting the end of what the last insert added: make it shorter
            if kind == 'd' and position >= last_pos and position + count == last_pos + last_count {
                last_count -= count
                if last_count == 0 {
                    undo_len = start
                } else {
                    undo_len = start + last_count + 7
                    pokew(undo_buf + start, last_count)
                    pokew(undo_buf + undo_len - 5, last_pos)
                    pokew(undo_buf + undo_len - 3, last_count)
                    undo_buf[undo_len - 1] = 'i'
                }
                return
            }
        }
        if count > undo_size - undo_len or undo_size - undo_len - count < 7 {
            undo_lost = true
            return
        }
        pokew(undo_buf + undo_len, count)
        sys.memcopy(data, undo_buf + undo_len + 2, count)
        undo_len += count + 7
        pokew(undo_buf + undo_len - 5, position)
        pokew(undo_buf + undo_len - 3, count)
        undo_buf[undo_len - 1] = kind
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
                count = peekw(undo_buf + at)
                position = peekw(undo_buf + at + count + 2)
                undo_record(at + count + 7, count, position)
                lowest = min(lowest, position)
                at += count + 7
            }
        } else {
            ; undo: the last record first
            at = undo_len
            while at != 0 {
                count = peekw(undo_buf + at - 3)
                position = peekw(undo_buf + at - 5)
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
        pointer data = undo_buf + end - 5 - count
        ubyte old
        when undo_buf[end - 1] {
            'i' -> {
                void delete_nchar(count, position)
                undo_buf[end - 1] = 'd'
            }
            'd' -> {
                void insert_bytes(data, count, position)
                undo_buf[end - 1] = 'i'
            }
            's' -> {
                old = get(position)
                void set(position, @(data))
                @(data) = old
            }
        }
    }

    ;
    ; reading
    ;

    ; copy up to count characters starting at position to dest.
    ; returns the number of characters copied.
    sub copy_out(uword position, uword count, pointer dest) -> uword {
        uword n1 = 0
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        if count == 0
            return 0
        ; part before the gap
        if position < gappos {
            n1 = min(count, gappos - position)
            sys.memcopy(ramstart + position, dest, n1)
        }
        ; part after the gap
        if count > n1
            sys.memcopy(buffer2ram(position + n1), dest + n1, count - n1)
        return count
    }

    ; copy the line (or the next maxlen characters of it) starting at position
    ; to dest, without the line ending, followed by a 0 byte.
    ; dest must have room for maxlen + 1 bytes.
    ; returns the number of characters copied.  if that is maxlen and
    ; get(position + maxlen) is not eol the line continues (wraps).
    sub copy_line(uword position, pointer dest, uword maxlen) -> uword {
        uword limit
        uword n = 0
        if position < bufend {
            if maxlen > bufend - position
                limit = bufend
            else
                limit = position + maxlen
            n = find_next(eol, position, limit) - position
            void copy_out(position, n, dest)
        }
        @(dest + n) = 0
        return n
    }

    ; returns the ram addresses and lengths of the text before and after
    ; the gap, e.g. to save the text without moving the gap.
    ; after move_gap(length()) the second segment is empty.
    sub segments() -> pointer, uword, pointer, uword {
        return ramstart, gappos, gapend + 1, bufend - gappos
    }

    ;
    ; searching
    ;

    ; returns the offset of the first value at or after position and
    ; before limit (limit is clamped to the end of the text).
    ; returns limit if it is not found.
    sub find_next(ubyte value, uword position, uword limit) -> uword {
        pointer p
        uword stop
        if limit > bufend
            limit = bufend
        ; part before the gap
        if position < gappos {
            stop = min(limit, gappos)
            p = ramstart + position
            while position < stop {
                if @(p) == value
                    return position
                p++
                position++
            }
        }
        ; part after the gap
        if position < limit {
            p = buffer2ram(position)
            while position < limit {
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
        pointer p
        if position > bufend
            position = bufend
        ; part after the gap
        if position > gappos {
            p = buffer2ram(position - 1)
            while position > gappos {
                position--
                if @(p) == value
                    return position
                p--
            }
        }
        ; part before the gap
        if position > 0 {
            p = ramstart + position - 1
            while position > 0 {
                position--
                if @(p) == value
                    return position
                p--
            }
        }
        return NONE
    }

    ; true if the count bytes at pattern are in the text at position
    sub match_at(pointer pattern, ubyte count, uword position) -> bool {
        ubyte i
        if count as uword > bufend or position > bufend - count
            return false
        for i in 0 to count - 1 {
            if get(position + i) != pattern[i]
                return false
        }
        return true
    }

    ; returns the offset of the first occurrence of the count bytes at
    ; pattern that starts at or after position and ends at or before limit,
    ; or NONE.  count must be at least 1.
    sub find_bytes(pointer pattern, ubyte count, uword position, uword limit) -> uword {
        if limit > bufend
            limit = bufend
        repeat {
            position = find_next(pattern[0], position, limit)
            if position >= limit
                return NONE
            if position + count <= limit and match_at(pattern, count, position)
                return position
            position++
        }
    }

    ; returns the offset of the last occurrence of the count bytes at
    ; pattern that starts before position, or NONE.  count must be at least 1.
    sub find_bytes_prev(pointer pattern, ubyte count, uword position) -> uword {
        repeat {
            position = find_prev(pattern[0], position)
            if position == NONE
                return NONE
            if match_at(pattern, count, position)
                return position
        }
    }

    ;
    ; lines
    ;
    ; every eol starts a new line, so "a<eol>" is two lines: "a" and "".
    ; line numbers are zero relative.
    ;

    ; returns the offset of the start of the line containing position
    sub line_start(uword position) -> uword {
        uword found = find_prev(eol, position)
        if found == NONE
            return 0
        return found + 1
    }

    ; returns the offset of the eol ending the line containing position,
    ; or the end of the text for the last line
    sub line_end(uword position) -> uword {
        return find_next(eol, position, bufend)
    }

    ; returns the start of the line after the one containing position,
    ; or NONE if it is the last line
    sub next_line(uword position) -> uword {
        uword end = line_end(position)
        if end >= bufend
            return NONE
        return end + 1
    }

    ; returns the start of the line before the one containing position,
    ; or NONE if it is the first line
    sub prev_line(uword position) -> uword {
        uword start = line_start(position)
        if start == 0
            return NONE
        return line_start(start - 1)
    }

    ; returns the start of line number line, or NONE if there aren't
    ; that many lines
    sub line_offset(uword line) -> uword {
        uword position = 0
        while line > 0 {
            position = next_line(position)
            if position == NONE
                return NONE
            line--
        }
        return position
    }

    ; returns the line number of position
    sub line_number(uword position) -> uword {
        uword line = 0
        uword found = 0
        if position > bufend
            position = bufend
        repeat {
            found = find_next(eol, found, position)
            if found >= position
                return line
            line++
            found++
        }
    }

    ;
    ; addresses
    ;

    ; returns the *ram* address of the character at buffer offset bufaddr
    ; skipping over the gap if needed.
    sub buffer2ram(uword bufaddr) -> pointer {
        pointer temp = ramstart + bufaddr
        if temp < gapstart
            return temp
        return temp + gapsize
    }

    ; returns the ram address one past the last byte of text, which
    ; is always ramtop since the text after the gap is kept against it.
    sub ramend() -> pointer {
        return ramstart + bufend + gapsize
    }

} ; end of gapbuffer block
