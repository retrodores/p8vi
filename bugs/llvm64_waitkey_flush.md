# llvm64: txt.getkey()/waitkey() don't flush stdout before waiting

**Status:** fixed in the compiler (2026-11-11): the repro's prompt shows
before the key.  p8vi's workaround (`fileio.flush(0)` before `syscall
218` in src/host/console_platform.p8) is gone; the host version needs
this compiler or later.

## What happens

On a terminal, a program that draws with `txt.chrout`/`txt.print` without
a newline and then calls `txt.waitkey()` shows nothing: it sits in
`poll()` (`prog8_waitkey` -> `read_key`) with the output still in stdio's
buffer (stdout to a terminal is line buffered; `putchar` output without
a `\n` stays there).  A full-screen program (cursor addressing, no
newlines) looks hung.  Seen with build/p8vi-host on macOS arm64 (iTerm2
and Terminal), 2026-11-10.

## Repro

```prog8
%import textio
main {
    sub start() {
        txt.print("press a key: ")      ; no newline
        ubyte k = txt.waitkey()         ; nothing shown while waiting
        txt.print_ub(k)
        txt.nl()
    }
}
```

`prog8c -target llvm64 -o build/waitkey waitkey.p8 && build/waitkey`:
"press a key: " appears only after a key is pressed.

## Fix

In the runtime's `read_key` (both `prog8_getkey` and `prog8_waitkey`),
`fflush(stdout)` before `poll()`/`read()`, as C's stdio does for stdin
reads from a line-buffered terminal (`getchar` flushes stdout; a raw
`read`/`poll` doesn't).  getkey() too: a program polling for keys in a
loop would otherwise only show its output when the buffer fills.
