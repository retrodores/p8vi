; src/postype.p8 for the wide builds (32-bit hosts and the m68k machines):
; text positions, line numbers and counts are long.  The editor core is
; compiled from copies with uword made long (tools/encode_copy.py --wide);
; this file comes first in -srcdirs, before the copy of src/postype.p8.

%import textio
%import conv

pos {
    ; bytes in a position (the undo log's records hold them)
    const ubyte SIZE = 4
    ; no position: the largest value, so min() and < NONE work (not -1)
    const long NONE = $7fffffff
    ; the most text a build can hold (the host's text area)
    const long TEXT_MAX = 16 * 1024 * 1024
    ; digits in the largest line number (16 M one-character lines)
    const ubyte DIGITS = 8
    ; a position or count as text
    alias print = txt.print_l
    alias text = conv.str_l
    ; a number typed (:123, :1,5d)
    alias parse = conv.str2long

    ; a position in memory at any address, a byte at a time (big endian):
    ; the 68000 can't read or write a long at an odd address, and the gap
    ; buffer's undo records have them anywhere (tools/encode_copy.py
    ; --bytewise puts these in place of peekl/pokel; the hosts don't)
    sub load(pointer p) -> long {
        return mklong(@(p), @(p + 1), @(p + 2), @(p + 3))
    }

    sub store(pointer p, long value) {
        @(p) = msb(msw(value))
        @(p + 1) = lsb(msw(value))
        @(p + 2) = msb(lsw(value))
        @(p + 3) = lsb(value)
    }

    ; sys.memset for any count: the m68k library's count is a uword
    ; (--bytewise puts it in place of sys.memset)
    sub memset(pointer p, long count, ubyte value) {
        while count > $8000 {
            sys.memset(p, $8000, value)
            p += $8000
            count -= $8000
        }
        if count != 0
            sys.memset(p, count as uword, value)
    }
}
