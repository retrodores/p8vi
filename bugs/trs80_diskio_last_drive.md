# Request: diskio.last_drive() for the TRS-80 profiles

A prompt for the prog8c-llvm (compiler) side, from p8vi, 2026-11-10.

---

Add a `diskio.last_drive() -> ubyte` to the llvm16 TRS-80 profiles: the
drive number (0-7) that the DOS opened the last file on, or 255 when it
isn't known.

## Why

The TRS-80 DOSes search every drive when a file spec has no drive number
(`T/TXT` rather than `T/TXT:1`), and a program can't tell which drive the
file was found on.  p8vi (a vi for 8-bit machines) saves safely: it
writes the text to `p8vi.tmp`, then deletes the old file and renames the
temporary one over it.  A file opened from drive 1 as plain `t/txt` is
deleted from drive 1, but `p8vi.tmp` is created on the first drive the DOS
can write to (drive 0), so a save moves the file from drive 1 to drive 0.
This was confirmed in trs80gp on the Model 4 (LS-DOS 6.3, drive 0
writable, `-d1 :lu4`).  With the drive the file was opened from, p8vi can
put the temporary file on that drive (`p8vi.tmp:1`) and rename it to
`t/txt:1`.

## What to add

1. In the profiles' C file layer, a static byte, `last_drive`, starting at
   255.
   - `z80-trs80-m4` (`z80-trs80-m4-files.c`, which has its own `open()`):
     after a successful `@OPEN` or `@INIT`, copy the drive number from the
     file's FCB.
   - `z80-trs80` (Model III LDOS, z88dk's stdio plus
     `z80-trs80-files.c`): after a successful fopen.  `prog8_trs80_fopen`
     wraps `fopen`, and the FCB is
     `((struct TRSDOS_FILE *)fp->desc.fd)->fcb`, as `read_position()` uses
     it.
   - `z80-trs80-m3-trsdos` (TRSDOS 1.3): the same, if TRSDOS 1.3's open
     FCB holds the drive.  If it doesn't, leave the value at 255 there.
   - When an open fails, set `last_drive` to 255, so a stale value isn't
     taken for the new file's drive.
   - Opens to read and opens to write (`f_open`, `f_open_w`, `load`,
     `exists` and so on) all set it.  Every open goes through the same
     `open()`/`fopen`, so one place per profile should cover them.
2. Expose it the way `status_code()` is exposed:

   ```prog8
   ; the drive (0-7) the DOS opened the last file on (found by searching
   ; the drives when the name had no :d), or 255 if unknown
   sub last_drive() -> ubyte
   ```

   - Keep it in a byte that is saved when the file opens.  Don't read it
     from the FCB when it's asked for: the FCB is freed at close, and
     callers ask after `f_close()` (they only know the load worked by
     then).
   - Avoid the name `drive` or `drivenumber`: on the CBM targets
     `diskio.drivenumber` is the device number (8, 9, ...), something
     else.
3. On the other llvm16 targets (and in the docs), either leave it out or
   have it return 255.  p8vi only calls it in its TRS-80 builds.

## To check

- Which FCB byte holds the drive after an open.  I believe it is FCB+6 on
  LDOS 5 and LS-DOS 6, but I haven't verified it.  Check in trs80gp that
  it is the drive the file was *found* on after a search, not just a spec
  that was parsed.  @FSPEC alone may leave it 0 or unset until @OPEN
  fills it in.
- The test: put `T/TXT` on drive 1 only, with drive 0 writable (no
  `-im wp 0 on`).
  - `f_open("t/txt")`, then `f_close()`: `last_drive()` should be 1.
  - `f_open("t/txt:1")`: 1.
  - `f_open_w("new/txt")`: the drive the DOS created it on (0 here).
  - `f_open("missing/txt")`: 255.
- It costs one byte and a few instructions in `open()`.

## How p8vi will use it

- `:e name` with no `:d` in the name saves `diskio.last_drive()` with the
  file.
- `:w` of that same file then writes `p8vi.tmp:d` and renames it to
  `name:d`.
- If the value is 255, p8vi falls back to letting the DOS choose, which
  is what it does today.
