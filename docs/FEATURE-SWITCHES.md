# Feature switches in Prog8

p8vi is one editor built in two versions: a full one for the C64 and the
Commander X16, and a smaller one for the VIC-20, which has to fit below
`$8000`.  Optional features can be switched off for a build, and a feature
that is off costs nothing: its code is not in the program at all.

Prog8 has no `#ifdef`, but it gets the same effect from two things it
already does:

1. **Constant folding.**  An `if` whose condition is a constant `false` is
   removed when the program is compiled, along with everything in it.
2. **Removing unused code.**  A subroutine that nothing calls is left out
   of the program.  So when the only call to a feature's code was inside a
   removed `if`, the feature's subroutines, strings and tables go too.

The switches are `const bool`s, and the trick is in writing the tests
on them so that the compiler folds them without filling the build with
warnings.

## One toplevel file per version

The switches live in a small block in the toplevel file, and each version
of the program has its own toplevel file that imports the shared code:

```prog8
; src/p8vi.p8: the full editor, for the C64 and the Commander X16
%import editor
%zeropage basicsafe

features {
    const bool SPLASH = true    ; the start screen
    const bool ASCII = true     ; ASCII files translated to PETSCII and back
    const bool CRLF = true      ; CR LF line endings, :set crlf
}
```

`src/p8vi_vic20.p8` is the same file with its own values.  The shared code
in `src/editor.p8` uses `features.ASCII` and so on without knowing which
build it is in, and the `Makefile` compiles each toplevel file for its
targets.  Turning a feature off for the VIC-20 means editing one line.

## Writing the tests

Here is how the different ways of writing a test behave, measured with
prog8c 14.0-BETA3 for the C64:

| How it's written | Switch on | Switch off |
|---|---|---|
| `if features.X { ... }` | warning "condition is always true" | code removed, warning "always false" |
| `if features.X and <runtime test> { ... }` | no warning | code removed, warning "always false" |
| `flag = features.X and f()` | no warning | call removed, no warning |
| `y = if features.X f() else g()` | no warning | **not folded**: both `f()` and `g()` stay in |
| `when features.X { ... }` | compile error | compile error |

Prog8 warns on any `if` with a constant condition.  With a plain
`if features.X`, every build warns on every switch, whether it is on or off.

### Use `and` with the test that is there anyway

Most feature code already runs under some runtime condition.  Put the
switch in front of it with `and`:

```prog8
if features.ASCII and ascii_file
    translate_text(charset.TO_ASCII)

if features.CRLF and line_ending == ENDING_CRLF {
    ; write CR LF after each line
    ...
}
```

With the switch on, `true and ascii_file` is just `ascii_file`: no extra
code and no warning.  With it off, `false and ...` is `false`, the whole
`if` is removed, and `translate_text()` goes if nothing else calls it.
The build then warns "condition is always false" at that line, which
is fine.  It is only reminding you that the switch is off.

### Or put the switch into a value

A value that later tests read can take the switch as well:

```prog8
ascii_file = features.ASCII and charset.looks_ascii(buf, size, eol == $0a)
```

With `ASCII` off this is `ascii_file = false`, with no call to
`looks_ascii()` and no warning.  If every later use also starts with
`features.ASCII and`, the compiler removes those uses and the code
behind them.

The start screen works the same way: `view.splash = features.SPLASH` at
startup, and `if features.SPLASH and splash` where it is drawn.

### Turning off options that the user types

The editor's `:set` options are looked up in a table of strings.  An option
whose feature is off stays in the table (only a few bytes), but the lookup
skips it, so it gives "bad option":

```prog8
str[] set_options = ["petscii", "ascii", "cr", "lf", "crlf"]

while strings.compare(arg, set_options[i]) != 0 or
        (i == 1 and not features.ASCII) or (i == 4 and not features.CRLF) {
    i++
    ...
}
```

With the switches on, `not features.ASCII` is `false`, so
`i == 1 and false` folds to `false` and that part of the test drops out.

### Avoid if-expressions on a switch

```prog8
; don't: both f() and g() are compiled in, and the constant is tested
; when the program runs
y = if features.X f() else g()
```

The compiler doesn't fold an if-expression whose condition is a constant,
so it is the one form that quietly costs bytes.  (It also gives no
warning, which makes it look like the clean way to write a switch.)  A
small reproducer is in `bugs/ifexpr_const_condition.p8`.  Use an `if`
statement instead.

### Sharing code with a feature

A new feature often needs a few lines that are already somewhere else.
Moving them into a helper subroutine that both places call looks
cleaner, but the build with the feature off then pays for the helper's
call and its variables, and gets nothing for it.  In p8vi, `:r $` needs
`load_file()`'s "where does `:r` put the text" lines.  As a helper, they
cost the VIC-20 18 bytes, and marking the helper `inline` didn't change
that.  So `dir_cmd()` has its own copy, which a build without `DIR`
leaves out.  Compare the size of a build with the feature off before and
after (`tools/listsize.py old.list new.list`).

### Assembly routines

Prog8 never removes an unused `asmsub` itself: it stays in the `.asm` file,
probably because other assembly code could call it by its label.  It still costs
nothing, because the routine is a `.proc` there, and 64tass only assembles
a `.proc` that something references.  So when you look for leftover
feature code, check the `.list` file or the program size, not the `.asm`
file.

## Checking that it worked

Compare the sizes of two builds, one with the switch on and one with it off:

```
make size                 # room left on each target
```

`tools/listsize.py` can also compare two `.list` files and show which
blocks and subroutines grew or shrank.  For p8vi on the VIC-20, turning
the switches off frees:

| Switch | Frees |
|---|---|
| `SPLASH` | 297 bytes |
| `ASCII` | 214 bytes |
| `CRLF` | 289 bytes |
| all three | 795 bytes |

Also check that a build with the switches off still runs.  It is the
version that gets tested least.
