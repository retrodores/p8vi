# The mc6809 (CoCo) builds are 2-4.5 times the size of the Z80 builds

From p8vi, 2026-11-10, for the prog8c-llvm (compiler) side: a prompt for Claude.

---

The same Prog8 program builds into 2 to 4.5 times as much code for
`-triple mc6809-coco` as for `-triple z80-trs80-cmd`.  The 6809 backend can do
much better: most of the difference is inlining.  Prog8's IR has no `optsize`
or `minsize` function attributes, and the mc6809 backend's inliner then
inlines very freely.  Find out why, and make the llvm16 builds optimize for
size.

## Measurements

All the numbers are the `.text` of the object, from `llvm-size`.  The objects
were compiled by hand from the `.ll` that prog8c wrote, with the same clang as
the profiles use (`$LLVM_MC6809/bin/clang --target=mc6809-unknown-decb`,
`$LLVM_Z80/bin/clang --target=z80`), at `-O2` unless the table says otherwise.

**p8vi's gap buffer self-test** (`src/gaptest.p8` from the p8vi repository).
To build it, use `-srcdirs src:src/trs80`, and replace its `sys.progend()`
with a static `ubyte[64]` buffer: the llvm16 targets have no `progend`.

| Build | 6809 | Z80 |
|---|---|---|
| -O2 (what prog8c does) | 65,236 | 14,078 |
| -O1 | 63,570 | |
| -Os, -Oz | 65,236 (no change) | |
| -O0 | 36,131 | |
| -O2 `-mllvm -inline-threshold=0` | 17,205 | 12,065 |
| -O2, every `define` given `minsize optsize` | 16,447 | 11,673 |
| the same plus `-fno-pic` | 15,894 | |

- **The linked 6809 program doesn't load.** At -O2 it doesn't even link as a
  DECB file: "ld.lld: error: DECB binary size 67127 exceeds 16-bit length
  field".
- **Which functions are left.** After -O2, 16 of the 106 functions in the IR
  are left on the 6809, but 66 on the Z80.  `buftests.run` alone is 37,672
  bytes on the 6809 (5,605 with threshold 0): its 158 calls to small check
  routines are all inlined.
- **-O0 is half the size of -O2** on the 6809.
- **`-Os` and `-Oz` change nothing.** Clang doesn't add `optsize`/`minsize` to
  the functions of a `.ll` input, so the size levels only work if the IR
  carries the attributes itself.

**A small reproducer:** `bugs/mc6809_code_size.p8`, five byte and word loop
routines called once each.

| Build | 6809 | Z80 |
|---|---|---|
| -O2 | 1,333 (all inlined into `main`) | 565 |
| -O2 `-mllvm -inline-threshold=0` | 703 | |

    LLVM_MC6809=~/.local/llvm-mc6809 prog8c -target llvm16 -triple mc6809-coco -o build/m-coco bugs/mc6809_code_size.p8
    LLVM_Z80=~/.local/llvm-z80 Z88DK=~/.local/z88dk prog8c -target llvm16 -triple z80-trs80-cmd -o build/m-z80 bugs/mc6809_code_size.p8
    $LLVM_MC6809/bin/clang --target=mc6809-unknown-decb -O2 -c build/m-coco.ll -o m.o && $LLVM_MC6809/bin/llvm-size m.o

## What to look at

1. **Size attributes in the IR.**
   - Emit `optsize` (or `minsize`) on every function that Prog8 generates,
     through an `attributes #0 = { ... }` group, or make it the llvm16 default
     with an option to turn it off.  On these 8-bit machines memory, not
     speed, is what runs out.
   - It helps the Z80 too: 14,078 down to 11,673 bytes (-17%).
   - Check that a speed option, if one is kept, still gives today's output.
2. **The mc6809 inliner.**
   - Even without the attributes, the 6809 inlines far more than the Z80 does
     at the same threshold.  Look at the mc6809 target's
     `TargetTransformInfo`: `getInliningThresholdMultiplier`, the call cost,
     and any `adjustInliningThreshold`.  If calls are costed as very
     expensive, or instructions as nearly free, everything gets inlined.
   - Inlining a routine that has many callers multiplies its code.  The
     inliner should weigh that more heavily under `optsize`.
   - Fixing the 6809 cost model may belong upstream in llvm-mc6809.  The
     attributes from (1) are Prog8's side.
3. **PIC.**
   - The 6809 code addresses its static variables PC-relative (`std
     $nnnn,pcr`: 4 bytes, against 3 for extended `std $nnnn`).  662 such
     references are left in the minsize build.
   - `-fno-pic` saves 3.4%.  A DECB `.bin` loads at a fixed address, so the
     coco profile can build static code.
4. **What remains.**
   - With (1) and (3) the 6809 code is about 1.36 times the Z80's (15,894
     against 11,673).  The 6809 should be at least as compact as the Z80,
     so look at that remainder too.
   - In the disassembly, values go through the direct-page "registers"
     (`__rs0`...: `ldd x / std <rs / ldd <rs / cmpd <rs`) many times where
     the 6809's own D, X, Y and U would do.

## To check

- `bugs/mc6809_code_size.p8` and p8vi's `gaptest.p8`: the `.text` of the
  6809 build should come close to the Z80's, or below it.
- The 6809 test suites (`mc6809-sim`) still pass with the attributes and
  `-fno-pic`.
- The z80, mos6502 and other llvm16 profiles, if the attributes go to all of
  them: their tests still pass, and their sizes go down.
- Report the before and after sizes of both reproducers.

## Why p8vi cares

A CoCo 2 port would have $0E00-$7FFF (28.5 KB) under Disk BASIC.  p8vi's
code is about 27-32 KB on the 6502 and Z80 builds; at today's 6809 code size
it would be over 100 KB.  (The coco profile also has no file I/O yet:
`diskio` always fails.)  This is worth fixing for any 6809 program, though.
