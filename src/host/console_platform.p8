;
; the console for src/cpm/textio.p8 in the host build (llvm64, llvm32):
; the terminal, through the library's syscalls.  The first key read puts
; it in raw mode (no echo, no line editing, Ctrl-C and Ctrl-Z are keys);
; it goes back to normal when the program ends.  When stdin isn't a
; terminal, a key is the next byte of stdin, and 0 at its end.
;
console {
    ; the largest screen txt keeps (its buffers' size, 50 KB): a terminal
    ; window's size up to this is used (platform.init asks it); a bigger
    ; one shows this much.  (the editor's rows and columns are ubytes)
    const ubyte MAX_WIDTH = 250
    const ubyte MAX_HEIGHT = 200

    sub out(ubyte char) {
        %ir {{
            loadm.b r99100.b,[console.out.char]
            syscall 2 (r99100.b)
        }}
    }

    ; a key typed, 0 for none (txt.getkey)
    sub poll() -> ubyte {
        %ir {{
            syscall 217 (): r99100.b
            returnr.b r99100.b
        }}
    }

    ; a key, waiting for it (txt.waitkey): the editor would otherwise ask
    ; again and again, and keep a host CPU busy.  (the runtime flushes
    ; stdout first, so the screen is sent)
    sub wait() -> ubyte {
        %ir {{
            syscall 218 (): r99100.b
            returnr.b r99100.b
        }}
    }
}
