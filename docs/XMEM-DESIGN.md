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

A page `id` is turned into an address by a small platform module,
`pagemem` (`src/<target>/pagemem_platform.p8`):

```prog8
pagemem {
    sub init() -> uword                 ; number of pages
    sub map(uword id) -> pointer        ; the page's bytes, until the next map()
    sub changed()                       ; the last mapped page was written to
    sub sync()                          ; write changed pages back
}
```

- **Main RAM** (virtual target, a C64 without an REU): pages are slots in
  the text memory; `map()` is arithmetic.
- **X16:** pages are in banked RAM, 8 to a bank.  `map()` selects the
  bank and returns `$a000 + (id & 7) * 1024`.  Nothing is copied.
- **C64 with an REU:** `map()` fetches the page into one of a few
  **cache slots** in main RAM (8 slots of 1 KB to start with), unless it
  is there already; the least recently used slot is written back first if
  it changed.  1 KB of DMA takes about 1 ms.  This doesn't use `reu.bank()`
  or the `$a000` window: only `reu.cmd()`, with page-sized transfers.  So
  the 8 KB at `$a000` stay part of main RAM.
- Free pages are kept in a bitmap: 256 bytes for 2048 pages (2 MB).

Main RAM pages can be used next to extended memory pages (the main RAM
left after the cache slots and buffers), so an REU adds to main RAM
rather than replacing it.

**Two pages at once.**  Copying from one page to another (splitting,
merging, yanking) needs both at once.  The REU cache holds both.  On the
X16 two pages in different banks can't both be seen at `$a000`, so the
copy goes through a small buffer in main RAM (256 bytes), in pieces.
Code must not switch between two banks byte by byte.

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

After a crash or a reset, the REU still holds its pages, and the X16
its banked RAM (both tested, see "What survives a reset" below).  After
switching off, both are lost.  To find the text again, extended memory
needs a **header** at a fixed place (the start of REU bank 0, or the
start of X16 bank 2, the first `xmem` bank):

- a signature and a format version;
- `PAGE_SIZE`, the file name, the line ending and ASCII settings;
- the page table and a checksum over it;
- a "clean" flag, set on `:q` and cleared by the first change.

`pagemem.sync()` writes the changed cache slots (C64) and then the header.
The editor calls it when the keyboard has been idle for a moment and
after a fixed number of changes, like vi writing its swap file.  Pages
written after the last sync but before a crash are lost; the header still
describes the text as it was at the sync, as long as freed pages are not
reused before the next sync.

At startup, before anything writes to extended memory:

1. Find the REU without writing to it (below).
2. Read the header.  If the signature and checksum are right and it isn't
   clean, say so: `recover with :recover`.  Until then, nothing may write
   to extended memory: new text goes in main RAM pages.
3. `:recover` takes the page table from the header.  `:e`, `:q` or the
   first change without recovering ends the chance, after asking once.

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
   C64 and X16 builds use it.  Measure its code size and the text room
   lost to half-full pages and the table.  *Done,* see "Step 3: what the
   page store costs" below.
4. **`pagemem` for the X16 and the REU.**  Key buffers to main RAM.
5. **Yank and undo in the page store.**
6. **Recovery:** header, `sync()`, `:recover`.
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

## Open questions

- `PAGE_SIZE`: 1 KB is a guess.  Smaller pages make inserts faster and
  waste less on half-full pages; bigger ones make the table smaller and
  cross fewer page boundaries.  Measure with real files.
- A C64 without an REU: the page store in main RAM, or the gap buffer as
  now?  Measured in step 3: the page store leaves 12 KB of text instead of
  17 KB (below).  Choices: accept it; make the page store smaller (parts
  in assembler); or two C64 builds, the gap buffer one without REU
  support.
- Recovery: just a status message and `:recover`, or a question at
  startup?
- How often to `sync()`, and whether a sync while typing is noticeable on
  the C64 (writing 8 changed slots is about 8 ms).
