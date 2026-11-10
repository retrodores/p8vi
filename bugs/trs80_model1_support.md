# Request: TRS-80 Model I support in the z80-trs80-cmd profile

A prompt for the prog8c-llvm (compiler) side, from p8vi, 2026-11-10.

---

Make the `z80-trs80-cmd` profile behave the same on a TRS-80 Model I as
on a Model III.  Programs built for it already load and run on a Model I,
and its file routines work there.  But the clock, the keyboard's letter
case and the screen's lower case differ, and a program can't tell which
machine it's on.  Please add the items below to the library, so a
program can handle both with one `.cmd`.

## What was found

p8vi (a vi for 8-bit machines) was tried in trs80gp on a Model I.  Its
`p8vi-trs80.cmd` is built with `z80-trs80-cmd` for the Model III and
LDOS.

- It runs unchanged under LDOS 5.3.1 (`trs80gp -m1 -ld`) and TRSDOS 2.3
  (plain `-m1`).
- All 17 of p8vi's file test suites pass on the Model I under LDOS:
  loading, saving over a file, `diskio.rename`, and files of about 9 KB.
  The test runner is p8vi's tests/trs80/trstest.py, with
  `(['-m1'], ':lu1', ...)` as the machine.
- **Letter case.**  Typing "Hello Model I" gives `hELLO mODEL i`.
  - p8vi turns off the Model III ROM's caps lock by writing 0 to `$4019`.
    On a Model I that address means something else.
  - The Model I keyboard gives capitals unless shifted.
- **The clock.**  p8vi blinks its cursor by LDOS's Model III timer at
  `$4216`, which doesn't count on a Model I, so the cursor never shows.
  `sys.ticks()` is documented as 0 on a Model I, and `sys.wait()` returns
  at once there.
- **Lower case on the screen.**  A Model I without the lower-case kit
  (trs80gp `-nlc`) has no bit 6 in its video RAM, so lower case shows as
  symbols.  `Prog8 VI (p8vi)` comes out as `P2/'8 VI (086))`, and `~` as
  `>`.  Many Model Is have the kit, but a stock one doesn't.
- **Typing in trs80gp.**  Keys typed with `-ik` (hex mask, then the row
  set back to 0) get lost or garbled on both models with a hold and gap of
  6 frames.  At 15/15 they arrive.

## What to add

1. **`sys.ticks()` and `sys.wait()` on the Model I.**
   - Under LDOS 5.3 on the Model I, add an interrupt task as on the Model
     III (the `P8TICKS` module).  The Model I's interrupt runs 40 times a
     second, not 30, so the step that makes 60ths differs: 3 ticks of 60
     for every 2 interrupts.
   - Under TRSDOS 2.3, find a counter the DOS keeps up to date (the 25 ms
     heartbeat at `$4040` is a guess: check it by comparing memory, as was
     done for LS-DOS 6's `$002C`), or hook its interrupt chain.  If that
     can't work, document that it is 0.
   - The Model I acknowledges its interrupts differently from the Model
     III (the latch at `$37E0`, not port `$E0`).  That matters for the
     task's entry code, if it does more than the DOS's chain.
2. **The model and the DOS.**
   - Something like `sys.trs80_model() -> ubyte`, giving 1, 3 or 4.  The
     usual check is the ROM byte at `$0125`: `I` (73) on a Model III.
     Verify it on both models in trs80gp, and check that it doesn't
     mistake a Model 4 in Model III mode for something else.
   - A way to tell LDOS, TRSDOS 2.3 and TRSDOS 1.3 apart, for programs
     that use DOS addresses.
3. **The keyboard: the same on both models.**
   - `txt.getkey()` and `txt.waitkey()` give lower case unshifted and
     capitals shifted, on the Model I and the Model III.
   - On a Model III, save the ROM's caps lock (`$4019`), turn it off, and
     put it back at exit.  On a Model I, swap the case of the letters.
     Leave `$4019` alone there.
   - Optionally, `txt.caps_lock(bool on)` for programs that want
     capitals.
   - Check that the arrows, BREAK, CLEAR and ENTER give the same codes on
     both: on the Model III they are up 91, down 10, left 8, right 9,
     BREAK 1, CLEAR 31 and ENTER 13.
4. **Lower case on the screen.**
   - `txt.has_lowercase() -> bool`: write a lower-case letter to the
     video RAM (`$3C00`), read it back, and restore the cell.  Without the
     kit, bit 6 is lost.
   - Optionally: without the kit, `txt.chrout`, `print` and `setchr` show
     lower case as capitals, so that text stays readable.  `getchr` then
     returns the capital.
5. **The cursor.**
   - `txt.cursor_on()` and `cursor_off()`, as the `z80-trs80-m4` profile
     has them.
   - Under LDOS on the Model III, the DOS's blinking cursor is kept at
     `$4020` (position) and `$4023` (character).  p8vi points it at a
     spare byte, as it blanked the status line's first column.  Check
     what the Model I uses under LDOS and TRSDOS 2.3.
6. **Tests and documentation.**
   - A Model I test profile for trs80gp, next to `trs80gp-m3.properties`:
     `-m1 -ld`, plus `-m1 -nlc` for a machine without the kit.
   - A section in `trs80-build.md` on the Model I: what works, which DOSes
     were tried, and what is 0 or missing.

## To check

- In trs80gp, on the Model I (`-m1 -ld`, `-m1`, `-m1 -nlc`) and on the
  Model III (`-m3 -ld`):
  - `sys.trs80_model()` gives the right number.
  - `sys.ticks()` goes up by about 120 across `sys.wait(120)`.
  - A program that echoes `txt.waitkey()` shows lower case when unshifted
    and capitals when shifted.
  - `txt.has_lowercase()` is false with `-nlc` only.
- On a Model III, caps lock is back as it was after the program ends.

## How p8vi will use it

- p8vi's src/trs80/platform.p8 drops its own `$4019` caps lock code and
  its `$4216` cursor timer, and uses `sys.ticks()` for both.
- Without the kit it shows its text in capitals.
- The same `p8vi-trs80.cmd` then runs on the Model I and the Model III.
- See docs/TODO.md ("TRS-80 Model I") in the p8vi repository.
