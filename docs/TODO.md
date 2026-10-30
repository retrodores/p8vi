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

## Disk

- **Read the directory into the text:** `:r $`, since `$` is the
  directory's file name on a CBM drive.  The drive sends the listing as a
  BASIC program (block counts as line numbers), so it needs turning into
  lines of text, or `diskio.lf_start_list()` / `lf_next_entry()` can
  give just the file names.  `dir_cmd()` (`:@$`) already reads the
  listing.  Off on the VIC-20.

## Known problems

- **Keys typed ahead during a failed load are lost.**  For example after
  `:r nofile`.  See `bugs/diskio_missing_file.md`, part 2.
- **An extra empty line at the end of a file.**  Every line ending starts a
  new line, so a file that ends with a line ending shows an empty last
  line.  vi treats the last line ending as the end of the last line.
- **The VIC-20 status line** is only 22 columns: 12 for messages and 10 for
  the line,column position.  Check what gets cut short and whether the two
  parts can run into each other.

## Speed and size

- **One-row scrolls:** scroll the screen and draw one new row, instead of
  redrawing the screen.
- **Gap buffer fields:** make the gap buffer's internal variables
  `private`, so the editor only uses its subroutines.

## Memory

- **A bigger undo log on the cx16.**  The yank buffer, undo log (2 KB) and
  key buffers are in RAM bank 1 (8 KB) and use about 3.4 KB of it, so about
  4.7 KB is unused.  Choosing the undo size at run time costs the VIC-20
  bytes, so it may need a feature switch (see `docs/FEATURE-SWITCHES.md`).
  Left for later, after some of the other items.
- **More of the cx16's banked RAM,** for example for the text itself, so
  files bigger than about 12 KB fit.
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
