; The width of the editor core's text positions, line numbers and counts
; (buffer, gapbuffer and editor.p8 declare them uword): 16 bits here, for
; up to 64 KB of text.  A wide build (32-bit hosts and the m68k machines)
; compiles copies of those modules with uword made long, and its own
; postype.p8 in a source directory before this one: what changes with the
; width is all in this block.

%import textio
%import conv

pos {
    ; bytes in a position (the undo log's records hold them)
    const ubyte SIZE = 2
    ; no position: the largest value, so min() and < NONE work
    const uword NONE = $ffff
    ; the most text a build can hold (the host's text area)
    const uword TEXT_MAX = 65535
    ; digits in the largest line number (65535)
    const ubyte DIGITS = 5
    ; a position or count as text
    alias print = txt.print_uw
    alias text = conv.str_uw
    ; a number typed (:123, :1,5d), up to 65535
    alias parse = conv.str2uword
}
