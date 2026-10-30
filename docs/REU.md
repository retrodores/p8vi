# Extended memory: REU banking and `xmem`

The C64 and the Commander X16 can both show 8 KB "RAM banks" at
`$a000-$bfff`: the X16 in hardware, the C64 with an REU and the modules
below.  p8vi doesn't use them yet; they are the base for a bigger text
buffer, designed in `docs/XMEM-DESIGN.md`.

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
  and fetches bank 0 into `$a000-$bfff`.  It writes 9 bytes at the start
  of every REU bank to find the size.
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

## Measured (VICE x64sc, prog8c 14.0-BETA3)

- 512 KB REU: 512 KB, 64 banks; 16 MB REU: 16384 KB, 256 banks; no REU: 0.
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

## Open points

- The C128 version is untested.  Its `reujsrfar` doesn't switch back to
  the previous REU bank after the call (the C64 one does), and `bank()` may
  use zero page that overlaps `$02-$08`, where the KERNAL's JSRFAR keeps
  its arguments.  It also needs `reu.p8`, which is in `src/c64/`.
- `detect()` writes into every REU bank.  It has to stop doing that
  before p8vi keeps text in the REU, so that text can be recovered after
  a crash or a reset: see "REU detection without writing" in
  `docs/XMEM-DESIGN.md`.
- The asm in `reucompat` uses the compiler's internal names
  (`p8b_reu.p8s_bank`, `p8b_reu.p8v_current_bank`), which can change
  between compiler versions.
- Bank numbers aren't checked against `rambanks`.
