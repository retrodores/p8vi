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
`docs/KEYS.md` lists the vi commands it has, `docs/TODO.md` ideas for
later.

| Build | Toplevel file | Target |
|-------|---------------|--------|
| `build/p8vi-c64.prg` | `src/p8vi.p8` | C64 |
| `build/p8vi-c64reu.prg` | `src/p8vi.p8` | C64 with the page store, for text in an REU |
| `build/p8vi-cx16.prg` | `src/p8vi.p8` | Commander X16 |
| `build/p8vi-vic20.prg` | `src/p8vi_vic20.p8` | VIC-20 with 24K or more |

The editor itself is `src/editor.p8` (with `charset.p8`,
`src/<target>/platform.p8` and a text store, `buffer.p8` plus
`gapbuffer.p8` or `pagestore.p8`, chosen by `src/<target>/store_platform.p8`).
The two C64 builds differ only in the store: `p8vi-c64reu` is compiled
with `src/c64reu` before `src/c64`.  It keeps the text in pages in an
REU, up to 64 KB, or in main RAM without one (about 5 KB less than the
plain build).  The X16 keeps its pages in banked RAM
(`docs/XMEM-DESIGN.md`).  Each toplevel file has a `features` block
of `const bool` switches for optional features; the code of a feature that
is off is left out of the program.  The VIC-20 program has to end below
`$8000`, so its version leaves out features when room runs out: new
features that don't fit start out off there.  `make size` shows the room
left on each target.
`docs/FEATURE-SWITCHES.md` explains how the switches are written so the
compiler leaves the code out.

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
| `make test`  | Run on the virtual target and compare with `tests/expected/` |
| `make test-gap` | Text store tests (gap buffer and page store) on the virtual target |
| `make test-c64` | Editor command tests on a C64 in VICE (`tests/vice/edtest.py`, ~10 s) |
| `make test-c64reu` | The same on the C64 REU build (the page store) |
| `make test-reu` | REU detection and reset tests in VICE (`tests/reu/`) |
| `make test-c64-screen` | Check partial redraws against full redraws in VICE (~30 s) |
| `make size` | Memory map and room left below memtop for each build (`tools/listsize.py`) |
| `make c64`   | Compile for the C64 and run it in VICE                    |
| `make cx16`  | Compile for the Commander X16 and run it in x16emu        |
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
