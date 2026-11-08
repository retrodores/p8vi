# p8vi: possible future work

Ideas and known problems for p8vi, roughly by kind, not by priority.
`docs/KEYS.md` lists the vi commands that are done and the ones that
aren't.

## vi commands

- **Line ranges for more commands:** `:1,5d`, `:.,$y`, `:1,10w name`.
  `:s` has them (`read_range()`).
- **`&`** repeats the last `:s` on the cursor line.
- **Scrolling the view:** `zt`, `zz` and `zb` (cursor line to the top,
  middle or bottom of the screen), and Ctrl-E / Ctrl-Y (scroll one line).
- **Marks:** `m` and `'` / `` ` ``.  The gap buffer already keeps marks up
  to date as text changes (`NUM_MARKS` = 4, the editor uses 2), so there
  is room for a few.

## Known problems

- **Keys typed ahead during a failed load are lost.**  For example after
  `:r nofile`.  See `bugs/diskio_missing_file.md`, part 2.
- **An extra empty line at the end of a file, on the VIC-20.**  Fixed on
  the C64 and X16 (`features.FINAL_EOL`: the text doesn't keep a file's
  last line ending, writing puts it back), but it costs about 100 bytes
  the VIC-20 doesn't have, so there a file that ends with a line ending
  still shows an empty last line.
- **Saving with a drive or path prefix** (`:w 0:name`, `//dir/:name`):
  the library's delete and rename put `s:` and `r:` before the whole name,
  which doesn't work with a prefix (nor did saving before the safe save).
- **The VIC-20 status line** is only 22 columns: 12 for messages and 10 for
  the line,column position.  Check what gets cut short and whether the two
  parts can run into each other.

## Speed and size

- **Scrolling** (done on the C64 and X16, `features.SCROLL`): the screen
  scrolls when the cursor goes up to 4 rows off it, and only the rows
  that come in are drawn; rows are drawn in assembler (`put_row`).  One
  `j` over 2-row lines went from 274 ms to 84 ms on the C64
  (`tests/bench/viewbench.py`).  Left: `layout()` still works out all rows
  after a scroll (about a quarter of the time); shifting the row tables
  instead costs about 200 bytes the X16 doesn't have.  The VIC-20 has no
  room for the scroll code (SCROLL off) but draws rows in assembler.

- **More assembler:** the byte scans and copies are in `src/fastmem.p8`
  (3-4 times faster; `make bench`), screen rows in `put_row` and
  `scroll_rows` (platform).  The Prog8 code around calls is what costs
  bytes.

- **Ctrl-G could show where the text is** (the REU, bank 1, main RAM),
  like Turbo Macro Pro's `(512k)` on its status line: it would show at a
  glance when a build quietly falls back to main RAM (as p8vi-c64font
  did, 11 bytes short of room for the REU slots).  A fixed tag is about
  15-25 bytes, the REU size more; p8vi-c128reu has about 24 bytes before
  it loses a page slot, so it waits for a round of trimming.  The tests
  catch the fallback already (`reu-in-use` in tests/vice/edtest.py).

## Memory

- **Text in extended memory** (the cx16's banked RAM, a C64 REU): files
  up to 64 KB fit, with yank and undo as big, and `:recover` after a crash
  (done, `docs/XMEM-DESIGN.md`).
- **The X16's main RAM is full** (110 bytes left; the key buffers
  are in golden RAM, after the page store's buffers): the page store's
  code is big.  Parts in assembler, or more feature switches
  (`src/p8vi_cx16.p8`), before adding much there.
- **The start screen** is off on the VIC-20 (its room went to the safe
  save) and on the X16 (`features.SPLASH`).
- **More text on the VIC-20.**  With RAM in block 5 the text is at
  `$a000-$bfff` (8 KB).  The main RAM after the program was the idea for a
  second text area (a gap buffer split across two memory areas), but the
  program now reaches almost to `$8000`.  Room would have to come from
  features switched off, or from the 3 KB expansion at `$0400-$0fff`.
- **Several files open at once** (multiple buffers).
- **The font build** (`p8vi-c64font`): a name for it that doesn't
  suggest it runs on C64 OS; a fallback when `p8vi.fnt` is missing (it
  stops with "can't load p8vi.fnt"); whether the plain C64 build (gap
  buffer) should get it too, which costs it the 2 KB above `$c800`;
  switching the font with the file's kind, as on the MEGA65 (the C64
  character ROM can't be seen from the VIC bank the font is in); vi's `{`
  and `}` paragraph motions, now that they can be typed.

## Pages on disk (`p8vi-c64disk`, an experiment)

The page store with its pages in SEQ files, `p8vi.swp...`, on the
text's drive (`src/diskpage`), for fast devices (IDE64, RAMLink, CMD HD,
SD cards).  A 39 KB file, `:e` / `:w`: about 25 s / 22 s on VICE's host
directory drive; 154 s / 122 s on a 1581 with JiffyDOS (254 s to load
without); about 4 minutes to load on a 1541 with JiffyDOS, most of it the
37 page writes (a directory search, the BAM and 5 blocks each).  Moving
and editing then go about as with an REU.

- **Faster loading and saving:** the page transfer is in assembler now
  (7f9c417), but that was a small part.  Sampling the PC while a 39 KB
  file loads: the KERNAL's byte I/O about 30%, `charset.translate`
  (ASCII to PETSCII) about a third, the page writes about 10%,
  `diskio.f_read` about 9%.  A table for the translation (256 bytes per
  direction) and an assembler loop for reading text files (5.9 s to 3.7 s
  for 39 KB in a benchmark) would help every build with room for them.
- **Scratch the swap files on quitting** (now the next start does it).
- **A full disk** (done): the page count is sized from the blocks free
  at start (4 kept), a failed page write is caught (`READST` after the
  close), its splat file scratched and the write tried again.  While no
  page can be written p8vi keeps one clean page slot, refuses changes
  ("swap disk full"; moving and saving still work) and tries again on the
  next change, so deleting files on the drive (`:@s:...`) lets editing go
  on.  Tested on a full 1541: nothing lost or reordered beyond the
  refused changes.  Refused changes are slow on a 1541 (each one tries a
  write, a few seconds with JiffyDOS).
- **Recovery after a crash:** the swap files survive one; it needs the
  recovery headers in a file.
- **Other targets:** the driver only needs the KERNAL's file calls and
  `platform.KERNAL_OPEN_FILES`.  Not the PET 4032: the program alone is
  6.7 KB too big for it.

## Other targets

- **MEGA65** (`p8vi-mega65`, `p8vi-mega65dma`):
  - `p8vi-mega65dma` has 75 bytes left; SPLASH, SUBST and DIR are off.
  - On real hardware: which character set a MEGA65 starts with (p8vi
    puts the C64's back on quitting, which is what xemu starts with), and
    the attic RAM check on a board without it.
  - Recovery after a reset hasn't been tried.
- **PET** (`p8vi-pet32`, a 4032 with BASIC 4):
  - The PET has no Ctrl key: Ctrl-F/B/D/U, Ctrl-W, Ctrl-G and Ctrl-L
    need other keys (RVS already gives Ctrl-R).
  - The 8032 (80 columns): Prog8's PET screen routines are 40 columns.
  - The 8096 and 8296 have 64 KB more RAM at `$8000-$ffff`: room for
    the page store.
  - A disk error (no drive) stops p8vi with a BASIC error: BASIC 4's
    OPEN and CHKIN don't return when they fail.
- **Plus/4** (`p8vi-plus4`): `src/plus4/rammode.p8` must stay below
  `$8000` (it switches the RAM in); that holds because the toplevel
  imports `platform` first, but nothing checks it when the program grows.
- **C128** (`p8vi-c128`, native mode; the 40 column VIC-II or the 80
  column VDC screen, whichever is active at the start; `make test-c128`).
  Needs prog8c-llvm ab65226d8 or later (bugs/c128_startup_under_basic_rom.p8).
  - Only 11 KB for text (the program starts at `$1c01`).  `p8vi-c128x`
    (`make test-c128x`) has the text in RAM bank 1 instead, up to about
    60 KB (src/c128bank1: pages copied a byte at a time through the MMU's
    preset configurations, by a loop in the shared RAM at $0200), without
    the start screen and `:@$` for room, and 2 page slots.  Moving through
    about 50 KB of text, the copies from bank 1 can't be noticed (tried on
    VICE, 2026-11-06).  `:rec` after a reset works (bank 1 keeps its
    contents; tests/vice/rectest.py --machine c128 [--no-reu], also with
    p8vi-c128reu's REU).  It is also a font build: p8vi.fnt (the C64
    font build's) on either screen, src/c128font/font.p8; without the file
    the ROM's font stays.  The font cost one page slot (755 bytes).
  - `p8vi-c128reu` (`make test-c128reu`): the pages in an REU, 192 KB
    for the text, yank and undo (src/c128reu, src/c64/reu.p8), or in bank
    1 without one; the bank 1 build's room savings and also the one row
    scrolling off (`features.SCROLL`), for 2 page slots.
  - p8vi-c128x, and p8vi-c128reu without an REU, use all of bank 1,
    where BASIC 7 keeps its variables and strings.  Safe after the usual
    `LOAD`/`RUN`: they clear BASIC's variables and string space before p8vi
    starts (checked 2026-11-07).  Only a start without `RUN` (`BLOAD` and
    `SYS 7181`) could have variables to keep.  Using only the part BASIC
    leaves free (STREND $33 to FRETOP $35) was left out: `:rec` would
    have to search bank 1 for the headers after a reset, and
    p8vi-c128reu would lose a page slot.
  - Switching 40/80 while running: p8vi-c128 follows the 40/80 DISPLAY
    key (MMU $d505 bit 7, looked at while waiting for keys; SWAPPER, then
    everything drawn again), 185 bytes (`features.SWITCH`), and
    p8vi-c128x, with its font set up on both screens at the start (162
    bytes there, 1322 left).  Not in p8vi-c128reu (1048 bytes free: it
    would lose a page slot).  The status
    message is lost on a switch.  In VICE: `resourceset "C128ColumnKey"
    "0"` (80) or `"1"` (40) in the monitor.
  - The C128's other keys: TAB, HELP, LINE FEED, the function keys.
  - Colors on the VDC (the attribute memory), `txt` colors and scrolling.
- **The next release:** which of the new builds go in (`make release`
  copies the MEGA65 builds, not the PET, Plus/4, disk or C128 builds).

## Tests

- **A VIC-20 test runner** (with `xvic`).  `tests/vice/edtest.py` runs the
  C64, the PET (`--machine pet`) and the Plus/4 (`--machine plus4`).
- **cx16 tests.**  x16emu can only type keys by pasting text with `-bas`,
  so tests there are done by hand so far.
- **Intermittent failures with JiffyDOS** (`make test-jiffydos`): in 2
  of 3 full runs, suites of the REU and font builds failed (an extra byte
  at the end of a file read in, lines missing after a put, a hang), and
  in 1 of 10 runs of three suites; the stock ROMs had none in 10.  Not
  reproduced in 55 later runs on a quieter machine, so maybe host load
  or another test run at the same time (the runner's files in `build/`
  have fixed names, vt-<suite>.*).  The disk and plain C64 builds passed
  every time.
- **Intermittent failures:** in 2 of 6 full PET screen runs one suite
  failed (not the same one); the MEGA65 runner fails with "no answer"
  when the machine is very busy (its monitor reads time out after 5 s).
