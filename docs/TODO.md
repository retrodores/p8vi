# p8vi: possible future work

Ideas and known problems for p8vi, roughly by kind, not by priority.
`docs/KEYS.md` lists the vi commands that are done and the ones that
aren't.

## vi commands

- **Line ranges for more commands:** `:1,5d`, `:.,$y`, `:1,10w name`.
  `:s` has them (`read_range()`).
- **Scrolling the view:** Ctrl-E / Ctrl-Y (scroll one line), and
  `z<Return>` `z.` `z-` (`zt` `zz` `zb` and the first non-blank).  `zt`
  `zz` `zb` (`features.Z_VIEW`, about 145 bytes) are off on the VIC-20,
  X16, p8vi-mega65dma (no room), p8vi-c128x (the main-RAM page slot),
  p8vi-c64font (the REU slots) and the TRS-80 (edtest's big suite no
  longer fit).  They put the cursor's row at the top or
  bottom, where vi puts the first or last row of a long line.
- **`:set number`** (`features.NUMBER`, done): about 740–800 bytes, 870 on the
  TRS-80 Model 4 (Prog8's calls and loops; the logic is small).  Off on the
  VIC-20 (and 22 columns), X16 (both builds) and p8vi-mega65dma: no room.
  It leaves p8vi-c128reu 113 bytes and p8vi-c128x 242, and takes 800 of the
  PET's 3.3 KB of text (it could go off there).  The numbers are 5 digits and
  a space, so a 40-column screen has 34 for text.  Still to do:
  - `:set relativenumber`: the same count without adding `cur_line`;
  - a width that grows with the line count, as vi's (4 to start);
  - rewriting `draw_row`'s number and `number_rows` in assembler, to
    bring it to the X16.
- **More marks:** forgetting a mark when its line is deleted, as vi does
  (now it stays where the deletion was).  (`''` and ``` `` ``` are done.)
  Marks (`features.MARKS`, about 400 bytes) are off on the VIC-20, X16,
  p8vi-mega65dma, p8vi-c128x (it would lose its main-RAM page slot),
  p8vi-c128reu, p8vi-c64font (its REU slots ran short: the reu-in-use
  check failed) and the TRS-80 (6% of its text; edtest's big suite no
  longer fit the test build).
- **`&` on the X16 and in `p8vi-c128reu`** (`features.REPEAT_SUBST`,
  about 115 bytes and a 40 byte copy of the last `:s`): the X16's main RAM
  is full, and in `p8vi-c128reu` the copy would push the page slot out of
  `$1300-$1bdf` (32 bytes are left).  The C128's sprite area (`$0e00`)
  could hold the copy.  `g&` (`:%s` again) isn't there either.

## Known problems

- **Keys typed ahead during a failed load are lost.**  For example after
  `:r nofile`.  See `bugs/diskio_missing_file.md`, part 2.
- **An extra empty line at the end of a file, on the VIC-20.**  Fixed on
  the C64 and X16 (`features.FINAL_EOL`: the text doesn't keep a file's
  last line ending, writing puts it back), but it costs about 100 bytes
  the VIC-20 doesn't have, so there a file that ends with a line ending
  still shows an empty last line.
- **Saving with a drive or path prefix** (`:w 0:name`, `//dir/:name`):
  fixed with `features.PREFIX` (164 bytes; the scratch and rename commands
  keep the prefix in front, and the temporary file goes to the same place),
  but it is off where there's no room: p8vi-vic20, p8vi-cx16 and
  p8vi-mega65dma (too long by 59-98 bytes) and p8vi-c128reu (it would
  lose a page slot).  There the library's delete and rename put `s:` and
  `r:` before the whole name, which a prefix doesn't survive.  Only `0:` is
  tested (the `prefix` suite); `//dir/:` needs a CMD drive or SD2IEC.
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
- **ISO mode on the X16** (`build/p8vi-cx16iso.prg`, `src/p8vi_cx16iso.p8`):
  the text, keys and screen in ISO-8859-15 (`txt.iso()`), so ASCII files
  show as they are, `{ | } ~ _` included.  Every module of the program is
  compiled with `%encoding iso`, from copies `tools/encode_copy.py` makes in
  `build/cx16iso` (`bugs/encoding_option.md`); the library keeps PETSCII.
  `features.ISO`: `features.ASCII` off (nothing to translate), the cursor
  shown by swapping the colors (`platform.color_cursor`), `:@` commands'
  letters before the `:` in capitals (CMDR-DOS wants `S:`, not ISO's `s`),
  PETSCII again at `:q`.  276 bytes free, against the PETSCII build's 104.
  Tried in x16emu (ROM R49) on HostFS and on an SD card image:
  - `:e`, edits, `:w`, `:@s:name` and `:@$` all work;
  - CMDR-DOS stores names as typed, so the ISO build writes `new.txt` and
    `Mixed.txt`, where the PETSCII build writes `NEW.TXT` and `ÍIXED.TXT`.

  Still to do:
  - check the real keyboard's codes in ISO mode (the test typed raw bytes
    through `-bas`): the cursor keys, DEL, Esc, Ctrl;
  - the rows after the text could show vi's `~` (EMPTY_ROW is `-`);
  - new texts still get CR endings, where LF may suit ISO better;
  - PETSCII files show wrong, as there's no `:set ascii` the other way;
  - put it in `release/`.
- **The start screen** is off on the VIC-20 (its room went to the safe
  save) and on the X16 (`features.SPLASH`).
- **More text on the VIC-20.**  With RAM in block 5 the text is at
  `$a000-$bfff` (8 KB).  The main RAM after the program was the idea for a
  second text area (a gap buffer split across two memory areas), but the
  program now reaches almost to `$8000`.  Room would have to come from
  features switched off, or from the 3 KB expansion at `$0400-$0fff`.
- **Several files open at once** (multiple buffers).
- **The font build** (`p8vi-c64font`, the OSCII font in `oscii.fnt`): a
  fallback when `oscii.fnt` is missing (it
  stops with "can't load oscii.fnt"); whether the plain C64 build (gap
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
  - The PET has no Ctrl key: `@` then a letter is Ctrl in normal mode
    (`features.CTRL_AT`, as on the TRS-80; 133 bytes), RVS gives Ctrl-R.
    Ctrl-W in insert mode (delete a word) still can't be typed.
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
    p8vi-c128reu's REU).  It is also a font build: oscii.fnt (the C64
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
- **TRS-80 Model III with LDOS** (`p8vi-trs80.cmd`, `make trs80`; llvm16
  with the z80-trs80-cmd profile, llvm-z80 and z88dk; src/trs80).  Edits,
  saves and reads files (checked by hand in trs80gp, 2026-11-08); about
  9.6 KB for text with LDOS's HIGH$ at $FFFF (6.6 KB before the compiler's
  -Oz default, 2026-11-10).  Keys: shift + up arrow is
  Escape, BREAK too, the left arrow is backspace (DEL), shift + left moves
  left, Ctrl is shift + down arrow + a letter, or @ then a letter in
  normal mode.  p8vi clears the caps lock
  flag ($4019) and moves LDOS's blinking cursor ($4020) out of the way,
  and puts both back on :q.  `make test-trs80` runs edtest's file suites
  (16 of them, not the CBM ones) with a test build that plays its keys from
  KEYS/TXT (features.KEYFILE, `make trs80-test`), through FreHD's IMPORT2
  and EXPORT2 in trs80gp (tests/trs80/trstest.py).  Open:
  - Screen tests.  trs80gp's paste (`-i`) doesn't reach p8vi's keyboard
    polling, and after a key typed on its keyboard matrix (`-ik`) a file
    open hangs (not with the real keyboard); a JCL file (`DO`) can't drive
    it either.  temp/docs/trs80-ldos-notes.md has the details.
  - Saves are slow: about 6.5 s of turbo trs80gp time per :w on top of
    the writing, nearly all the DOS's directory work (about 8 searches:
    deletes, opens, the copy).  The safe save uses diskio.rename(), the
    profile's copy and delete (no DOS call renames), and checks
    diskio.status_code() after it.  Left as it is on purpose: when the
    compiler's rename gets faster, use that.
  - Scrolling (features.SCROLL) copied the wrong memory until 2026-11-09
    (`VIDEO + (r + count) as uword * COLUMNS` is `(VIDEO + r + count) *
    COLUMNS`: the ROM, so nothing moved) and no test looks at the screen.
    The text room was down to a few bytes for edtest's big g3 (STACK_ROOM
    went from 512 to 256 for the fix's 10 bytes); -Oz gave 3.5 KB back.
- **TRS-80 Model 4** (`p8vi-trs80m4.cmd`, `make trs80m4`; the z80-trs80-m4
  profile; src/trs80m4, with src/trs80's other files).  TRSDOS 6 or
  LS-DOS 6.3, 80 x 24.  About 15 KB for text, so marks and zt zz zb
  are in.  z88dk's AMALLOC makes the heap only 75% of the memory below the
  stack: the platform uses the rest as spare memory (the key buffers), and
  FILE_ROOM is 1 KB (the DOS renames: one file open at a time).  The
  profile could do this itself: `-pragma-define:CRT_STACK_SIZE=512` gives
  the heap everything but the stack.  The screen: rows and scrolling go straight to the video RAM at
  $f800 (memory map 2, port $84; TRSDOS 6 leaves it on), with interrupts
  off; the cursor is the DOS's own (DOS_CURSOR: txt.plot and display
  codes 14/15), which it blinks, off while the screen is drawn.  Keys from
  @KBD: up 11, down 10, left 8, right 9, BREAK 128, shift + up 27, CTRL
  + letter 1-26, F1-F3 129-131.  The DOS renames files.  `make
  test-trs80m4` runs the file suites (19, with marks and zview) in trs80gp
  with the LS-DOS 6.3 utility disk (`:lu4`, IMPORT2 and EXPORT2) and a
  test build (`make trs80m4-test`; trstest.py --model 4).  If the DOS's
  cursor ever misbehaves, DOS_CURSOR false gives p8vi's own (a blink
  every 400 keyboard polls looked right in trs80gp).  Open:
  - **p8vi-trs80m4x** (`make trs80m4x`, done): the text in the second
    64 KB, up to about 60 KB (62 pages of 1 KB and two headers for :rec),
    src/trs80m4x.  Port $84 bits 6-4 = 110 / 111 put one of its 32 KB
    halves at $0000-$7fff (MAME's table; trs80gp does it; not yet seen on
    a real Model 4): a copy routine above $8000 does the copying with
    interrupts off, between that window and 2 to 4 slots above $8000 (as
    many as fit: the program is about 43 KB, the page store is big in Z80
    code).  The start screen, marks, zt zz zb and SCROLL are off for room.
    fastmem has Prog8 loops here (the page store needs them; the TRS-80's
    were stubs, the gap buffer has its own).  `make test-trs80m4x` runs the
    file suites with -mem 128, and the page store's (not huge).  `:rec`
    works after a reset in trs80gp (`-ictl reset`; the sync needed a
    clock: `ticks()` is the compiler's `sys.ticks()`, 60ths of a second, since
    2026-11-10): tests/trs80/rectest.py in `make test-trs80m4x`.  Open: a 64 KB Model 4 falls
    back to main RAM with only a page or two (use p8vi-trs80m4 there); an
    NMI while a page is in the window would find no handler.
  - The function keys (F1-F3), `:r $` / `:@$` (the DOS has a directory).
  - Screen tests: trs80gp's `-it` writes the text screen to a file.
- **TRS-80 Model I** (not supported yet; tried in trs80gp on 2026-11-10 with
  the v0.3.1 `p8vi-trs80.cmd`).  The Model III build runs unchanged: under
  LDOS 5.3.1 (`-m1 -ld`) and TRSDOS 2.3 (plain `-m1`) it starts and shows
  the start screen.  All 17 file suites pass under LDOS (with trstest.py
  given a model `'1': (['-m1'], ':lu1', ...)`, as for model 3).  The
  suites play keys from a file, so they miss what's wrong:
  - **Letter case swapped** when typing ("Hello" comes out as "hELLO").
    platform.init writes 0 to `$4019`, the Model III ROM's caps lock flag.
    On a Model I that is something else, so don't write it there.  The
    Model I's keyboard gives capitals unless shifted: swap the case of
    letters from `txt.getkey()`.
  - **No cursor.**  blink_timer reads `$4216` (LDOS's timer on the Model
    III), which doesn't count on a Model I: the cursor is never drawn.
    `sys.ticks()` is 0 on a Model I (compiler docs), so show it without
    blinking, or count passes through the key loop.
  - **Without the lower-case kit** (`-nlc`) lower case shows as symbols
    (bit 6 of the video RAM is missing): "Prog8 VI (p8vi)" is
    `P2/'8 VI (086))`, and the `~` rows are `>`.  Test for the kit at the
    start (write a lower-case letter to the video RAM and read it back), and
    without it show everything in upper case.
  - Telling the models apart: the ROM byte at `$0125` is `I` (73) on a
    Model III (the usual check; not verified here yet).  One `.cmd` can
    serve both.
  - Keys typed with `-ik` faster than hold/gap 15/15 frames get lost or
    garbled on both models (test timing, not p8vi).
  - Better done in the compiler's profile (bugs/trs80_model1_support.md):
    `sys.ticks()`, the model, `txt.getkey()`'s case and the lower-case test.
- **CP/M** (`p8vi-cpm.com`, `make cpm`; llvm16 z80-cpm; src/cpm).  A
  terminal screen kept in memory, sent as changes: `-t ansi` (default),
  `vt52` (tnylpo's full screen), `adm3a`.  Checked in tnylpo (all three
  terminals give the same screen as a Ctrl-L redraw) and on the TRS-80
  Model 4 with Montezuma Micro CP/M 2.2 in trs80gp (`-t adm3a` works;
  17,202 bytes free with its 64K CP/M; `make emu-trs80m4-cpm` boots a
  copy of the system disk with a data disk in drive B made by
  tools/cpm/m4disk.py).  Also tried by hand on the C128's CP/M 3.0 in
  x128 (2026-11-10): `-t adm3a` works on both screens, 20,914 bytes free,
  but slow.  Its 40 column screen is a window on an 80 column console
  (CP/M says 80 columns), so p8vi draws 80 wide there.  Getting files on
  was the hard part: cpmtools has no C128 formats; a CP/M tool (rdcbm)
  read p8vi.com off a 1541 .d64.  Not a practical target.  Open:
  - Tests (`make test-cpm`, tests/cpm): edtest's file suites and its
    screen suites on each terminal (against a Ctrl-L redraw) in tnylpo,
    and a smoke test on Montezuma CP/M in trs80gp (m4test.py, only with
    the disk image: CPM_DISK or build/cpm222_work.dsk).  Each is skipped
    without its emulator.
  - Arrow keys (2026-11-10): txt.escape_key reads ANSI's ESC [ A-D, Home
    (ESC [ H, 1~, 7~), Page Up/Down (5~ 6~: Ctrl-B/F), drops the
    sequences it doesn't know, and with -t vt52 ESC A-D.  `make emu-cpm`
    runs tnylpo -s -w (VT52 arrows; without -w it sends WordStar's ^E ^S
    ^D ^X, which are vi keys).  Checked in tnylpo -s -w through a pty.
    Not ADM-3A's (^K ^J ^H ^L are vi keys too), nor Montezuma's arrows
    (unknown: try them in trs80gp).  On CP/M a sequence's bytes must come
    within 255 console polls; a fast typist's Escape then A on VT52 could
    be taken for up.
  - Montezuma's keyboard: capitals until CAPS is pressed; BREAK is
    Escape.  Keys typed while the floppy is read are lost (no type-ahead);
    txt.flush() asks for keys every 16 characters, so typing during a
    screen update is kept.
  - A Montezuma console driver of its own (its codes beyond ADM-3A:
    clear to end of line would save a lot of spaces), and the C128's CP/M
    (ADM-31: clear to end of line).
  - `-40` draws 40 columns wide (70 bytes; for the C128's 40 column
    window, which CP/M reports as 80; checked in tnylpo, and by the user
    on the C128 in x128: the splash is centred, lines wrap at 40).  Other sizes (`-w`, `-h`, or CP/M 3's SCB, BDOS 49) only if a
    terminal needs them.
  - The C128's RUN/STOP isn't Escape, and won't be: its ESC key is in a
    good spot, and Ctrl-C is Escape too (KEY_STOP).  RUN/STOP sends
    nothing: the BIOS key table (4 codes a key: plain, caps, shift,
    control; at $1290 in bank 0 in the 28 May 87 BIOS, RUN/STOP at $138c)
    has 00 00 00 f0 for it.  CP/M's KEYFIG can give it $1b.
  - The z80-cpm profile doesn't turn on z88dk's heap (the Makefile's link
    options do) and its txt has no getchr and plots 0-based to ANSI (one
    row and column off): worth a note to the compiler side.
- **Host version** (`build/p8vi-host`, `make host`; llvm64 and clang;
  src/host with src/cpm's screen and src/trs80's charset).  A program for
  this machine in a terminal: `p8vi-host [-t ansi|vt52|adm3a] [-40]
  [file]`.  The terminal is the console (src/host/console_platform.p8:
  the library's getkey/waitkey syscalls, raw mode from the first key);
  src/cpm/console_platform.p8 is CP/M's.  New files get LF; the safe
  save's p8vi.tmp goes in the file's directory (PATH_SEP '/').  Checked
  on macOS (arm64), 2026-11-10: edtest's file suites (19) and screen
  suites (18, on the three terminals) pass with the keys piped in (a
  scratch run of tests/cpm/cpmtest.py), and in a pty a lone ESC, Ctrl-C
  and :wq work.  `make test-host` runs them (cpmtest.py --host: the keys
  on stdin; the screen compared is the one before :q! clears it).  The
  runtime's waitkey flushes stdout before it waits since the compiler of
  2026-11-11 (bugs/llvm64_waitkey_flush.md): an older one shows no
  screen.  Open:
  - The text is the 16-bit editor's: 64 KB at most.
  - The screen is 80 x 24 (or -40); the terminal's own size isn't asked.
  - Arrow keys: the runtime's getkey gives the arrows' codes itself
    (ESC [ A, ESC [ 1;2A, ESC O A: the same as the editor's); Home, Page
    Up/Down, unknown sequences and VT52 are txt.escape_key's.  Tested by
    cpmtest.py --host's ansi-keys and vt52-keys suites.
  - llvm32 (wasm with WASI: no raw keyboard there), Linux and Windows
    builds not tried.
- **Color Computer 2 and 3** (not started; llvm16 `mc6809-coco`).  Both are
  blocked by the 6809's code size today.  The same program's code is 4.5
  times the Z80's at -O2, mostly from inlining, so p8vi would be over
  100 KB.  With size attributes and no PIC it would still be about 1.36
  times the Z80's (bugs/mc6809_code_size.md, being looked at on the compiler
  side).  The coco profile also has no file I/O yet (`diskio` always fails),
  and its `txt` goes through BASIC's character output.
  - **CoCo 2 (64 KB), a plan.**  Under Disk BASIC, $0E00-$7FFF (28.5 KB) is
    free, too little for code and text.  In all-RAM mode (the SAM's TY bit:
    $FFDF on, $FFDE off) $8000-$FEFF is RAM too.  Nothing from the ROM needs
    copying if the editor only goes back to the ROM for DSKCON:
    - $0000-$0DFF: left alone (BASIC's and Disk BASIC's variables,
      DSKCON's request block at $00EA, its drive variables up to about
      $0988, the interrupt vectors at $0100-$0111, the screen at $0400).
    - $0E00-~$10FF: the stub that switches to ROM mode, calls DSKCON
      ([$C004]) and switches back; a 256-byte sector buffer; the stack.
    - ~$1100-$7FFF: the text, about 27 KB, used directly (RAM in both
      modes, no banking).
    - $8000-$FEFF: the editor's code and variables, 32,512 bytes.  It fits
      only if the 6809's code comes close to the Z80's, or with features
      left out as on the VIC-20.
    - Check in XRoar whether the CPU's vectors ($FFF2-$FFFF) come from the
      ROM or from the RAM at $BFF2 in all-RAM mode.  To be safe, copy the
      ROM's 16 bytes at $BFF0 to RAM.
    - Loading: writes in ROM mode don't reach the RAM under the ROM, so the
      image goes up in pieces.  Either a BASIC program does `LOADM"ED1",offset`
      of about 16 KB at a time into low RAM, with a few bytes of code that
      switch modes and copy each piece up, or a small loader reads the
      image a sector at a time with DSKCON and copies it.  Then the stub
      starts the editor.
    - Interrupts: in all-RAM mode BASIC's handlers jump into the editor's
      code, so the editor needs its own 60 Hz IRQ handler (it reads $FF02
      to clear the interrupt, and counts ticks).  Disk BASIC's IRQ turns the
      drive motor off, so the disk stub does that itself (0 to $FF40), or
      puts BASIC's handler back while it is in ROM mode.
    - Screen and keyboard without the ROM: a platform `txt` that writes to
      the VDG screen at $0400 (32x16, no lower case) and scans the keyboard
      through the PIA at $FF00/$FF02.  A 256x192 screen with p8vi's font
      would give lower case and more columns, but costs 6 KB of the text.
    - Files: DSKCON only reads and writes sectors, and Disk BASIC's file
      routines aren't meant for machine code.  So it needs an RS-DOS layer
      of 1-2 KB, which can sit in high RAM: the FAT is in sector 2 of track
      17, the directory (32-byte entries) in sectors 3-11, and a granule
      is 9 sectors (68 to a disk).  p8vi reads and writes whole files, so it
      never needs to seek.  This could go in the compiler's coco profile as
      `diskio`, for every CoCo program.
    - The compiler: a layout with the code and variables at $8000, the stack
      in low RAM, no BASIC calls, and a way to call the low-RAM disk stub.
    - A 16 KB or 32 KB CoCo 2 has no all-RAM mode.
  - **CoCo 3.**  It has more RAM, through the GIME's 8 KB MMU pages, an
    80-column text screen with lower case, and the same 6809 code-size
    problem.  The text could go in MMU pages, like the m4x's second 64 KB.
    It still needs the file layer and its own `txt`.
    (XRoar's `-type` drops keys on a CoCo 3, so tests would need another way
    to type keys, see the compiler's coco-build notes.)

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
