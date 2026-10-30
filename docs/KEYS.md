# vi keys

The vi and vim commands that are practical for this editor on 8-bit
systems, and which are implemented.

| Mark | Meaning |
|------|---------|
| ✅ | implemented |
| ⬜ | to do |
| ❌ | won't do (too big for the target machines, or no use there) |

A count can be typed before most commands (`3j`, `2dd`, `d2w`, `3x`).

## CBM keyboard notes

Commodore keyboards are missing some keys vi uses, so:

| vi key | Type | Notes |
|--------|------|-------|
| `Esc` | `RUN/STOP` or `Ctrl` + `[` | the cx16 has a real `Esc` key |
| `~` | `π` (`Shift` + `↑`) | PETSCII has no `~` |
| `^` | `↑` | PETSCII puts `↑` where ASCII has `^` |
| `Backspace` | `DEL` | |
| arrow keys | cursor keys | work in nav, insert and replace mode |

Text is edited as raw bytes: there is no ASCII/PETSCII translation yet, so
an ASCII file's lowercase letters show up as uppercase (and typed lowercase
letters are saved as ASCII uppercase).

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
| `gg` | first line | ⬜ |
| `ge` `gE` | end of previous word | ⬜ |
| `H` `M` `L` | top, middle, bottom row of the screen | ✅ |
| `+`, `Return`, `-` | first non-blank of next / previous line | ✅ |
| `_` | first non-blank of the line (`n_` n-1 lines down) | ⬜ |
| `\|`, `n\|` | column n | ⬜ |
| `f` `F` `t` `T` + char | find char in the line forward / back, onto or before it | ✅ |
| `;` `,` | repeat the last `f` `F` `t` `T` the same / opposite way | ✅ |
| `%` | matching bracket | ⬜ |
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
| count + insert (`3ifoo<Esc>`) | repeat the inserted text | ⬜ |

Keys in insert and replace mode:

| Keys | Action | Status |
|------|--------|--------|
| `Esc` | back to nav mode | ✅ |
| `Return` | new line | ✅ |
| `DEL` | delete the character before the cursor (moves left in replace mode) | ✅ |
| cursor keys | move without leaving insert mode | ✅ |
| `Ctrl-W` | delete the word before the cursor | ⬜ |
| `Ctrl-U` | delete back to the start of the insert | ⬜ |
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
| `gJ` | join lines without a space | ⬜ |
| `>>` `<<`, `>`motion `<`motion | indent / unindent lines | ⬜ |
| `.` | repeat the last change | ⬜ |
| `u` | undo | ⬜ |
| `Ctrl-R` | redo | ⬜ |
| `U` | undo all changes on the line | ❌ |
| `Ctrl-A` `Ctrl-X` | add to / subtract from the number under the cursor | ⬜ |
| `g~` `gu` `gU` motion | switch / lower / upper case | ⬜ |

Operators (`d`, `c`, `y`) work with every motion above that is marked ✅,
including `f` `F` `t` `T` `;` `,` `n` `N`, and with counts before
either part (`2d3w`).  `j` `k` `G` `H` `M` `L` `+` `-` work on whole lines.

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
refused with "too big to yank" (a delete still happens, with "not yanked").

## Searching

| Keys | Action | Status |
|------|--------|--------|
| `/text` `?text` | search forward / back, wrapping around | ✅ |
| `/` `?` + `Return` | repeat the last search forward / back | ✅ |
| `n` `N` | next match in the same / opposite direction | ✅ |
| `*` `#` | search for the word under the cursor | ⬜ |
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
| `:n` | go to line n | ✅ |
| `Ctrl-G` | show line count and free memory | ✅ |
| `:s/old/new/` | substitute (plain text) | ⬜ |
| line ranges (`:1,5d`, `:%`) | | ⬜ |
| `:set` options (line endings, tabs) | | ⬜ |
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
