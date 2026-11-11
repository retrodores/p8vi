# Prog8 AI context for developing user programs

This repository uses reference material from the official Prog8 compiler
repository, downloaded by `setup.py`.  The AGENTS.md file references upstream
documents and adds additional information to help with writing programs with
Prog8 and inline 6502 assembly.

Some critical code sections like startup code for a target might be written
directly in 6502 assembly language in .asm files and included either by
the inline assembly directly or defined in the custom target properties file.

Prog8 code can easily load modules and call routines written directly in
6502 assembly, but the typical case would be Prog8 and some inline assembly.

The compiler source code is not downloaded, but the standard library source
code (written in Prog8) is critical.

The upstream compiler repository, under the GPLv3 license, is here:
https://github.com/irmen/prog8

`setup.py` does a sparse, shallow download of only the agent skills, docs,
grammar, standard library and example code, matching the version of the
installed `prog8c` compiler.  This gives AI agents the upstream context
without duplicating it here or checking out the whole compiler repository.

# p8vi

This repository holds p8vi, a vi for 8-bit computers written in Prog8.
`docs/QUICKSTART.md` is an introduction with a one-page cheat sheet,
`docs/KEYS.md` lists the vi commands it has, `docs/TODO.md` ideas for
later.

| Build | Toplevel file | Target |
|-------|---------------|--------|
| `build/p8vi-c64.prg` | `src/p8vi.p8` | C64 |
| `build/p8vi-c64reu.prg` | `src/p8vi_c64reu.p8` | C64 with the page store, for text in an REU |
| `build/p8vi-c64disk.prg` | `src/p8vi.p8` | An experiment: C64 with the page store, its pages in SEQ files (`p8vi.swp...`) on the drive, for fast devices (IDE64, RAMLink, CMD HD); `src/diskpage` |
| `build/p8vi-cx16.prg` | `src/p8vi.p8` | Commander X16 |
| `build/p8vi-cx16iso.prg` | `src/p8vi_cx16iso.p8` | Commander X16 in ISO mode: ASCII/ISO text shown as it is (`{ \| } ~ _`), file names in ISO; built from `%encoding iso` copies of the sources (`tools/encode_copy.py`, `bugs/encoding_option.md`), in progress |
| `build/p8vi-mega65.prg` | `src/p8vi_mega65.p8` | MEGA65 (MEGA65 mode), with the ASCII characters for ASCII files, in progress |
| `build/p8vi-mega65dma.prg` | `src/p8vi_mega65dma.p8` | The same with the page store: text in attic RAM (or chip RAM banks 4 and 5) through DMA, in progress |
| `build/p8vi-plus4.prg` | `src/p8vi_plus4.p8` | Plus/4: the full editor with 24.6 KB of text, running with the RAM in up to `$fc00` and the KERNAL ROM switched in for its calls (`src/plus4/rammode.p8`), in progress |
| `build/p8vi-pet32.prg` | `src/p8vi_pet32.p8` | PET 4032 (32 KB, BASIC 4), with the VIC-20's features and no ASCII or CR LF files: 3.3 KB of text, in progress |
| `build/p8vi-vic20.prg` | `src/p8vi_vic20.p8` | VIC-20 with 24K or more |
| `build/p8vi-c64font.prg` | `src/p8vi_c64font.p8` | An experiment: the C64 REU build with a font for ASCII text |

The editor itself is `src/editor.p8` (with `charset.p8`,
`src/<target>/platform.p8` and a text store, `buffer.p8` plus
`gapbuffer.p8` or `pagestore.p8`, chosen by `src/<target>/store_platform.p8`).
The two C64 builds differ only in the store: `p8vi-c64reu` is compiled
with `src/c64reu` before `src/c64`.  It keeps the text in pages in an
REU, up to 64 KB, or in main RAM without one (about 5 KB less than the
plain build).  The X16 keeps its pages in banked RAM
(`docs/XMEM-DESIGN.md`).  `p8vi-mega65dma` (`src/mega65dma` before
`src/mega65`) copies its pages to and from attic RAM with the DMA
controller, up to 254 pages of 1 KB (room for the store's 64 KB of text
with yank and undo besides), or chip RAM banks 4 and 5 (126 pages) on a MEGA65
without attic RAM, such as the Nexys4 boards (checked by model ID and by
writing to it).  Its program must end below `$c000`, so SPLASH, SUBST
and DIR are off there for now.  Each toplevel file has a `features` block
of `const bool` switches for optional features; the code of a feature that
is off is left out of the program.  The VIC-20 program has to end below
`$8000`, so its version leaves out features when room runs out: new
features that don't fit start out off there.  `make size` shows the room
left on each target.
`docs/FEATURE-SWITCHES.md` explains how the switches are written so the
compiler leaves the code out.
`docs/TEXT-STORE.md` lists the files to copy to use the text stores (the
gap buffer, or the page store with an REU or the X16's banked RAM) in
another program.

`p8vi-c64font` (the `FONT` switch, `src/c64/font.p8`) is the REU build
with OSCII (C64 OS + ASCII), a font that has the ASCII characters PETSCII
lacks: `` \ ^ _ ` { | } ~ ``.  It loads the font from `oscii.fnt` on the disk to the RAM under the
KERNAL at `$f800` and moves the screen to `$c800`, so the program and its
buffers end below `$c800`.  The characters are typed as in C64 OS: pound
`\`, up arrow `^`, left arrow `_`, and with Shift: `*` for `` ` ``, `+`
for `{`, pound for `|`, `-` for `}` and up arrow for `~`.  ASCII files are
translated to the PETSCII codes the font shows them for.  `make font`
makes `build/oscii.fnt` from the font in `FONTSRC` (`tools/mkfont.py`),
`make emu-c64font` runs it in VICE.  `p8vi-c128x` shows the same font.

The MEGA65 builds are font builds too (`src/mega65/font.p8`), with no
font file: the MEGA65 ROM has a lower case character set with the same
characters at the same codes (BASIC 65's `FONT A`, at `$29800`).  The
font follows the text: for an ASCII file p8vi copies that set into the
VIC-IV's character RAM with DMA, for a PETSCII file (and when it quits)
the C64 set (`$2d800`), so PETSCII graphics show as they are.  `:set
ascii` and `:set petscii` switch it too.  With the ASCII set the keys
are the same as on the C64 font build, and MEGA with `:`, `.`, `;` and
`,` types `{`, `|`, `}` and `~` too.

# Prerequisites

- **Java 17 or newer** to run the Prog8 compiler.  Check with `java -version`.
  [Adoptium](https://adoptium.net/temurin/releases) has OpenJDK builds for
  all platforms.
- **The Prog8 compiler**, run as `prog8c`.  Download `prog8c-<version>-all.jar`
  from the [Prog8 releases](https://github.com/irmen/prog8/releases), or see
  the [installation docs](https://prog8.readthedocs.io/en/latest/compiling.html)
  for other options.  Use v12.2 or newer.
- **The 64tass assembler**, which the compiler runs to assemble its output.
  Binaries are on [SourceForge](https://sourceforge.net/projects/tass64/files/binaries/),
  and most Linux distributions and Homebrew have a `64tass` package.
- **git**, **make** and **Python 3**.
- *Optional:* the [VICE emulator](https://vice-emu.sourceforge.io/) for
  `make emu`.  Everything else uses the compiler's built-in virtual target
  and needs no emulator.

The `Makefile` and `setup.py` both expect `prog8c` in your `PATH`.  If you
downloaded the jar, a small wrapper script does the job.  On Linux or macOS
save this as `prog8c` somewhere in your `PATH` and `chmod +x` it:
```
#!/bin/sh
exec java -jar /path/to/prog8c-12.3.4-all.jar "$@"
```
On Windows save this as `prog8c.cmd` in a folder on your `PATH`:
```
@java -jar C:\path\to\prog8c-12.3.4-all.jar %*
```

# Quick start

1. On GitHub click **Use this template** to create your own repository,
   then clone it.
2. Download the Prog8 reference material for your installed compiler:
   ```
   python3 setup.py
   ```
   (On Windows use `py setup.py` or `python setup.py`.)
3. Build and run the example program on the virtual target:
   ```
   make run
   ```
4. Start your AI coding assistant in the repository and ask it to write
   some Prog8!

`setup.py` puts the reference material in `.prog8-reference`, which is in
`.gitignore` so it is never committed.  Run it again whenever you install
a different version of the compiler.  It deletes and recreates the
directory each time.

The useful `make` targets are:

| Target       | What it does                                              |
|--------------|-----------------------------------------------------------|
| `make check` | Fast syntax check without compiling                       |
| `make run`   | Compile for the virtual target and run it                 |
| `make test` | The text store tests (the same as `make test-gap`) |
| `make test-gap` | Text store tests (gap buffer and page store) on the virtual target |
| `make test-c64` | Editor command tests on a C64 in VICE (`tests/vice/edtest.py`, ~10 s) |
| `make test-c64reu` | The same on the C64 REU build (the page store), with and without an REU, and recovery after a reset (`tests/vice/rectest.py`) |
| `make audit` | Look in the generated assembler for the silent compiler bugs found so far (`tools/asmaudit.py`) |
| `make test-fastmem` | The 6502 byte scans and copies (`src/fastmem.p8`) against plain Prog8, in VICE |
| `make bench` | Timings of the text store routines in VICE (`tests/bench/storebench.p8`), screenshots in `build/bench-*.png` |
| `make test-reu` | REU detection and reset tests in VICE (`tests/reu/`) |
| `make test-c64font` | The C64 REU build's tests on the font build, and its own (`font`) |
| `make test-c64disk` | The VICE editor and redraw tests on the C64 disk build, on a 1541 |
| `make test-c64-screen` | Check partial redraws against full redraws in VICE (~30 s) |
| `make test-plus4` | The VICE editor and redraw tests on a Plus/4 (`xplus4`, `tests/vice/edtest.py --machine plus4`) |
| `make emu-plus4` | Run the Plus/4 version in `xplus4`, with a disk of its own (`build/testplus4.d64`) |
| `make test-pet32` | The VICE editor and redraw tests on a PET 4032 (`xpet`, `tests/vice/edtest.py --machine pet`), without the suites for the features it leaves out |
| `make emu-pet32` | Run the PET version in `xpet`, with a disk of its own (`build/testpet.d64`) |
| `make test-mega65` | The VICE editor and redraw tests on a MEGA65 in xmega65, through `tools/m65harness.py` (`tests/mega65/edtest.py`, ~3 min) |
| `make test-mega65dma` | The same on the MEGA65 page store build, with the big-text and font suites, in attic RAM and (as on a Nexys4 board) without it |
| `make test-mega65-zp` | Which zero page bytes the MEGA65 ROM changes in KERNAL calls (`tests/mega65/zpwatch.p8`) |
| `make test-mega65-keymap` | Measure which MEGA65 keys give which PETSCII codes (the harness's key table) |
| `make size` | Memory map and room left below memtop for each build (`tools/listsize.py`) |
| `make disk` | `build/testgap.d81`: a 1581 disk with the C64 and VIC-20 programs, `oscii.fnt` and the sample files, for `make emu-c64`, `emu-c64reu`, `emu-c64font` and `emu-vic20` (drive 8 is a 1581) |
| `make c64`   | Compile for the C64 and run it in VICE                    |
| `make cx16`  | Compile for the Commander X16 and run it in x16emu        |
| `make release` | Copy the four programs and `docs/QUICKSTART.md` to `release/` (after `make test`, `audit` and `size`): the last known good version |
| `make clean` | Remove everything in `build/`                             |

# How the AI context works

`AGENTS.md` is the single source of instructions for AI agents.  The other
agent files only point at it, so most tools pick it up without extra setup:

| File                              | Tool                       |
|-----------------------------------|----------------------------|
| `CLAUDE.md`                       | Claude Code                |
| `GEMINI.md`                       | Gemini CLI                 |
| `.github/copilot-instructions.md` | GitHub Copilot             |
| `.cursor/rules/prog8.mdc`         | Cursor                     |
| `.aiassistant/rules/AGENT_RULES.md` | JetBrains AI Assistant   |

`AGENTS.md` sends agents to the upstream skills, docs, grammar, standard
library and examples in `.prog8-reference`.  The files in `.context/` add
only what the upstream material doesn't already cover.  `setup.py` also
links the upstream skills into `.claude/skills/` so Claude Code loads them
automatically.

If the reference material is missing, `AGENTS.md` tells the agent to stop
and ask you to run `setup.py`.

# Customizing

- **A different compiler:** to match a beta or a locally built compiler
  (such as `prog8c-beta`), change `PROG8C` at the top of `setup.py`
  and `PCC` in the `Makefile`.  Snapshot builds are matched by commit, so
  for a compiler built from a fork or another branch also change
  `TARGET_REPO` and `TARGET_BRANCH`.
- **Your program:** source goes in `src/`, starting with the toplevel files `src/p8vi.p8` and `src/p8vi_vic20.p8`.
  Code for one target only goes in a target directory such as `src/c64/`.
  See `AGENTS.md` for the conventions.

# License

This template is released under the [0BSD license](LICENSE), so projects
created from it can use any license they like.  Replace `LICENSE` with
your own project's license, since the current one names the template's
author as the copyright holder.

The Prog8 material that `setup.py` downloads into `.prog8-reference` comes
from the [Prog8 repository](https://github.com/irmen/prog8) and is under
the GPLv3 license.  It is not part of this repository and is never
committed to it.
