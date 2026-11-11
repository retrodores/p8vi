;
; the console for src/cpm/textio.p8: CP/M's, through BDOS function 6
; (direct console I/O: no ^S/^C checks, no tab expansion).  The host
; build's is src/host/console_platform.p8.
;
console {
    ; BDOS function 6: E is the character, or $FF to read a key without
    ; waiting (0 when there is none).  IX and IY are kept, for the
    ; compiled code.
    ubyte[] bdos6 = [
        $dd, $e5,           ; push ix
        $fd, $e5,           ; push iy
        $0e, $06,           ; ld c,6
        $1e, $ff,           ; ld e,char (offset 7)
        $cd, $05, $00,      ; call 5
        $fd, $e1,           ; pop iy
        $dd, $e1,           ; pop ix
        $6f,                ; ld l,a
        $26, $00,           ; ld h,0
        $c9                 ; ret
    ]

    sub out(ubyte char) {
        bdos6[7] = char
        uword code = &bdos6
        void call(code)
    }

    ; a key typed, 0 for none
    sub poll() -> ubyte {
        bdos6[7] = $ff
        uword code = &bdos6
        return lsb(call(code))
    }

    ; a key, when the program has nothing else to do: here too 0 for none
    ; (the editor asks again)
    sub wait() -> ubyte {
        return poll()
    }
}
