# The text store: using p8vi's gap buffer and page store elsewhere

p8vi's text is kept by a *text store*, the block `buffer`.  It doesn't
know about keys, the screen or vi: it holds the text, inserts and
deletes, finds lines, keeps marks, a yank buffer and an undo log, and
says what changed so an editor can redraw only that.  Another editor can
use it as it is and bring its own keys and screen code.

There are two stores with the same routines.  A program imports exactly
one of them:

- **The gap buffer** (`gapbuffer.p8`): the text in one block of main RAM.
  It's small, fast and works on any target.
- **The page store** (`pagestore.p8`): the text in 1 KB pages, which
  can be in extended memory: a C64 REU or the X16's banked RAM, up to
  64 KB of text with yank and undo as big.  Without extended memory, the
  pages are in main RAM.  The text can be recovered after a crash or a
  reset.

Nothing in these files uses the editor (`editor.p8`), `platform`,
`features` or textio.  Only the files listed below are needed.

## Which files to copy

The gap buffer only:

| File | Why |
|------|-----|
| `src/buffer.p8` | the shared part of the store |
| `src/gapbuffer.p8` | the gap buffer |
| `src/fastmem.p8` | 6502 byte scans and copies (not for the virtual target) |
| `src/<target>/fastmem_platform.p8` | turns `fastmem` on or off for the target |

The page store with extended memory:

| File | Why |
|------|-----|
| `src/buffer.p8` | the shared part of the store |
| `src/pagestore.p8` | the page store |
| `src/fastmem.p8`, `src/<target>/fastmem_platform.p8` | as above |
| `src/<target>/pagemem_platform.p8` | where the pages live |
| C64 only: `src/c64/reu.p8` | the REU driver (`pagemem` uses it) |
| X16 only: `src/cx16/xmem_platform.p8` | the X16's RAM banks (`pagemem` uses it) |

These sets were checked by copying only them (and a small `main`) to
an empty directory and compiling for the C64, X16, VIC-20 and virtual
targets.

Optional:

| File | What |
|------|------|
| `src/charset.p8` | ASCII ↔ PETSCII translation in place, CR LF → CR, and "does this look like ASCII?".  Its tables need an assembler symbol `p8b_main.FONT` (0, or 1 for p8vi's font build), so define it as `docs/FEATURE-SWITCHES.md` shows, or delete the `.if`. |
| `src/cbmscreen.p8` | fast C64 and VIC-20 row drawing and scrolling, straight into screen memory (`put_row`, `scroll_rows`) |
| `src/buftests.p8`, `src/gaptest.p8`, `src/pagetest.p8` | the store's self checking tests (see Tests) |

## Platform specific files

The `-srcdirs` order picks a target's files (`src:src/<target>`).
p8vi's C64 REU build uses `-srcdirs src:src/c64reu:src/c64`, so its
`pagemem_platform.p8` comes from `src/c64reu` and the rest from
`src/c64`.

| File | Provides |
|------|----------|
| `src/c64/fastmem_platform.p8`, `src/cx16/fastmem_platform.p8` | `fastmem.FAST = true`: the stores use the 6502 routines in `fastmem.p8` |
| `src/vic20/fastmem_platform.p8` | `fastmem.FAST = false`: the gap buffer keeps its own Prog8 loops, which are smaller and slower (p8vi's VIC-20 build has no room for both) |
| `src/virtual/fastmem_platform.p8` | Prog8 versions of the `fastmem` routines, for the virtual target |
| `src/c64reu/pagemem_platform.p8` | pages in an REU.  Pages are copied into 4 cache slots of main RAM (4 KB, from the start address given to `buffer.init()`), and changed ones are written back.  The REU's first 2 KB holds the two recovery headers.  Without an REU the pages are in main RAM from start to top.  `scratch`: 768 bytes in a `memory()` block. |
| `src/cx16/pagemem_platform.p8` | pages (2 KB each) in banked RAM from bank 2, used in place.  Bank 0 is the KERNAL's, and a reset changes bank 1.  Without banked RAM, pages are in main RAM.  `scratch`: golden RAM `$0400`-`$067f`, so your program can use only `$0680`-`$07ff` of golden RAM. |
| `src/virtual/pagemem_platform.p8` | pages in main RAM, seen through one window that is written back only after `changed()`.  It's stricter than the real ones, so the tests catch a page used after the next `map()`. |
| `src/c64/reu.p8` | REU driver: `detect()` (finds the REU and its size without changing its memory), `cmd()` (one DMA copy).  It also has 8 KB bank switching (`init()`, `bank()`), which the page store doesn't use. |
| `src/cx16/xmem_platform.p8` | `xmem.init()` (how many banks), `xmem.select(n)` |
| `src/c64/store_platform.p8` etc. | one line, `%import gapbuffer` or `%import pagestore`: p8vi's per-target choice of store.  Optional: your program can import a store directly. |

`pagemem` is the interface between the page store and the memory.  A new
target only needs its own `pagemem_platform.p8` with the same routines:
`init(start, top, page_size, max_pages) -> pages`, `map(id) -> address`
(valid until the next `map()`), `changed()`, `sync()`, `header_put()` and
`header_get()` (the recovery headers), plus `persistent`, `PAGE_SIZE`,
`MAX_PAGES`, `scratch` and `SCRATCH_SIZE`.  `docs/XMEM-DESIGN.md` explains
the design.

Not used by p8vi: `src/c64/xmem_platform.p8`, `src/c64/reucompat.p8`
and `src/c128/reucompat.p8`.  They're 8 KB REU banks at `$a000` and the
X16's banking calls on the C64, from an earlier plan (`docs/REU.md`).

## The shared part: buffer.p8

`buffer.p8` is in both stores (the stores add to its block with
`%option merge`).  It has:

- **Positions:** offsets in the text, 0 to `length()`, so at most 64 KB.
  `NONE` ($ffff) means no result.
- **Marks:** `NUM_MARKS` (4) positions that move with inserts and
  deletes.  Use them for the cursor, the top of the screen and so on:
  `set_mark()`, `get_mark()`.
- **Change tracking:** `modified` (cleared by `loaded()` and `clear()`;
  the editor clears it after a save) and `changes` (a counter).
  `change_start` and `change_end` give the range that differs since the
  last `change_reset()`, for redrawing only that.
- **Editing:** `insert(str, pos)`, `delete_char(pos)`,
  `delete_range(start, end)`.
- **Lines and searching:** `eol` (the line ending, CR by default),
  `line_start()`, `line_end()`, `next_line()`, `prev_line()`,
  `copy_line()`, `match_at()`, `find_bytes()`, `find_bytes_prev()`.
- **Undo:** `undo_init(buf, size)`, `undo_mark()` (call before each
  command: one undo reverts everything since), `can_undo()`,
  `undo_clear()`, and `undo_lost` and `undo_reversed` (undo again to
  redo).

## The gap buffer: gapbuffer.p8

| Routines | What |
|----------|------|
| `init(start, top)` | use main RAM from start up to top, empty |
| `clear()`, `free()`, `length()` | |
| `get(pos)`, `set(pos, c)` | one byte |
| `insert_char()`, `insert_bytes()`, `delete_nchar()` | the basic changes |
| `read_room(pos)`, `read_done(n)`, `loaded(n)` | loading a file straight into the store, then marking it as a new unmodified text |
| `copy_out(pos, n, dest)` | bytes out, for drawing |
| `chunks()`, `chunk(i)` | the text in pieces in memory (two for the gap buffer), for saving and translating |
| `find_next()`, `find_prev()`, `line_offset(line)`, `line_number(pos)` | |
| `yank(start, n, lines)`, `put(pos)`, `undo()` | the yank buffer and undo |
| `PAGED = false`; `sync()`, `clean()`, `recover()` | empty: no recovery |

Before `init()`, set `yank_buf` and `yank_size`, and call
`undo_init(buf, size)` (or leave `undo_size` at 0 for no undo).  p8vi
takes 1 KB for yank and 2 KB for undo from the top of its memory.

## The page store: pagestore.p8

It has the same routines as the gap buffer, and these differences:

- **`PAGED = true`.**  Code for one store only can test it, and the
  compiler leaves out the other store's branch.
- **Yank and undo live in its pages.**  Set `yank_size` and `undo_size`
  to `$ffff` (as big as there is room) before `init()`; `yank_buf` isn't
  used.
- **A pointer is valid only until the store is used again.**
  `read_room()` gives room in one page, so a file is read in several
  pieces.  `chunks()` and `chunk(i)` give one piece per page.
- **Recovery** (when `pagemem.persistent`):
  - `sync(meta)` saves the text's header and `META_SIZE` (48) bytes of
    your own (file name, settings).  p8vi calls it when no key has come
    for half a second.
  - `recoverable` tells how many texts are waiting after a restart.
  - `recover(meta)` gets the newest one back.
  - `clean()` (on quitting) means there's nothing to recover.
  - `synced_changes` equals `changes` when nothing is unsynced.
- **`page_size` and `stream_min`** are settings for `init()`.  The tests
  use small pages.

## What the editor does

The store doesn't read files, draw or take keys.  p8vi's `editor.p8` is
an example of all of these:
- **Loading:** `clear()`, then `read_room()` / `read_done()` until the
  file ends, then `loaded(n)` (`load_file()`).
- **Saving:** `chunk(i)` for each piece (`translate_text()`,
  `write_text()`).
- **Drawing:** `copy_out()` per line, with `change_start` and
  `change_end` to skip what didn't change.
- **Commands:** `undo_mark()` before each command.  The cursor goes in
  a mark.

## Names to watch out for

The store uses the block names `buffer`, `fastmem` and `pagemem`, plus
`reu` on the C64 and `xmem` on the X16, so your program can't have
blocks with these names.

The C64 page store needs BASIC banked out, which is Prog8's default:
the REU sees the same memory as the CPU.

## Tests

- `make test` runs `src/gaptest.p8` and `src/pagetest.p8` on the virtual
  target.  Both run the shared `src/buftests.p8`, then their store's own
  tests, and compare the output with `tests/expected/`.  A copy of the
  store can use the same tests, with the virtual target's
  `fastmem_platform.p8` and `pagemem_platform.p8`.
- `make test-fastmem` checks the 6502 routines against Prog8 in VICE.
- `make bench` (`tests/bench/storebench.p8`) times the stores.
