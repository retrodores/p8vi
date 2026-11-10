# llvm16 / z80: a 0 followed by $30-$37 in an array loses a byte

prog8c 14.0-BETA3-llvm.1, llvm16 target with the z80 profiles (seen with
z80-test and z80-trs80-m4), 2026-11-09.

## Symptom

A `ubyte[]` with the bytes `$00, $31` comes out of the binary as one byte,
`$01`, and everything after it moves up a byte (the array runs into the next
data).  The same goes for a 0 followed by any of `$30`-`$37` (the ASCII
digits 0-7).  A 0 followed by `$38` or `$39` is fine.  The IR (`.ll`) still
has the right values:

    @main.data = internal global [14 x i8] [i8 17, i8 0, i8 49, i8 1, ...]

## Reproduction

    prog8c-llvm -target llvm16 -triple z80-test -emu bugs/z80_array_zero_digit.p8

    got:  11 01 01 07 02 00 38 03 00 00 04 67 6f 74
    want: 11 00 31 01 00 37 02 00 38 03 00 00 30 04

`00 31` became `01`, `00 37` became `07`, `00 00 30` became `00 00`; `00 38`
is right.  The last bytes printed (`67 6f 74`, "got") are the next string.

## Probable cause

The array data is written to the assembler as a string, a 0 byte as `\0`.
When the next byte is the character `0`-`7`, the assembler reads `\0` and
that digit as one octal escape (`\01`, `\07`, `\00`).  An escape that can't
run on (`\000`, three digits, or `\x00`) would fix it.  Somewhere between
the LLVM Z80 backend's asm printer and z88dk's assembler.

## Notes for checking a fix

- LLVM folds `data[i]` to the initial values wherever it can (the global is
  never written), so a check like `if data[2] == $31` passes even when the
  binary is wrong.  Only a loop over the array (or the binary itself) shows
  it.
- The same will happen to `str` constants and any other data that has a 0
  before a digit: a `uword` array with `$3100` (bytes `00 31`), a string
  table, machine code kept in an array (`ld de,$3100` is `11 00 31`, which
  is how this was found).
- p8vi's TRS-80 builds have no such bytes at the moment (their `.ll` has no
  `i8 0, i8 48`-`55` and no `\00` followed by a digit 0-7).
