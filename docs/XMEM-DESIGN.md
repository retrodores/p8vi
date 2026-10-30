# Design: text in extended memory

Status: proposal, nothing of it is built yet.  `docs/REU.md` describes
the REU and `xmem` modules this builds on.

## Goals

- Edit files bigger than main RAM: up to 64 KB of text on a C64 with an
  REU and on the Commander X16 (now 20 KB and 12 KB).
- **Recover the text after a crash or a reset.**  The REU and the X16's
  banked RAM keep their contents, so the text in them can be found again,
  like vi's `-r`.  This means nothing may write to extended memory before
  the editor has checked for text to recover, including REU detection.
- One C64 build: it finds an REU at run time and works without one.
- The VIC-20 keeps the gap buffer and must not pay bytes for any of this.
- The logic can be tested on the virtual target, without extended memory.

Not goals for now: more than 64 KB of text, several files at once, the
C128.  The design should leave room for them.

## Why not one big gap buffer in banks

The gap buffer works on raw memory: `gap_ptr()` and `segments()` hand out
pointers, the searches walk bytes, moving the gap is one `memcopy`.
Stretched over banks, every byte access needs a bank check, and moving
the gap copies text between banks.  On the C64 it is worse: an REU bank
is not mapped in, it is copied in.  Switching the 8 KB window costs about
18 ms (9 ms for one that wasn't changed), so anything that touches two
banks in turn (a search, drawing a screen across a bank boundary, moving
the gap) would switch hundreds of times.

## The page store

The text is a list of **pages**.  A page is a block of `PAGE_SIZE`
bytes (1 KB to start with, to be measured) that holds from 0 to
`PAGE_SIZE` bytes of text.  A **page table** in main RAM lists the pages
in text order:

| Field | Size | What |
|-------|------|------|
| `id` | uword | where the page is (see below) |
| `len` | uword | bytes of text in it |
| `lines` | uword | line endings in it |

With 1 KB pages, 64 KB of text needs at most about 128 pages if pages are
kept at least half full: a 768 byte table.

- **Positions stay `uword`,** as now, so the editor doesn't change.  The
  store finds the page for a position by adding up `len` along the table.
  It remembers the last page found and where it starts, so the usual case
  (near the last access) is a compare.
- **Insert** shifts the rest of one page up.  At most `PAGE_SIZE` bytes
  move: about 10 ms for 1 KB on the C64 in the worst case, against up to
  the whole text after the cursor in the gap buffer when the gap moves.
  A full page is split in two.
- **Delete** shifts the rest of the page down; a page that falls below a
  quarter full is merged with its neighbour if they fit in one.  A big
  delete drops whole pages from the table without touching them.
- **Line numbers:** `line_offset()` and `line_number()` add up `lines`
  page by page and only scan inside one page.  Now they scan the text
  from the start, which gets slow at 64 KB.
- **Marks, undo, `changes`, `change_start`/`change_end`, `modified`** work
  in positions and stay as they are.

### Where pages live: `pagemem`

A page `id` (0 to 127) is turned into an address by a small platform
module, `pagemem` (`src/<target>/pagemem_platform.p8`, built in step 4):

```prog8
pagemem {
    sub init(uword start, uword top, uword page_size, ubyte max_pages) -> uword
    sub map(ubyte id) -> uword          ; the page's bytes, until the next map()
    sub changed()                       ; the page mapped last was written to
    sub sync()                          ; write changed pages back
}
```

- **Only the page mapped last can be used**, and every write to it is
  followed by `changed()`.  Bytes going from one page to another (splits,
  merges, moving bytes along) pass through a 255 byte buffer in main RAM,
  a piece at a time.
- **X16** (`src/cx16`): pages are in banked RAM from bank 2 (`xmem`), 8 to
  a bank, used in place: `map()` selects the bank.
- **C64 REU build** (`src/c64reu`): `map()` copies the page into one of 4
  **cache slots** of 1 KB in main RAM, unless it is there already; the
  least recently used slot is written back first if it changed.  1 KB of
  DMA takes about 1 ms.  Only `reu.cmd()` is used, not the `$a000`
  window.
- **Without extended memory** both use main RAM pages.  With it, all pages
  are in extended memory (none in main RAM), as crash recovery needs; the
  first page there is kept free for the recovery header.
- **Virtual target** (the tests): one window that is written back only
  after `changed()`, so a page used after mapping another, or written
  without `changed()`, gives wrong text in the tests.
- The page table has room for 128 pages; the text is at most 65534 bytes
  (positions are uwords), and `read_room()` gives no more room than that.

### What the editor sees

The editor uses the gap buffer's subroutines.  The places that used the
gap's memory directly (`gap_ptr()`, `inserted()` and `segments()`) now go
through a **chunk** interface that both stores have (done in step 2):

```prog8
    sub chunks() -> ubyte               ; number of pieces of text
    sub chunk(ubyte n) -> pointer, uword    ; piece n and its length
    sub read_room(uword position) -> pointer, uword    ; room to read into
    sub read_done(uword count)          ; count bytes were read into it
    sub loaded(uword count) -> bool     ; after clear(): they are the text
```

- `translate_text(how)` goes through the chunks to translate the text or,
  with `WRITE_TEXT`, to write it to a file (one loop for both: `:w` and
  the ASCII and line ending conversions).
- `load_file` reads into `read_room()` and calls `read_done()` (`:r`) or
  `loaded()` (`:e`).

The gap buffer has two chunks (before and after the gap) and one read
room (the gap).  The page store has one chunk per page and gives one page
at a time to read into, so in step 3 a load becomes a loop of `f_read`
calls.  Two details of that loop: a CR LF pair can be split between two
reads, and the format is detected from the first read only, not from the
whole file as now.  With the gap buffer the loop runs once.

Both stores are one block with the same name and subroutines, so the
editor calls them the same way: `src/vic20/` imports the gap buffer, the
C64 and X16 import the page store.  `make test-gap` tests both on the
virtual target, with a small `PAGE_SIZE` so that splits and merges
happen often.

### Yank and undo

The yank buffer and the undo log are fixed buffers now (the undo log is
2 KB), so `yG` or `dG` on a 60 KB text can't be yanked or undone.  They
become page lists in the same store, in pages not used by the text.  A
yank copies pages; a put inserts them.  This also answers the X16
problem in `docs/REU.md`: the yank buffer, undo log and key buffers are
in bank 1 now, which can't be seen while a text page is mapped.  Yank and
undo move into the page store, the key buffers (small) into main RAM, and
bank 1 becomes part of the page pool.

Several files at once would be several page lists too.

## Crash recovery

After a crash or a reset, the REU still holds its pages, and the X16 its
banked RAM (both tested, see "What survives a reset" below).  After
switching off, both are lost.  Decided (step 6): like vi's `-r`, the text
comes back with a command, `:recover` (`:rec`), not a question at startup.

**Two header slots.**  Extended memory starts with two header slots of
1 KB; the pages come after them.  A header describes one text:

- a signature, a version, a state (in use, or clean) and a sequence
  number (the newer text has the higher one);
- `page_size`, the text length, the cursor;
- the editor's data (48 bytes: file name, line endings, ASCII);
- the page ids and lengths of the text;
- a checksum over all of it.

**Syncing.**  `buffer.sync()` writes the changed cache slots back (C64)
and then the header into the session's slot.  The editor calls it when
the keyboard has been idle for half a second and the text changed since
the last sync, like vi writing its swap file.  `:q` marks the session's
header clean.  A text recovered is the text as of the last sync; a page
changed after it (or freed and used again) can be off.

**At startup**, before anything writes to extended memory:

1. Find the REU without writing to it (below).
2. Read both headers.  A valid one (signature, checksum, page size, page
   ids) that isn't clean is a text to recover: its pages are left out of
   the free pages, so nothing overwrites them, and the editor says so
   (`:rec to recover`).
3. Nothing is written yet: the session takes a slot at its first sync
   (below).

So a text waits until it is recovered, also over more sessions and
resets: missing the message loses nothing.  After a second reset there
can be two texts: `:recover` brings back the newer one and says that one
more is there; `:recover` again brings the other.  The session takes a
header slot only when it first syncs: the recovered text's, a free one,
or, if two texts still wait then (the user typed a new text instead of
recovering), the older text's, which is dropped.

`:recover` replaces the text (`:recover!` if it is changed and not
saved), with the file name and settings it had.

### REU detection without writing

Done: `reu.detect()` no longer changes the REU's memory.  REU sizes are
powers of two, so it probes bank 1, 2, 4 ... 128 in turn, 8 bytes at
`$fff8` (the end of the bank, away from the header), until a bank isn't
there:

- the marker doesn't stay in it (VICE's 256 KB REU, like a 1764, has no
  banks 4-7: they don't repeat banks 0-3), or
- the marker shows up in bank 0 (a smaller REU repeats its banks above
  its size).

Each probe swaps the marker in with the REU's swap command and swaps it
back out, so the bytes are put back without a copy.  Bank 0 is probed
first, to see whether there is an REU at all.  This takes 25 transfers of
8 bytes at most.

### What survives a reset

Tested (`make test-reu`, `tests/x16/bankreset.p8`):

| | Kept |
|---|---|
| C64 reset in VICE (`reset 0`, like the reset button) | the REU's memory, all of it; the C64's RAM too |
| C64 hard reset in VICE (`reset 1`, like switching off) | nothing: the REU is empty and the RAM refilled |
| X16 reset through the SMC (x16emu, ROM R49) | all banked RAM except the first byte of bank 1 (`$a000` becomes `$a0`) |

## Steps

1. **Non-destructive REU detection** and a test in VICE: a known pattern
   in the REU survives `reu.init()`, and the sizes are still right.  Find
   out what the X16 keeps in banked RAM over a reset.  *Done.*
2. **The chunk interface** in the gap buffer and the editor.  No change
   in behaviour; the VIC-20 must keep its free bytes (64 at least).
   *Done:* every build got smaller (VIC-20 76 to 105 bytes free).
3. **The page store, main RAM only**, with the gap buffer's tests and new
   ones for splits and merges, on the virtual target, and the load loop.
   C64 (REU build) and X16 builds use it.  Measure its code size and the text room
   lost to half-full pages and the table.  *Done,* see "Step 3: what the
   page store costs" below.
4. **`pagemem` for the X16 and the REU.**  Key buffers to main RAM.
   *Done:* see "Step 4" below.
5. **Yank and undo in the page store.**  *Done:* see "Step 5" below.
6. **Recovery:** header, `sync()`, `:recover`.  *Done:* see "Step 6"
   below.
7. Later: several files, texts over 64 KB (positions would need more than
   a `uword`, a change across the whole editor).

## Step 3: what the page store costs

Built (`src/pagestore.p8`), tested on the virtual target with 8 byte
pages (`make test-gap`: the store tests both stores pass, plus splits,
moving bytes between pages, merges, line counts against counting, reads
over several pages, and typing checked against a model), and in VICE
(`make test-c64`, with a new `big` suite: a 3.2 KB CR LF file whose CR LF
pairs are split between 1 KB reads).  A quick check on the X16 (load,
`dd`, save) is right too.

How it came out, compared with the design above:

- The code both stores share is `src/buffer.p8` (marks, change tracking,
  undo, searches built on `find_next`/`find_prev`, line routines); a
  store adds the rest, chosen per target by `store_platform.p8`.
- `buffer.PAGED` is false in the gap buffer, so code only the page store
  needs folds away (the VIC-20 lost 10 bytes in all, now 95 free).
- `read_room()` opens room inside one page (the rest of the page moves to
  its end, `read_done()` moves it back), so a read needs no free page.
- A delete over several pages is logged a page at a time, 7 bytes a
  record.
- The page store moves bytes with its own loop, 256 at a time with a byte
  index: `sys.memcopy` can't copy overlapping memory.

Size, main RAM only (1 KB pages, room for 64 in the table):

| | Gap buffer | Page store |
|---|---|---|
| C64 code + data | 29201 | 32922 (+3721) |
| C64 variables | 1024 | 1610 (+586, the page table) |
| C64 text room | 17486 bytes | 12 pages, 12288 bytes |
| X16 text room | 9980 bytes | 5 pages, 5120 bytes |

(text room: free memory less the yank buffer, undo log and key buffers,
3456 bytes on the C64; the X16 has them in bank 1; whole pages only).
The page store's code is the most of it, about 4 KB of Prog8's code for
the page table.  With extended memory (step 4) the text leaves main RAM,
so this matters for a C64 without an REU, and for the X16 only until
then.

## Step 4: text in extended memory

- The X16 keeps its pages in banked RAM; the yank buffer, undo log and
  key buffers moved from bank 1 to main RAM.  Files up to the 64 KB limit
  load: tried by hand in x16emu with 3 KB, 9.8 KB (two banks), 19.7 KB
  and 39 KB files (load, `dd`, save: right).
- The C64 REU build keeps its pages in the REU with 4 cache slots.
- Main RAM free (program end to memtop): C64 REU build 14382 bytes (the
  page table grew to 128 pages, and the slots come out of it), X16 4801.
  The text no longer needs it when there is extended memory.
- Tests: `make test-c64reu` runs the editor suites on the REU build with
  a 512 KB REU (with two more suites: `pages`, an 8 KB file, more pages
  than slots; `huge`, a 30 KB file read in twice more, the second time cut
  short at 65534 bytes) and without one, and the screen checks with the
  REU.  With the slots never written back the `pages` suite fails.
- Found on the way: `read_room()` gave a whole page of room even when the
  text was nearly 64 KB, so the length went past 65535 (the `huge` suite).

## Step 5: yank and undo in the page store

- The yank buffer is part of the store's interface: `yank(start, count,
  lines)` (adds the line ending for whole lines), `put(position)`,
  `yank_len`.  The gap buffer keeps it in main RAM (`yank_buf`), the page
  store in a **stream**.
- A stream is a list of pages outside the text, taken from the free pages
  as it grows: one for the yank buffer, one for the undo log, up to 64
  pages each.  The text has a budget, `text_max` pages (enough for 64 KB
  and 8 more, or all but `stream_min` = 3 when pages are few), and a
  stream only takes a free page while the text could still reach its
  budget: an insert still fits whenever `free()` says so; a big yank or
  undo log fails instead ("undo too big").
- The undo log keeps its record format; the page store's copy of
  `log_change()` / `undo()` reads and writes it through the stream, and
  takes a change's bytes from the text by position (not a pointer: the
  stream's pages are mapped in between).  The gap buffer's undo code moved
  unchanged from `buffer.p8` to `gapbuffer.p8`.
- Bytes from a stream into the text go through `put_buf`, as `bounce` is
  used inside `insert_bytes()`.
- The page table holds 255 pages, so a 64 KB text, a 64 KB yank and a
  64 KB undo log fit together.
- Tests: the store tests have a shared yank test and a page store stream
  test; edtest has `bigundo` (REU only: `dG` of 30 KB undone, `yG` of 30 KB
  put; the step 4 build fails it).  The X16 undid `dG` of a 39 KB file.
- Found on the way: `delete_nchar` counted the line endings after moving
  the rest of the page down (a new test, `delete lines`, catches it), and a
  compiler bug (`bugs/uword_array_eq_ubyte.p8`) made the REU cache miss
  pages it had and fetch them a second time.
- Main RAM free: C64 REU build 11630 bytes, X16 2089 (the tables and two
  255 byte buffers).  The REU build without an REU has 7 KB of text (and
  3 KB for yank and undo).

## Step 6: recovery

- `pagemem` has two header slots before the pages (1 KB each), with
  `header_put()` / `header_get()`, and `persistent` where the memory
  survives a reset (REU, X16 banked RAM; and the virtual target, where
  calling `init()` again on the same memory is the reset).
- The page store reads both headers in `init()` and leaves the waiting
  texts' pages out of the free pages.  `sync(meta)` writes the session's
  header; `clean()` marks it clean (`:q`); `recover(meta)` brings back the
  newest text and syncs it at once into its own slot.  The editor syncs
  when no key came for 30 jiffies and the text changed (`sync_text()`,
  with the file name, line ending and ASCII setting), says `:rec to
  recover` at startup, and has `:recover` / `:rec` / `:rec!`.  `cmdword`
  holds 8 letters now (VIC-20: 4 bytes).
- Room: the page store's buffers (bounce, put_buf, free list, header,
  stream page lists: 989 bytes) are in `pagemem.scratch`: golden RAM
  `$0400` on the X16, a `memory()` block elsewhere.  `pagemem` gives the
  page size and the table size: the X16 has 2 KB pages and 128 of them
  (256 KB, so a 64 KB text, yank and undo log fit), the C64 1 KB pages and
  255.  Main RAM free: C64 REU build 7653 bytes (without an REU it has
  4 KB of text), X16 505 (the key buffers take 384 of it), VIC-20 110.
- Tests: `pagetest` (recovery: one and two texts, newer first, a dropped
  older one, `clean()`, a damaged header, waiting pages left alone), and
  `tests/vice/rectest.py` in `make test-c64reu`: edit with an REU, reset
  VICE, run p8vi again, `:rec`, the edited text is back; and after `:q!`
  nothing comes back.  Without the sync it fails.  Not tried on the X16
  over a reset (x16emu can't be reset from pasted keys); the X16 edits
  big files and undoes `dG` of 39 KB.
- Compiler bug found: comparing two elements of a split `uword` array
  doesn't assemble (`bugs/split_array_compare_elements.p8`); `slot_seq` is
  `@nosplit`.

## Open questions

- `PAGE_SIZE`: 1 KB is a guess.  Smaller pages make inserts faster and
  waste less on half-full pages; bigger ones make the table smaller and
  cross fewer page boundaries.  Measure with real files.
- A C64 without an REU: decided after step 3, two C64 builds for now.
  `p8vi-c64` keeps the gap buffer (17 KB of text); `p8vi-c64reu` has the
  page store (`src/c64reu/store_platform.p8`, compiled with `src/c64reu`
  before `src/c64`), and got the REU in step 4.  Without an REU it has
  12 KB of text after step 3, 4 KB after step 6.
- Recovery: decided, `:recover` and two header slots (see "Crash
  recovery").
- How often to `sync()`, and whether a sync while typing is noticeable on
  the C64 (writing 4 changed slots and the header is about 5 ms).  Not
  measured yet, nor how a cache slot miss feels while typing.
