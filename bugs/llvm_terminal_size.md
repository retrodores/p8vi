# llvm32/llvm64: the terminal's size, and when it changes

**Status:** feature request (2026-11-11).  p8vi works around it: see
"What p8vi does now".  Nothing in the language changes: this is the
llvm targets' runtime and library (textio), so it could go upstream as
it is or not at all.

## What's missing

On the hosted llvm targets a program runs in a terminal window of any
size, which the user can change while it runs.  The library doesn't say
what that size is:

- `txt.width()` and `txt.height()` return the constants
  `txt.DEFAULT_WIDTH` and `DEFAULT_HEIGHT` (80 and 25), whatever the
  window is;
- nothing tells a program that the window changed size.

Upstream's API already has the dynamic case: on the cx16, `txt.width()`
and `txt.height()` return the current screen mode's size, and a program
that calls them gets the right answer after a mode change.  On llvm the
same calls could return the window's size.

## What p8vi does now

The host version (`make host`, src/host/platform.p8) asks the terminal
itself:

1. `ESC [ 999 ; 999 H` (the cursor to the bottom right corner: the
   terminal stops it at the edge), then `ESC [ 6 n` (where is it?);
2. the answer `ESC [ rows ; cols R` comes back as keys through
   `txt.getkey()` (the runtime passes escape sequences that aren't cursor
   keys on byte by byte);
3. it waits up to half a second (`sys.ticks()`), then takes 80 x 24;
4. Ctrl-L asks again, and a new size lays the screen out again.

That works on macOS terminals, the Windows console, and over ssh to
Windows' sshd (checked 2026-11-11), but:

- it needs raw mode before asking (the runtime switches at the first key
  read, so p8vi reads once first; in cooked mode the answer would be
  echoed and line buffered);
- when stdin isn't the terminal (keys piped in, as in tests) the "answer"
  is read from the input: p8vi needs a `-s COLSxROWS` option to not ask;
- a terminal that doesn't answer costs half a second at start;
- a resize is only seen when the user presses Ctrl-L.

## Proposal

Two parts; the first is the useful one on its own.

### 1. `txt.width()` / `txt.height()`: the window's size

In the hosted runtime (llvm-triples/hosted-*.c), a syscall that returns
the terminal's size, and `txt.width()`/`txt.height()` use it:

- Unix: `ioctl(1, TIOCGWINSZ, &ws)` (stdout; or the controlling terminal,
  `/dev/tty`, when stdout is redirected), `ws.ws_col` and `ws.ws_row`;
- Windows: `GetConsoleScreenBufferInfo` on the output handle,
  `srWindow.Right - srWindow.Left + 1` and `srWindow.Bottom -
  srWindow.Top + 1` (the visible window, not the buffer);
- not a terminal, or the call fails: `DEFAULT_WIDTH` x `DEFAULT_HEIGHT`
  as now (so piped tests keep a fixed size without an option);
- clamped to 255 (the return type is ubyte).

No waiting, no escape sequences, nothing read from stdin.
`DEFAULT_WIDTH`/`DEFAULT_HEIGHT` stay as the fallback and as constants
for array sizes.

### 2. Knowing that it changed

Some options, cheapest first:

- (a) Nothing new: a program calls `txt.width()`/`height()` again when it
  wants (on Ctrl-L, or now and then when idle).  With part 1 that's
  already enough for p8vi.
- (b) `txt.size_changed() -> bool`: true once after the window changed.
  Unix: a `SIGWINCH` handler sets a flag (`sigaction`, with `SA_RESTART`
  so a waiting `poll()`/`read()` isn't left with `EINTR`); Windows: a
  `WINDOW_BUFFER_SIZE_EVENT` in the console input (with
  `ENABLE_WINDOW_INPUT`), which `prog8_getkey` would see while reading
  keys.
- (c) A key code for it: `txt.getkey()`/`waitkey()` return a reserved
  value (like the cursor keys' PETSCII codes) when the window changed.
  A full-screen program that sits in `waitkey()` then wakes up to redraw
  without polling.  For `SIGWINCH` that means `poll()` returning `EINTR`
  (no `SA_RESTART`) and the runtime turning it into the key.  But a
  program that doesn't expect the code gets a strange key, so this one
  would want to be switched on (`txt.size_events(true)`?).

(b) is the most general; (c) suits editors best (vi redraws on SIGWINCH
while it waits for a key).  p8vi could use either: today it has a hook
for "the screen changed size, lay it out again" (the C128's 40/80 key
uses it).

## What p8vi would change

With part 1, src/host/platform.p8 drops its question and answer (about
80 lines), `-s` stays only as an override, and the tests stop needing
`-s 80x24`.  With 2 (b) or (c) the screen follows the window without
Ctrl-L.

## Tests

- part 1: a program printing `txt.width()` and `txt.height()`, run in a
  pty of a known size (Python `pty` + `fcntl.ioctl(fd, TIOCSWINSZ, ...)`)
  and with stdout redirected (80 x 25);
- part 2: the same pty resized while the program waits
  (`TIOCSWINSZ` on the master sends `SIGWINCH`), the program printing
  the new size when told.
