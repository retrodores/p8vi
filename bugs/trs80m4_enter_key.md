# TRS-80 Model 4: ENTER stops working after a program trs80gp runs itself

**Fixed** in prog8c-llvm (commit b8d63d11, 2026-11-10).

prog8c 14.0-BETA3-llvm.1, `-target llvm16 -triple z80-trs80-m4`, trs80gp
(Model 4, TRSDOS 06.02.01), 2026-11-09.

## Symptom

`trs80gp -m4 prog.cmd` boots TRSDOS 6 and runs the program.  In the program
ENTER gives no key code (`@KBD` returns nothing; CTRL-M still gives 13), and
after the program quits ENTER does nothing at the DOS prompt either, until a
reset (trs80gp's File -> Warm reset).  Any program does it, even one that
only prints a line.  Typed at the DOS prompt, the same program is fine:
ENTER is 13 in it and works in the DOS afterwards.

## Reproduction

`bugs/trs80m4_enter_key.p8` prints `sys.argc()` and the arguments, then the
code of each key; BREAK twice quits.

    prog8c-llvm -target llvm16 -triple z80-trs80-m4 -o build/enterkey bugs/trs80m4_enter_key.p8

trs80gp runs it (keys: A, ENTER, A, BREAK, BREAK, then ENTER twice at the
prompt, typed on the keyboard matrix with `-ik`):

    argc 1
    0: []
    key codes, ENTER should be 13 (BREAK twice quits):
    97 97 128 128
    TRSDOS Ready          <- the two ENTERs give no new prompts

Copied to drive 1 with FreHD's IMPORT2 and typed at the prompt as `EK A B`
(the same keys):

    argc 4
    0: []
    1: [K]
    2: [A]
    3: [B]
    key codes, ENTER should be 13 (BREAK twice quits):
    97 13 97 128 128
    TRSDOS Ready
    TRSDOS Ready          <- one per ENTER
    TRSDOS Ready

## Cause (as far as I can tell)

z88dk's `lib/target/trs80/classic/trs80_crt0.asm` keeps HL at entry as the
command line (`ld (cmdline+1),hl`), and later:

    cmdline:
        ld      hl,0    ; SMC - command line back again
        ld      bc,0
        ld      a,(hl)
        cp      13
        jr      nz,nocr
        xor     a
        ld      (hl),a          ; <- the CR becomes 0
        jp      argv_done
    nocr: ...                   ; (otherwise it looks for the CR further on
                                ; and zeroes that one)

When trs80gp runs the program itself there is no command line, but HL points
at a 13 somewhere in the DOS: `argc 1` with an empty `argv(0)` is that
first branch.  Zeroing it breaks ENTER, so it is probably the keyboard
driver's code for the ENTER key.  Typed at the prompt, HL points into the
command line, whose CR it is fine to zero.

A real Model 4 runs programs from the prompt, so this may only bite in
trs80gp.  But the start-up code shouldn't write through HL unless HL is
known to point at a command line.  (The profile's own start-up code,
z80-trs80-m4.asm, runs in code_crt_init, after `ld (cmdline+1),hl`.)

## Also: argv(1) is the name's second letter

`EK A B` gives argc 4 and `argv(1)` = `K`: HL pointed at the second
character of the program's name, not after it.  (The build notes say that
`PROG:1 A B` gives `argv(1)` = `1`, the drive.)  Worth checking what HL
points at for names of other lengths, and with and without a drive spec.

## Workaround in p8vi

`make emu-trs80` and `make emu-trs80m4` copy the program to drive 1 with
IMPORT2 and type `P8VI` at the prompt, instead of letting trs80gp run it.
