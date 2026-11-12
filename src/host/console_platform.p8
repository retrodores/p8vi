;
; the console for src/cpm/textio.p8 in the host build (llvm64, llvm32):
; the terminal, through the library's syscalls.  The first key read puts
; it in raw mode (no echo, no line editing, Ctrl-C and Ctrl-Z are keys);
; it goes back to normal when the program ends.  When stdin isn't a
; terminal, a key is the next byte of stdin, and 0 at its end.
;
; The window's size is the runtime's too (size(): TIOCGWINSZ on Unix,
; GetConsoleScreenBufferInfo on Windows).  While wait() waits on a
; terminal it looks every 60th of a second whether the size changed: the
; runtime's waitkey doesn't wake up for that.
;
console {
    ; the largest screen txt keeps (its buffers' size, 50 KB): a terminal
    ; window's size up to this is used; a bigger one shows this much.
    ; (the editor's rows and columns are ubytes)
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

    ; the window's size: columns (lsb) and rows (msb); 0 when stdout isn't
    ; a terminal.  (the library's txt.terminal_size(): p8vi's txt is
    ; src/cpm/textio.p8)
    sub size() -> uword {
        %ir {{
            syscall 219 (): r99000.w
            returnr.w r99000.w
        }}
    }

    ; the size the screen is laid out for (platform), 0: the size isn't
    ; followed (-s, or not a terminal)
    uword watched
    ; wait() found the size changed: it returned 0 (platform.get_key)
    bool resized

    ; a key, waiting for it (txt.waitkey), 0 at the end of the input: the
    ; editor would otherwise ask again and again, and keep a host CPU busy.
    ; (the runtime flushes stdout first, so the screen is sent)  When the
    ; size is followed: the keys asked for every 60th of a second, and 0
    ; when the window changed size (resized)
    sub wait() -> ubyte {
        if watched == 0 {
            %ir {{
                syscall 218 (): r99100.b
                returnr.b r99100.b
            }}
        }
        ubyte k
        repeat {
            k = poll()
            if k != 0
                return k
            if size() != watched {
                resized = true
                return 0
            }
            sys.wait(1)
        }
    }
}
