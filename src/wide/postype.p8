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
}
