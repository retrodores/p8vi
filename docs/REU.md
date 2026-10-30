# Extended memory: REU banking and `xmem`

The C64 and the Commander X16 can both show 8 KB "RAM banks" at
`$a000-$bfff`: the X16 in hardware, the C64 with an REU and the modules
below.  p8vi's page store keeps its text in them (`docs/XMEM-DESIGN.md`):
on the X16 through `xmem`, on the C64 with `reu.detect()` and `reu.cmd()`
only (1 KB pages copied to and from cache slots, not the 8 KB window).

## Files

| File | What |
|------|------|
| `src/c64/reu.p8` | REU driver: finds the REU and its size, switches 8 KB banks |
| `src/c64/reucompat.p8` | the X16's banking routines (`cx16.rambank()` ...) and banked `diskio.load()` on the C64 |
| `src/c128/reucompat.p8` | the same for the C128 (not tested) |
| `src/c64/xmem_platform.p8` | `xmem` for the C64, on `reu` |
| `src/cx16/xmem_platform.p8` | `xmem` for the X16, on its banked RAM from bank 2 |

`xmem` is the interface for p8vi: `xmem.init()` returns the number of
banks (0 without extended memory), `xmem.select(n)` shows bank n at
`$a000`.  Bank numbers start at 0 on both machines.  The C64 version
imports only `reu`, not `reucompat`, so a program using it keeps the
library's `diskio.load` and `x16jsrfar`.

`reu.p8` and `reucompat.p8` are a copy of a separate project; the
changes below are meant to go back there.

## Using `reu` and `reucompat`

```prog8
%import reu
%import reucompat

main {
    sub start() {
        uword kb = reu.init()       ; size in KB, 0 without an REU
        cx16.rambank(5)             ; bank 5 at $a000-$bfff
    }
}
```

- `reu.init()` finds the REU, sets `reu.present`, `reu.banks` (64 KB REU
  banks) and `reu.rambanks` (8 KB banks, at most 256 = 2 MB, like the X16),
  and fetches bank 0 into `$a000-$bfff`.  Finding the size doesn't change
  the REU's memory (see below), so a program can find its data again
  after a reset.
- `reu.bank(n)` (or `cx16.rambank(n)`) stashes the current bank and
  fetches bank n: 16 KB of DMA, about 18 ms.  A bank number past the end
  of a smaller REU lands on a lower bank.
- `reu.save(n)` stashes `$a000-$bfff` as bank n without switching, e.g.
  before saving an REU image.
- **Change tracking:** with `reu.track_changes = true`, a switch only
  stashes the current bank if `reu.modified` was set after writing to it,
  so a switch to read costs about 9 ms.  Without it, every switch
  stashes, which is always safe.
- `reucompat` replaces `diskio.load()`: a load into `$a000-$bfff` goes on
  into the following banks, like on the X16, and `diskio.load_size()` gives
  the size.  It also replaces `c64.x16jsrfar()` for `@bank` on `extsub`:
  banks 0-7 are the 6510's memory configurations, from 8 up REU banks.
- BASIC must be banked out, because the REU sees the same memory map as
  the CPU: a stash of `$a000` with BASIC in would save the ROM.  Prog8's
  startup banks BASIC out unless floats are used or `%option no_sysinit`
  is set.

## Finding the size

`reu.detect()` puts an 8 byte marker at `$fff8` in bank 1, 2, 4 ... 128
in turn, until a bank isn't there: the marker doesn't stay in it (a
1764 has no banks 4-7) or it shows up in bank 0 (a smaller REU repeats its
banks above its size).  Each marker is swapped in and back out with the
REU's swap command, so the REU's memory is left as it was.  It changes
`reu_addrcontrol` (to 0) and the address and length registers.

## Tests

`make test-reu` (VICE `x64sc` in the PATH) runs `tests/reu/reutest.py`:

- `tests/reu/reudetect.p8` with every REU size from 128 KB to 16 MB and
  without one: the size must be right and the REU's memory unchanged
  (checked at the start and the end of all 256 bank numbers).  With the
  old detection all sizes fail.
- `tests/reu/reureset.p8`: writes a pattern into the REU and waits; VICE
  is reset through its monitor (`reset 0`, like the reset button), the
  program starts again from a CBM80 hook in RAM and must find the pattern.

## Measured (VICE x64sc, prog8c 14.0-BETA3)

- All REU sizes, 128 KB to 16 MB, found; no REU: 0.
- Four banks filled, switched out of order: all intact.
- 60 switches: 66 jiffies (about 18 ms each); with change tracking and
  nothing modified, 33 jiffies (about 9 ms).
- `push_rambank(7)` from bank 3, then `pop_rambank()`: banks 7, then 3.
- `diskio.load("big.bin", $a000)` of a 12 KB file into bank 4: ends at
  `$b000` in bank 5, `load_size` 12288, the data in both banks right.
- `xmem` on the X16 (x16emu, 512 KB): 62 banks, data intact.

## Changes made to the original modules

To carry back to the original project:

1. `reucompat`: `diskio.load(str filenameptr, ...)` instead of `uword`.  A
   replacement with `%option merge` must have exactly the library's
   signature; with `uword` it was a second `load` and a compile error
   ("name conflict 'load'").
2. `reucompat`: `push_rambank()` didn't switch.  Prog8 passes a single
   byte parameter in A and `reu.bank()` starts with `sta p8v_banknum`, so
   the stored bank was overwritten by `current_bank`, which was in A at
   the `jsr`.  Now the bank is passed in A.  `rambank()`, `pop_rambank()`
   and `reujsrfar` pass it in A too, without the store to
   `p8b_reu.p8s_bank.p8v_banknum`.
3. `reucompat`: `reujsrfar` keeps X on the stack around the first bank
   switch, so the far routine gets the caller's X whatever `bank()` does
   with it.
4. `reu`: `save()` moved out of `bank()`, so it is `reu.save()` as the
   README said (it was `reu.bank.save()`).
5. `reu`: `detect()` returns `0, found` after the loop for 256 banks, not
   the loop variable, whose value after a `for` loop is undefined in Prog8.
   Also `for ... downto`, and `found = true` after the inner loop where it
   was meant to be.
6. `reu`: `init()` sets `reu_addrcontrol` to 0 (both addresses count up),
   in case an earlier program fixed one of them.
7. `reu`: `init()` computes the sizes (`banks = last bank + 1`,
   `rambanks = min(banks * 8, 256)`, `banks * 64` KB) instead of a table of
   known sizes, and returns 0 at once without an REU.
8. `reu`: `init()` fetches bank 0, so the first switch doesn't stash
   whatever was at `$a000` into bank 0.
9. `reu`: `track_changes` and `modified` (see above).
10. `src/c128/reucompat.p8`: changes 1 and 2 (it's `reucompat128.p8` in the
    original).
11. `reu`: `detect()` doesn't change the REU's memory (see "Finding the
    size"), and returns the last bank as 255 for 16 MB.  It returned 0
    for that, the same as for a 64 KB REU, and `init()` reported 64 KB
    (seen with the old `detect()` and `tests/reu/reudetect.p8`).  `init()` sets `reu_addrcontrol` before
    detecting rather than after.  It doesn't use `sys.memcmp()`, which
    doesn't assemble on the C64 with `%zeropage basicsafe`
    (`bugs/memcmp_c64_basicsafe.p8`).

## Open points

- The C128 version is untested.  Its `reujsrfar` doesn't switch back to
  the previous REU bank after the call (the C64 one does), and `bank()` may
  use zero page that overlaps `$02-$08`, where the KERNAL's JSRFAR keeps
  its arguments.  It also needs `reu.p8`, which is in `src/c64/`.
- The asm in `reucompat` uses the compiler's internal names
  (`p8b_reu.p8s_bank`, `p8b_reu.p8v_current_bank`), which can change
  between compiler versions.
- Bank numbers aren't checked against `rambanks`.
