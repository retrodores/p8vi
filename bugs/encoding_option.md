# Feature request: `-encoding <name>`, the default text encoding for a whole compile

**Status:** requested 2026-11-11 (prog8c 12.3.4).

## What it is for

p8vi's editor is shared across targets. Its source has hundreds of
character and string literals with no prefix (`'j'`, `"L "`, `':'`,
...): about 160 in src/editor.p8 alone, plus gapbuffer.p8, pagestore.p8
and others. They are compiled in the target's default encoding: PETSCII
on c64/cx16, ASCII on the TRS-80, CP/M and llvm64 targets. The editor
works in either, because it compares keys and text only against those
literals.

On the Commander X16 we want an ISO-mode build: `txt.iso()` at startup,
text kept as ISO-8859-15 in memory, ASCII/ISO files read and written
unchanged, and `{ | } ~ _ \`` shown as themselves. In ISO mode the
X16's keyboard gives ISO codes and CHROUT prints ISO, so every literal
has to be ISO as well (`j` arrives as $6A; the PETSCII literal is $4A).

Today the only way is `%encoding iso` in each module. That changes the
shared modules for every target, so the C64, C128 and PET builds would
break. Per-literal `iso:` prefixes have the same problem.

## Proposal

A command line option that sets the default encoding for the whole
compile:

```
prog8c -target cx16 -encoding iso -srcdirs src:src/cx16iso src/p8vi_cx16iso.p8
```

- Literals without a prefix, in modules without their own `%encoding`,
  use the given encoding instead of the target's default.
- `%encoding` in a module still overrides it for that module, and
  explicit prefixes (`petscii:"x"`, `sc:'a'`) still win.
- The name is any of the recognised encodings, as for `%encoding`; an
  encoding the target doesn't support is an error, as for `%encoding`.

**Open question: the library modules.** They are written for the target's
default. One example is the X16's `txt`/`diskio` code with PETSCII literals
(drive commands, directory parsing). p8vi only needs its own modules
changed, so either of these would do:
- the option applies only to the program's modules and not to the
  library (the safest choice); or
- it applies to all modules, and the library modules that depend on
  their encoding get an explicit `%encoding`.

Something like `-encoding iso` showing in the IR/asm header, or a
`target.ENCODING` style constant, would let a program check which way it
was compiled. That is not needed: p8vi will have its own features
switch.

## How to check it

```prog8
%import textio
main {
    sub start() {
        txt.iso()
        txt.print("Hello, {world} ~_|\n")   ; no prefix
        ubyte c = 'a'
        txt.print_ubhex(c, true)            ; $61 with -encoding iso, $41 without
        txt.nl()
    }
}
```

`prog8c -target cx16 -encoding iso` then `x16emu -run -prg ...`: the text
shows as written, in mixed case with the braces, and `$61`. Without the
option, the result is the same as today ($41, and the text garbled in ISO
mode).

## Until then

The X16 version stays PETSCII. An ISO version would be a second X16 build
that keeps PETSCII inside and translates at the edges, and that doesn't
fit in the 104 bytes free (see docs/TODO.md).
