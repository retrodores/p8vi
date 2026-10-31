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

## Memory

- **Text in extended memory** (the cx16's banked RAM, a C64 REU): files
  up to 64 KB fit, with yank and undo as big, and `:recover` after a crash
  (done, `docs/XMEM-DESIGN.md`).
- **The X16's main RAM is full** (43 bytes left; the key buffers
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

## Tests

- **A VIC-20 test runner** (with `xvic`).  `tests/vice/edtest.py` only runs
  the C64 version now.
- **cx16 tests.**  x16emu can only type keys by pasting text with `-bas`,
  so tests there are done by hand so far.
