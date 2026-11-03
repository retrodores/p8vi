# p8vi quick start

p8vi is a vi for 8-bit Commodore computers: the C64, VIC-20, Commander
X16 and MEGA65.  If you know vi or vim you
know most of it already; this guide shows what is there and which keys to
press on a Commodore keyboard.  `docs/KEYS.md` lists every vi command with
whether it is done.

## Contents

1. [Getting started](#getting-started)
2. [Modes](#modes)
3. [The keyboard](#the-keyboard)
4. [Moving around](#moving-around)
5. [Inserting text](#inserting-text)
6. [Deleting and changing](#deleting-and-changing)
7. [Copying and pasting](#copying-and-pasting)
8. [Undo and repeat](#undo-and-repeat)
9. [Searching and replacing](#searching-and-replacing)
10. [Files](#files)
11. [Disk commands](#disk-commands)
12. [ASCII and PETSCII](#ascii-and-petscii)
13. [Big files, extended memory and recovery](#big-files-extended-memory-and-recovery)
14. [What some versions leave out](#what-some-versions-leave-out)
15. [Cheat sheet](#cheat-sheet)

## Getting started

| Program | For | Text |
|---------|-----|------|
| `p8vi-c64.prg` | C64 | about 16 KB |
| `p8vi-c64reu.prg` | C64 with an REU | up to 64 KB (about 4 KB without an REU: use `p8vi-c64` then) |
| `p8vi-cx16.prg` | Commander X16 | up to 64 KB (in banked RAM) |
| `p8vi-vic20.prg` | VIC-20 with 32 KB of RAM expansion (blocks 1, 2, 3 and 5) | about 4.7 KB |
| `p8vi-mega65.prg` | MEGA65 (in MEGA65 mode, not `GO64`) | about 6.7 KB |
| `p8vi-mega65dma.prg` | MEGA65 | up to 64 KB (in attic RAM, or chip RAM banks 4 and 5 without it) |

The MEGA65 versions are new and still being worked on.

Load and run it like any program, for example on a C64:

```
LOAD"P8VI",8
RUN
```

On the MEGA65 (in its own mode, the one it starts in): `DLOAD"P8VI-MEGA65"`
and `RUN`, or `RUN"P8VI-MEGA65"`.

Then `:e name` opens a file (a name that isn't on the disk starts a new,
empty file), and `:q` quits.  `Ctrl-G` shows how many lines there are and
how much room is left.

The bottom of the screen is the status line: messages on the left, the
cursor's line and column on the right.

## Modes

| Mode | What it is | How you get there | How you leave |
|------|------------|-------------------|---------------|
| **nav** (vi's normal mode) | keys are commands: moving, deleting, ... | p8vi starts here | |
| **insert** | keys are typed into the text | `i` `a` `I` `A` `o` `O`, or `c` commands | `Esc` |
| **replace** | typing overwrites | `R` | `Esc` |
| **command line** | a `:` command, or a `/` `?` search, typed on the status line | `:` `/` `?` | `Return` runs it, `Esc` drops it |

When in doubt, press `Esc` (twice does no harm) to get back to nav mode.

## The keyboard

Commodore keyboards lack some keys vi uses:

| vi key | Type this | |
|--------|-----------|---|
| `Esc` | `RUN/STOP`, or `Ctrl` + `[` | the X16 and the MEGA65 also have a real `Esc` key |
| `~` | `π` (`Shift` + `↑`) | PETSCII has no `~` |
| `^` | `↑` | |
| `_` | `C=` + `@` | |
| `\|` | `Shift` + `-` | |
| Backspace | `DEL` | |
| arrow keys | the cursor keys | in nav, insert and replace mode |
| `Ctrl-F` etc. | `CTRL` + `F` | |

`{` and `}` don't exist in PETSCII.  On the MEGA65 an ASCII file shows
them, and the keys type them (see [ASCII and PETSCII](#ascii-and-petscii)).

A count typed before a command repeats or extends it: `3j` moves down 3
lines, `2dd` deletes 2 lines, `d3w` deletes 3 words.

## Moving around

| Keys | Moves to |
|------|----------|
| `h` `j` `k` `l` (or the cursor keys) | left, down, up, right |
| `Space`, `DEL` | right, left |
| `w` `b` `e` | next word, previous word, end of word |
| `W` `B` `E` | the same for words separated by blanks only |
| `ge` `gE` | end of the previous word |
| `0` (or `HOME`), `^`, `$` | start of the line, first non-blank, end of the line |
| `+` (or `Return`), `-` | first non-blank of the next / previous line |
| `_`, `n\|` | first non-blank of the line, column n |
| `f`x `F`x | the next / previous x in the line |
| `t`x `T`x | just before the next / after the previous x |
| `;` `,` | repeat the last `f` `F` `t` `T` the same / other way |
| `%` | the matching `( )` or `[ ]` |
| `gg`, `G`, `nG` | first line, last line, line n |
| `:n` | line n (also `:$` last line and `:.` cursor line, not on the VIC-20) |
| `H` `M` `L` | top, middle, bottom row of the screen |

Scrolling:

| Keys | Does |
|------|------|
| `Ctrl-F` `Ctrl-B` | a page forward / back |
| `Ctrl-D` `Ctrl-U` | half a page down / up |
| `Ctrl-L` | draw the screen again |

## Inserting text

| Keys | Inserts |
|------|---------|
| `i` `a` | before / after the cursor |
| `I` `A` | at the start (first non-blank) / end of the line |
| `o` `O` | on a new line below / above |
| `R` | replace mode: typing overwrites, `DEL` moves back |
| `3ifoo` `Esc` | with a count: the text 3 times (`2o`: 2 new lines) |

While inserting:

| Keys | Does |
|------|------|
| `Return` | starts a new line |
| `DEL` | deletes the character before the cursor |
| `Ctrl-W` | deletes the word before the cursor |
| `Ctrl-U` | deletes back to where this insert started |
| cursor keys | move without leaving insert mode |
| `Esc` | back to nav mode |

## Deleting and changing

| Keys | Does |
|------|------|
| `x` `X` | delete the character under / before the cursor |
| `dd` | delete the line (`3dd`: 3 lines) |
| `D` | delete to the end of the line |
| `cc` (or `S`), `C` | change the line, change to the end of the line |
| `s` | change the character |
| `r`x | replace the character with x (`r` `Return` splits the line) |
| `~` (`π`) | switch upper / lower case |
| `J`, `gJ` | join the next line, with a space / as it is |
| `>>` `<<` | indent / unindent the line by 4 spaces |

**Operators and motions.** `d` (delete), `c` (change), `y` (yank), `>`
and `<` (indent) take a motion: what they work on is where the motion
would move the cursor.

| Example | Does |
|---------|------|
| `dw` | delete to the next word |
| `d$` | delete to the end of the line |
| `cw` | change the word |
| `d3w`, `3dw` | delete 3 words |
| `dG` | delete to the end of the text |
| `dfx`, `dtx` | delete up to and with / without the next x |
| `>j` | indent this line and the next |

Motions that move by lines (`j` `k` `G` `gg` `H` `M` `L` `+` `-`) make
the operator work on whole lines.

## Copying and pasting

| Keys | Does |
|------|------|
| `yy` (or `Y`), `3yy` | copy (yank) the line, 3 lines |
| `y`motion | yank, like `d` (`yw`, `y$`, `yG`) |
| `p` `P` | put after / before the cursor (lines: below / above) |

Deleted text goes to the yank buffer too, so `ddp` swaps two lines and
`xp` two characters.  There is one yank buffer (no named registers).  It
holds 1 KB on the C64 and VIC-20, and up to 64 KB with an REU and on the
X16.

## Undo and repeat

| Keys | Does |
|------|------|
| `u` | undo the last change; `u` again redoes it (like vi) |
| `Ctrl-R` | redo what `u` just undid |
| `.` | repeat the last change (`3.`: with a count of 3) |

A whole insert, or a whole `:s`, counts as one change.  The undo log holds
2 KB on the C64 and VIC-20 (a bigger change says "undo too big" and can't
be undone), and up to 64 KB with an REU and on the X16.  Loading a file
empties it.

## Searching and replacing

| Keys | Does |
|------|------|
| `/text` `Return`, `?text` `Return` | search forward / back (wrapping around) |
| `n` `N` | the next match the same / other way |
| `/` `Return`, `?` `Return` | repeat the last search |
| `*` `#` | search forward / back for the word under the cursor |

Searches are for plain text, not patterns.

Replacing (not on the VIC-20):

| Command | Does |
|---------|------|
| `:s/old/new/` | replace the first old in the cursor line |
| `:s/old/new/g` | replace every old in the cursor line |
| `:%s/old/new/g` | in every line |
| `:5,10s/old/new/`, `:.,$s/old/new/` | in lines 5 to 10, from here to the end |
| `:s//new/` | replace what was searched for last |

Any character can take the place of `/` (`:s#a/b#c#`), and the last one can
be left out (`:s/old/new`).  `u` undoes a whole `:s`.

## Files

| Command | Does |
|---------|------|
| `:e name` | edit a file (a new name starts an empty one) |
| `:e!` | read the file again, throwing away changes |
| `:w` | write the file |
| `:w name` | write to another file |
| `:r name` | read a file in below the cursor line |
| `:q` | quit (refused if there are unsaved changes) |
| `:q!`, `ZQ` | quit, throwing away changes |
| `:wq` | write and quit |
| `:x`, `ZZ` | write if changed, and quit |

**Saving is safe.**  `:w` writes the text to `p8vi.tmp` first and only
then replaces the old file with it.  If the disk is full, or the write
fails, the old file is left as it was.  (So the disk needs room for both
while saving.)

**Other computers' files.**  p8vi works out what kind of file it reads:

* **ASCII** text (from a PC, Mac or Unix) is shown in the right case, and
  written back as ASCII.
* **Line endings:** CR (Commodore), LF (Unix) or CR LF (DOS and Windows).
  They are written back the same way.
* `:set` shows the format (for example `ascii crlf`).  `:set ascii`,
  `:set petscii`, `:set cr`, `:set lf` and `:set crlf` change how the file
  is written (see [ASCII and PETSCII](#ascii-and-petscii)).
* `:r` converts the file it reads to the text's format.

A file too big for the room left is read only partly ("too big, cut").
Writing it back over the same file then needs `:w!`, since the end of the
file would be lost.

Control characters (tabs too) show as `.`.

## Disk commands

Not on the VIC-20:

| Command | Does |
|---------|------|
| `:@` | show the drive status |
| `:@cmd` | send a command to the drive, like the DOS wedge: `:@s:name` deletes a file, `:@r:new=old` renames one (on the MEGA65: `:@r0:new=0:old`) |
| `:@$`, `:@$:pattern` | show the directory, or the files that match (`:@$:*.txt`); a key shows the next screenful, `Esc` stops |
| `:r $`, `:r $:pattern` | read the directory into the text, one line per file |

`:@$` and `:r $` aren't in `p8vi-mega65dma` either.

## ASCII and PETSCII

Commodore computers use PETSCII, other computers ASCII.  The two agree on
most letters, digits and punctuation, but PETSCII has graphics characters
where ASCII has `` \ ^ _ ` { | } ~ ``, and swaps upper and lower case.  p8vi
edits both:

* **Reading.**  p8vi looks at the file and decides: ASCII files are
  translated to PETSCII as they are read, PETSCII files are read as they
  are.  `:set` says which it is (`ascii` or `petscii`, with the line
  ending).
* **Writing.**  The file is written back the way it was read: an ASCII
  file is translated back to ASCII.
* **Changing it.**  If p8vi guessed wrong, or you want to convert a file,
  `:set ascii` or `:set petscii` changes how it is written (the text
  itself stays the same).  `:set cr`, `:set lf` and `:set crlf`
  change the line endings.  Then `:w`.
* A new file (`:e newname`) starts as PETSCII with CR line endings.

**On the MEGA65** the characters on the screen follow the file too.  For an
ASCII file p8vi switches to the MEGA65's own character set with
`` \ ^ _ ` { | } ~ `` in it (the one BASIC 65's `FONT A` gives), so a C
program or a Unix file looks as it should.  For a PETSCII file it uses the
usual Commodore set, so PETSCII graphics show as graphics.  `:set ascii`
and `:set petscii` switch the characters at once.  When you quit, the
Commodore set is back.

In an ASCII file on the MEGA65 these keys type the ASCII characters (as in
C64 OS):

| Character | Key | | Character | Key |
|-----------|-----|---|-----------|-----|
| `\` | `£` | | `{` | `Shift` + `+`, or `MEGA` + `:` |
| `^` | `↑` | | `\|` | `Shift` + `£`, or `MEGA` + `.` |
| `_` | `←` | | `}` | `Shift` + `-`, or `MEGA` + `;` |
| `` ` `` | `Shift` + `*` | | `~` | `Shift` + `↑`, or `MEGA` + `,` |

So in an ASCII file the vi commands `|` (go to a column) and `_` are
`Shift` + `£` and `←`.  In a PETSCII file the keys are as in the table in
[The keyboard](#the-keyboard).

## Big files, extended memory and recovery

**`p8vi-c64reu`** keeps the text in an REU, and **the X16** in its banked
RAM: files up to 64 KB, with yank and undo as big.  The plain C64 build
has more room without an REU, so use that one there.

**`p8vi-mega65dma`** keeps the text in the MEGA65's attic RAM: files up to
64 KB, with yank and undo as big.  A MEGA65 without attic RAM (the Nexys4
FPGA boards) has 128 KB of chip RAM for it instead, which holds a 64 KB
file but leaves less room for yank and undo.

**Recovery after a crash or a reset** (REU build with an REU, and the X16;
`p8vi-mega65dma` keeps a copy as well, but recovering it after a reset
hasn't been tried on a MEGA65 yet).
While you edit, p8vi keeps a copy of the text up to date in extended
memory whenever the keyboard has been idle for half a second.  After a
crash, or the reset button, start p8vi again: it says `:rec to recover`.

| Command | Does |
|---------|------|
| `:rec` (or `:recover`) | bring the text back, with its file name and format, and the cursor where it was |
| `:rec!` | the same when the text now has unsaved changes |

Up to two texts can wait (after two resets): `:rec` brings the newer one
and says when there is another; `:rec` again brings that.  A text waits
until it is recovered, also if you edit something else meanwhile, unless
two already wait and you start a third.  `:q` doesn't leave anything to
recover.  Switching the computer off loses the extended memory, and so the
text.

## What some versions leave out

The VIC-20 version has to fit in less memory, so it has none of these:

* `:s` replacing, and line ranges (`:%`, `:5,10`, `:$`, `:.`)
* the disk commands `:@`, `:@$` and `:r $`
* the start screen
* scrolling one row at a time (the screen is drawn again instead)
* a file that ends with a line ending shows an empty last line (the other
  versions treat it as the end of the last line, like vi)

The X16 version leaves out the start screen only.

`p8vi-mega65dma` leaves out the start screen, `:s` replacing and line
ranges, and `:@$` and `:r $`: its program has to fit below the room it
needs for its text.  `p8vi-mega65` has everything.

<div style="page-break-before: always"></div>

## Cheat sheet

`Esc` = `RUN/STOP`.  `π` = `Shift` + `↑`.  A count before most commands:
`3j`, `2dd`, `d3w`.  † = not on the VIC-20.  ‡ = not on the VIC-20 or in
`p8vi-mega65dma`.

**Moving**

| | | | |
|---|---|---|---|
| `h` `j` `k` `l` | left down up right | `gg` `G` `nG` | first / last / line n |
| `w` `b` `e` | word: next, back, end | `W` `B` `E` | blank-separated word |
| `0` `^` `$` | line: start, non-blank, end | `+` `-` | next / prev line |
| `f`x `F`x | find x in the line | `t`x `T`x | to just before x |
| `;` `,` | repeat f/t, same / back | `%` | matching `()` `[]` |
| `H` `M` `L` | screen top / middle / bottom | `n\|` `_` | column n, non-blank |
| `Ctrl-F` `Ctrl-B` | page down / up | `Ctrl-D` `Ctrl-U` | half page |
| `ge` `gE` | end of previous word | `Ctrl-L` | redraw |

**Inserting** (leave with `Esc`)

| | | | |
|---|---|---|---|
| `i` `a` | before / after cursor | `I` `A` | line start / end |
| `o` `O` | new line below / above | `R` | overwrite |
| `Ctrl-W` | delete word back | `Ctrl-U` | delete back to insert start |

**Changing**

| | | | |
|---|---|---|---|
| `x` `X` | delete char / char before | `dd` `D` | delete line / to end |
| `d`motion | delete | `c`motion | change |
| `cc` `S` `C` | change line / to end | `s` `r`x | change char, replace with x |
| `J` `gJ` | join with / without space | `~` (`π`) | switch case |
| `>>` `<<` | indent / unindent | `>`motion `<`motion | over a motion |
| `u` `Ctrl-R` | undo / redo | `.` | repeat change |

**Yank, put, search**

| | | | |
|---|---|---|---|
| `yy` `Y` `y`motion | yank | `p` `P` | put after / before |
| `/`text `?`text | search fwd / back | `n` `N` | next / previous match |
| `*` `#` | word under cursor | `:s/a/b/g` ‡ | replace in line |
| `:%s/a/b/g` ‡ | in all lines | `:5,10s/a/b/` ‡ | in lines 5-10 |

**Files and more**

| | | | |
|---|---|---|---|
| `:e` name | edit | `:e!` | reload |
| `:w` `:w` name | write | `:w!` | write a cut-short file |
| `:r` name | read in | `:q` `:q!` | quit / discard |
| `:wq` `:x` `ZZ` | write and quit | `ZQ` | quit, discard |
| `:n` | go to line n | `:$` `:.` ‡ | last / this line |
| `:set` | show format | `:set ascii` / `petscii` / `cr` / `lf` / `crlf` | write format (MEGA65: and the characters shown) |
| `:@` † | drive status | `:@`cmd † | drive command |
| `:@$` ‡ | directory | `:r $` ‡ | directory into text |
| `:rec` | recover after a crash (REU, X16) | `Ctrl-G` | lines and room |
