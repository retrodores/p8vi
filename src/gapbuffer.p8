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
;     point == gapstart - ramstart  (after any move/insert/delete)
;
; Buffer offsets (bufstart, bufend, point, positions) are zero relative
; and never include the gap.  All positions passed in are clamped to
; 0..bufend.
gapbuffer {
    ; ram address based coordinates
    uword ramstart  ; start of buffer ram (at end of program code to IO generally)
    uword ramtop    ; never moves, basically MEMTOP (aka 1 byte past last usable)
    uword lastbyte  ; last usable byte (top-1)

    ; zero relative buffer coordinates
    uword bufstart  ; always 0, start of the text
    uword bufend    ; length of the text (1 past the last character)
    uword bufsize   ; bufend - bufstart

    ; zero relative buffer coordinate of insertion point
    uword point     ; linear cursor / insertion point, does not include gap buffer

    ; gap buffer coordinates are ram addresses
    uword gapstart  ; first byte of the gap, moves
    uword gapend    ; last byte of the gap (inclusive), moves
    uword gapsize   ; current size of the gap, also the free memory

    ; set ramstart to the end of the program and empty the buffer.
    ; ramtop must already be set (normally by platform.init)
    sub init() {
        ramstart = sys.progend()
        clear()
    }

    ; empty the buffer, the gap becomes all of ramstart..ramtop-1
    sub clear() {
        bufstart = 0
        bufend = 0
        bufsize = 0
        point = 0
        gapstart = ramstart
        gapend = ramtop - 1
        gapsize = ramtop - ramstart
    }

    ; call after placing count bytes of text at ramstart (e.g. a file load).
    ; the gap is placed after the text.  returns false if it can't fit.
    sub loaded(uword count) -> bool {
        if count > ramtop - ramstart
            return false
        bufend = count
        bufsize = count
        point = count
        gapstart = ramstart + count
        gapend = ramtop - 1
        gapsize = ramtop - gapstart
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

    ; move the gap left so it starts at ram address target
    ; text between target and gapstart moves to just after the gap.
    ; copies in chunks no larger than the gap so they never overlap.
    sub left(uword position) {
        uword target = point2ram(position)
        uword n
        if gapsize == 0 {
            ; no gap: ram and buffer coordinates are the same
            gapstart = target
            gapend = target - 1
            return
        }
        while gapstart > target {
            n = min(gapstart - target, gapsize)
            gapstart -= n
            gapend -= n
            sys.memcopy(gapstart, gapend + 1, n)
        }
    }

    ; move the gap right so it starts at ram address target
    ; text between the gap and target moves to just before the gap.
    sub right(uword position) {
        uword target = point2ram(position)
        uword n
        if gapsize == 0 {
            gapstart = target
            gapend = target - 1
            return
        }
        while gapstart < target {
            n = min(target - gapstart, gapsize)
            sys.memcopy(gapend + 1, gapstart, n)
            gapstart += n
            gapend += n
        }
    }

    ; move the gap (and point) to position, clamped to the end of the text
    sub move_cursor(uword position) {
        if position > bufend
            position = bufend
        if point2ram(position) < gapstart
            left(position)
        else if point2ram(position) > gapstart
            right(position)
        point = position
    }

    ; delete the character at position (like vi 'x').
    ; the gap moves to position and absorbs the character after it.
    ; returns false if there is no character at position.
    sub delete_char(uword position) -> bool {
        if position >= bufend
            return false
        move_cursor(position)
        gapend++
        gapsize++
        bufend--
        bufsize--
        return true
    }

    ; delete up to count characters starting at position.
    ; returns the number of characters actually deleted.
    sub delete_nchar(uword count, uword position) -> uword {
        if position >= bufend
            return 0
        if count > bufend - position
            count = bufend - position
        move_cursor(position)
        gapend += count
        gapsize += count
        bufend -= count
        bufsize -= count
        return count
    }

    ; insert a character at position, point ends up after it.
    ; returns false if the buffer is full.
    sub insert_char(ubyte input, uword position) -> bool {
        if gapsize == 0
            return false
        move_cursor(position)
        @(gapstart) = input
        gapstart++
        gapsize--
        point++
        bufend++
        bufsize++
        return true
    }

    ; insert a string at position, point ends up after it.
    ; returns false (and inserts nothing) if it doesn't fit.
    sub insert(str input, uword position) -> bool {
        ubyte input_len = strings.length(input)
        if input_len as uword > gapsize
            return false
        move_cursor(position)
        sys.memcopy(input, gapstart, input_len)
        gapstart += input_len
        gapsize -= input_len
        point += input_len
        bufend += input_len
        bufsize += input_len
        return true
    }

    ; returns the *ram* address of the character at buffer offset bufaddr
    ; skipping over the gap if needed.
    sub buffer2ram(uword bufaddr) -> uword {
        uword temp = ramstart + bufaddr
        if temp < gapstart
            return temp
        return temp + gapsize
    }

    ; returns the ram address gapstart has when the gap is at position.
    ; text before the gap is not shifted, so no adjustment is needed.
    sub point2ram(uword position) -> uword {
        return ramstart + position
    }

    ; returns the ram address one past the last byte of text, which
    ; is always ramtop since the text after the gap is kept against it.
    sub ramend() -> uword {
        return ramstart + bufend + gapsize
    }

} ; end of gapbuffer block
