; strings routines the m68k targets' library doesn't have yet, which p8vi
; uses: the same as the other targets' (the llvm targets' strings.p8),
; merged into the library's strings block.  Dropped when the compiler's
; m68k strings has them.

%import strings

strings {
    %option merge, ignore_unused

    sub rfind(str stringptr, ubyte character) -> ubyte, bool {
        ; Locates the first position of the given character in the string, starting from the right.
        ; returns the index, and true; or 255 (an invalid index) and false when the string doesn't contain the character.
        ubyte ix = length(stringptr)
        while ix!=0 {
            ix--
            if stringptr[ix]==character
                return ix, true
        }
        return 255, false
    }

    sub append(str target, str suffix) -> ubyte {
        ; Append the suffix string to the target. (make sure the buffer is large enough!)
        ; Returns the length of the resulting string.
        ubyte target_len = length(target)
        return copy(suffix, target+target_len) + target_len
    }
}
