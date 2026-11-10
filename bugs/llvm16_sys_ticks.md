# Request: sys.ticks() for the llvm16 targets (TRS-80, CoCo)

**Done** in prog8c-llvm (2026-11-10), in 60ths of a second on every
target (`sys.TICKS_PER_SECOND` = 60); p8vi's TRS-80 `ticks()` uses it.

A prompt for the prog8c-llvm (compiler) side, from p8vi, 2026-11-10.

---

Add a free-running clock to the llvm16 targets' `sys`:

```prog8
const ubyte TICKS_PER_SECOND = 30   ; per target: 30 on the TRS-80, 60 on the CoCo
sub ticks() -> uword                ; counts up TICKS_PER_SECOND times a second, wraps at 65536
```

## Why

Programs need a clock for timeouts, cursor blinking, key repeat, animation
and "do this after N seconds idle".  The CBM targets have one
(`cbm.RDTIM16()`, the KERNAL's 60 Hz jiffy clock, kept up to date by its
interrupt), but the llvm16 z80 and 6809 targets have only `sys.wait()`.
So each program has to find a DOS counter on its own.

p8vi (a vi for 8-bit machines) needed one so that it syncs its text for
crash recovery after half a second without a key.  On the Model 4 it had
no clock, so the sync never ran and recovery after a reset could not
work.  It now polls a byte:

```prog8
const uword TICK_COUNT = $002c      ; LS-DOS 6: +1 per 30 Hz interrupt, wraps at 256
ubyte last_tick
uword clock
sub ticks() -> uword {
    ubyte t = @(TICK_COUNT)
    clock += t - last_tick          ; byte subtraction: right across the wrap
    last_tick = t
    return clock
}
```

This only works if it is called more often than every 256 ticks (8.5 s).
Otherwise whole turns of the counter are lost.  On the Model III (LDOS
5.3) p8vi uses `$4216` (30ths of a second, counting down) and `$4217`
(the seconds), which only work within a minute.  A library version should
have neither limit.

## How (suggested)

1. **Count in the interrupt.**  The profile's startup code adds a small
   task to the DOS's 30 Hz interrupt chain that increments a 16-bit (or
   32-bit) counter.  `sys.ticks()` then just reads it, with interrupts off
   for the two bytes, or by reading until two reads agree.
   - LS-DOS 6 / TRSDOS 6 (`z80-trs80-m4`): `@ADTSK` (SVC 29) adds an
     interrupt task to a task slot, and `@RMTSK` (SVC 30) removes it.
     Check the slot numbers that are free for user tasks in the LS-DOS 6
     technical reference; slots 0-7 run on every interrupt.
   - LDOS 5.3 Model III (`z80-trs80-cmd`, `z80-trs80`): LDOS has `@ADTSK`
     / `@RMTSK` too (different SVC entry points: check the LDOS 5.3
     manual).  TRSDOS 1.3 (`z80-trs80-m3-trsdos`) has none: there,
     fall back to polling (3).
   - The CoCo (`mc6809-coco`): BASIC's TIMER at `$0112` is already a
     16-bit 60 Hz counter, so `ticks()` can just read it.
2. **Remove the task when the program ends** (the exit path, `sys.exit()`
   and the normal return), or the DOS will call into freed memory after
   the next program loads.  BREAK, or a DOS error that aborts the
   program, should not leave it installed either.  If that can't be
   guaranteed, place the task in memory the DOS won't reuse, or document
   it.
3. **Fallback where no task can be added:** the polling version above,
   with its limit documented (call it at least every 8 seconds).  On LS-DOS
   6 the byte is `$002c` (found by comparing memory in trs80gp under
   LS-DOS 6.3, with the seconds at `$002d` and the minutes at `$002e`.
   This is not from the documentation, so verify it).  On LDOS 5.3 use
   `$4216`/`$4217`.
4. **Units:** keep the native rate and give `TICKS_PER_SECOND` (30 on the
   TRS-80, 60 on the CoCo), so `ticks()` counts by one.  Scaling to 60ths
   to match `sys.wait()`'s jiffies would make the TRS-80's count go up by
   two at a time.  Either way, document the rate.
5. **Only link it when it's used**, so programs that never call
   `sys.ticks()` don't pay for the task.

## To check

- In trs80gp (Model III with LDOS, Model 4 with LS-DOS 6.3): print
  `sys.ticks()` before and after `sys.wait(120)`.  The difference should
  be about 60 at 30 Hz.  Loop past 65536 to see the wrap.
- Run the program twice in a row, and also break out of it with BREAK:
  the second run and the DOS keep working (the task was removed).
- Disk I/O: the DOS turns interrupts off during floppy access, so the
  clock may lose ticks while a disk is in use.  That's acceptable;
  document it.

## How p8vi will use it

`ticks()` in src/trs80/platform.p8 and src/trs80m4/platform.p8 becomes
`return sys.ticks()`, and p8vi's `SYNC_DELAY` (now 30, in "jiffies") uses
`sys.TICKS_PER_SECOND / 2`.
