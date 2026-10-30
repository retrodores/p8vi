# vi keys

The vi and vim commands that are practical for this editor on 8-bit
systems, and which are implemented.

| Mark | Meaning |
|------|---------|
| ✅ | implemented |
| ⬜ | to do |
| ❌ | won't do (too big for the target machines, or no use there) |

The VIC-20 version (`src/p8vi_vic20.p8`) may leave out some features to
fit in memory; its `features` block lists which.

`:s` replaces plain text, not a pattern: no `.` `*` `^` `$` or `&`.  Any
character can take the place of the `/` (`:s#a/b#c#`), and the last `/`
can be left out (`:s/a/b`).  An empty old (`:s//new/`) uses the last
search.  `u` undoes the whole `:s`, as long as it fits in the undo log.

A count can be typed before most commands (`3j`, `2dd`, `d2w`, `3x`).

## CBM keyboard notes

Commodore keyboards are missing some keys vi uses, so:

| vi key | Type | Notes |
|--------|------|-------|
| `Esc` | `RUN/STOP` or `Ctrl` + `[` | the cx16 has a real `Esc` key |
| `~` | `π` (`Shift` + `↑`) | PETSCII has no `~` |
| `^` | `↑` | PETSCII puts `↑` where ASCII has `^` |
| `_` | `C=` + `@` | |
| `\|` | `Shift` + `-` | |
| `{` `}` | — | not in PETSCII, so `%` matches `( )` and `[ ]` only |
| `Backspace` | `DEL` | |
| arrow keys | cursor keys | work in nav, insert and replace mode |

ASCII files (from other computers) are translated to PETSCII when read and
back when written, so their letters show up in the right case.  A file is
taken as ASCII when it has more lowercase than uppercase ASCII letters and
no PETSCII capitals (with no letters at all: when it has LF line endings).
`:set ascii` and `:set petscii` change how the file is written, `:set`
shows which it is.  ASCII `_` `|` `~` become the PETSCII characters typed
for them; `{` `}` have no PETSCII form and show as graphics characters.
The translation is one to one, so bytes that are not text survive a round
trip unchanged.

Line endings are found when a file is read: CR (Commodore), LF (Unix) or
CR LF (DOS/Windows, held as CR while editing).  `:set cr`, `:set lf` and
`:set crlf` change them for writing; switching between CR and LF changes
every CR and LF in the text, and can't be undone with `u`.

`:r` finds the format of the file it reads the same way and converts it
to the text's: its line endings become the text's, and an ASCII file is
translated to PETSCII.  Read into an empty text, the text takes on the
file's format, as with `:e`.

## Moving

| Keys | Action | Status |
|------|--------|--------|
| `h` `j` `k` `l` | left, down, up, right | ✅ |
| cursor keys, `Space`, `DEL` | same as `l`, `h` and the arrows | ✅ |
| `0`, `HOME` | start of line | ✅ |
| `^` | first non-blank character of line | ✅ |
| `$` | end of line (`n$` moves down n-1 lines first) | ✅ |
| `w` `b` `e` | next word, previous word, end of word | ✅ |
| `W` `B` `E` | the same for blank-separated WORDs | ✅ |
| `G`, `nG` | last line, line n | ✅ |
| `gg`, `ngg` | first line, line n | ✅ |
| `ge` `gE` | end of previous word / WORD | ✅ |
| `H` `M` `L` | top, middle, bottom row of the screen | ✅ |
| `+`, `Return`, `-` | first non-blank of next / previous line | ✅ |
| `_` | first non-blank of the line (`n_` n-1 lines down) | ✅ |
| `\|`, `n\|` | column n | ✅ |
| `f` `F` `t` `T` + char | find char in the line forward / back, onto or before it | ✅ |
| `;` `,` | repeat the last `f` `F` `t` `T` the same / opposite way | ✅ |
| `%` | matching `( )` or `[ ]` (the first one at or after the cursor) | ✅ |
| `(` `)` | previous / next sentence | ⬜ |
| `{` `}` | previous / next paragraph | ⬜ |

## Scrolling

| Keys | Action | Status |
|------|--------|--------|
| `Ctrl-F` `Ctrl-B` | page forward / back (moves the cursor a screen of lines) | ✅ |
| `Ctrl-D` `Ctrl-U` | half a page down / up | ✅ |
| `Ctrl-E` `Ctrl-Y` | scroll one line without moving the cursor | ⬜ |
| `zt` `zz` `zb` (`z<CR>` `z.` `z-`) | cursor line to top / middle / bottom of the screen | ⬜ |
| `Ctrl-L` | redraw the screen | ✅ |

## Inserting

| Keys | Action | Status |
|------|--------|--------|
| `i` `a` | insert before / after the cursor | ✅ |
| `I` `A` | insert at the first non-blank / end of the line | ✅ |
| `o` `O` | open a new line below / above | ✅ |
| `R` | replace mode: typing overwrites | ✅ |
| `gi` `gI` | insert where insert mode was last left / at column 0 | ⬜ |
| count + insert (`3ifoo<Esc>`, `2o`) | repeat the inserted text (on new lines for `o` `O`) | ✅ |

Keys in insert and replace mode:

| Keys | Action | Status |
|------|--------|--------|
| `Esc` | back to nav mode | ✅ |
| `Return` | new line | ✅ |
| `DEL` | delete the character before the cursor (moves left in replace mode) | ✅ |
| cursor keys | move without leaving insert mode | ✅ |
| `Ctrl-W` | delete the word before the cursor | ✅ |
| `Ctrl-U` | delete back to where the insert started (or the line start) | ✅ |
| `Ctrl-T` `Ctrl-D` | indent / unindent the line | ⬜ |
| `Ctrl-V` + char | insert a control character literally | ⬜ |

## Changing text

| Keys | Action | Status |
|------|--------|--------|
| `x` `X` | delete the character under / before the cursor | ✅ |
| `d`motion | delete | ✅ |
| `dd` | delete lines | ✅ |
| `D` | delete to end of line (`d$`) | ✅ |
| `c`motion | change (delete, then insert); `cw` works like `ce` | ✅ |
| `cc`, `S` | change whole lines | ✅ |
| `C` | change to end of line (`c$`) | ✅ |
| `s` | change characters (`cl`) | ✅ |
| `r` + char | replace characters; `r` `Return` splits the line | ✅ |
| `~` (`π`) | switch case and move right | ✅ |
| `J` | join lines with one space | ✅ |
| `gJ` | join lines as they are, without a space | ✅ |
| `>>` `<<`, `>`motion `<`motion | indent / unindent lines by 4 spaces | ✅ |
| `.`, `n.` | repeat the last change (a count replaces its count) | ✅ |
| `u` | undo the last change (one level; `u` again redoes it, like vi) | ✅ |
| `Ctrl-R` | redo the change `u` just undid | ✅ |
| `U` | undo all changes on the line | ❌ |
| `Ctrl-A` `Ctrl-X` | add to / subtract from the number under the cursor | ⬜ |
| `g~` `gu` `gU` motion | switch / lower / upper case | ⬜ |

Operators (`d`, `c`, `y`, `>`, `<`) work with every motion above that is
marked ✅, including `f` `F` `t` `T` `;` `,` `n` `N` `gg` `ge`, and with
counts before either part (`2d3w`).  `j` `k` `G` `gg` `H` `M` `L` `+` `-`
`_` work on whole lines, and `>` `<` always do.

## Copying and pasting

| Keys | Action | Status |
|------|--------|--------|
| `y`motion | yank (copy) | ✅ |
| `yy`, `Y` | yank lines | ✅ |
| `p` `P` | put after / before the cursor (below / above for lines) | ✅ |
| deleted text goes to the yank buffer, so `xp`, `ddp` swap | | ✅ |
| `"a`–`"z` | named registers | ⬜ |
| `"A`–`"Z` | append to a named register | ❌ |

The yank buffer is 1 KB (256 bytes when memory is short); bigger yanks are
refused with "yank too big" (a delete still happens, with "not yanked").

`.` replays the keys of the last change, typed text included, so
`cwfoo<Esc>` then `.` changes the word under the cursor to `foo`.  As in
vim: a count before `.` replaces the change's count (`3dw` then `2.`
does `2dw`) and sticks for later `.`; yanks, motions, `:` commands, `u`
and `Ctrl-R` are not repeated; moving with the cursor keys in insert mode
starts the repeated text over from there.  A change of more than 128 keys
can't be repeated ("too long (.)").

The undo log holds one change (a whole insert session counts as one).
It is 2 KB (512 bytes when memory is short): a change that doesn't fit
can't be undone ("undo too big").  Loading a file empties it.

## Searching

| Keys | Action | Status |
|------|--------|--------|
| `/text` `?text` | search forward / back, wrapping around | ✅ |
| `/` `?` + `Return` | repeat the last search forward / back | ✅ |
| `n` `N` | next match in the same / opposite direction | ✅ |
| `*` `#` | search forward / back for the word under the cursor (as plain text) | ✅ |
| regular expressions | | ❌ (plain text only) |

## Marks

| Keys | Action | Status |
|------|--------|--------|
| `m` + `a`–`z` | set a mark | ⬜ (the buffer has 2 spare marks, so maybe `a` and `b`) |
| `'` + mark, `` ` `` + mark | go to a mark's line / position | ⬜ |
| `''` | back to the position before the last jump | ⬜ |

## Visual mode

| Keys | Action | Status |
|------|--------|--------|
| `v` `V` | select characters / lines, then an operator | ⬜ |
| `Ctrl-V` | block selection | ❌ |
| text objects (`iw` `aw` `ip` …) | | ⬜ |

## Ex commands

| Command | Action | Status |
|---------|--------|--------|
| `:w`, `:w name` | write the file, or write to name | ✅ |
| `:w!` | write a file that was cut short when read over itself | ✅ |
| `:q`, `:q!` | quit, `!` discards changes | ✅ |
| `:wq`, `:x`, `ZZ` | write (`:x` and `ZZ` only if changed) and quit | ✅ |
| `ZQ` | quit discarding changes | ✅ |
| `:e name`, `:e!` | edit another file (a new name starts empty), reload | ✅ |
| `:r name` | read a file in below the cursor line | ✅ |
| `:r $`, `:r $:pattern` | read the disk directory in below the cursor line, one line per file (not on the VIC-20) | ✅ |
| `:n`, `:$`, `:.` | go to line n, the last line, the cursor line (`:$` and `:.` not on the VIC-20) | ✅ |
| `Ctrl-G` | show line count and free memory | ✅ |
| `:@cmd` | send a command to the drive, like `@` in the DOS wedge: `:@s:name` deletes a file, `:@r:new=old` renames one (not on the VIC-20) | ✅ |
| `:@` | show the drive status (not on the VIC-20) | ✅ |
| `:@$`, `:@$:pattern` | show the disk directory, or the files that match (`:@$:*.txt`); a key shows the next screen, Escape stops (not on the VIC-20) | ✅ |
| `:s/old/new/`, `:s/old/new/g` | replace old with new in the cursor line: the first one, or all with `g` (not on the VIC-20) | ✅ |
| `:%s/…`, `:5,10s/…`, `:.,$s/…` | `:s` on a range of lines: `%` all lines, `a,b` with line numbers, `.` (cursor line), `$` (last line) | ✅ |
| line ranges for other commands (`:1,5d`, `:1,5w`) | | ⬜ |
| `:set ascii`, `:set petscii` | write the file as ASCII or PETSCII | ✅ |
| `:set cr`, `:set lf`, `:set crlf` | the file's line endings | ✅ |
| `:set` | show the file's format, e.g. `ascii crlf` | ✅ |
| `:set` options (tabs) | | ⬜ |
| `:g`, `:v` | | ❌ |
| `:!cmd` | | ❌ |
| windows (`:sp`, `Ctrl-W`) | | ❌ |
| `:help` | | ❌ |

## Other

| Keys | Action | Status |
|------|--------|--------|
| `q` `@` | record / play macros | ❌ |
| `:ab`, `:map` | abbreviations, key mappings | ❌ |
| `Ctrl-Z` | suspend | ❌ |

## Differences from vi

* Every line ending starts a new line, so a file that ends with a line
  ending has an empty last line (vi treats the last line ending as the end
  of the last line).
* Control characters (including tabs) are shown as `.`.
* A file too big for memory is read only partly ("too big, cut") and can't
  be written back over itself without `:w!`.
