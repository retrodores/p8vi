# Missing files: 1541 hangs and lost keys

Two related problems found while testing the editor's file commands, on
prog8c 14.0-BETA3 (commit f1ab1ed4, branch llvm), C64 target, VICE 3.10
x64sc with a true-drive 1541.  The first is understood well enough to work
around; the second is not understood yet.

## 1. `diskio.exists()` / `diskio.f_open()` on a missing file hangs the drive

**Status:** worked around in `src/main.p8`.  Not confirmed on real hardware,
and not yet known whether the cause is `diskio`, the KERNAL, the 1541 or VICE.

### Symptom

The editor hung while saving, at random, with the drive light flashing red.
The disk then holds an unclosed file (`*seq`, 0 blocks).  Saving used to call
`diskio.exists(name)` first, to delete an existing file before writing.

### What `exists()` does

`diskio.exists()` calls `diskio.f_open()`, which (shared_cbm_diskio.p8):

1. `OPEN 12,8,12,"name"`
2. `CHKIN 12` (`reset_read_channel`), then `CHRIN` to read the first byte
3. on failure, `f_close()` and `CLOSE 12`

For a missing file the drive answers the OPEN with `62, file not found` and
never opens the channel, but step 2 still makes it TALK on that channel.

### Reproduction

`bugs/diskio_missing_file_hang.p8` calls `diskio.exists("nofile")` 50 times.
Build and run commands are in its header.  It hung in 6 of 6 runs, and 1 of
2 later, after around 20 calls in the runs I looked at.

Earlier variants of the editor's save sequence (exists, delete, open with
`,s,w`, write, close, `status_code()`, 20 files per run) hung in 2 of 5 and
3 of 6 runs, always inside `exists()` of a file that did not exist yet.

### State when hung

From the VICE remote monitor (`-remotemonitor`, port 6510):

* C64 PC in the KERNAL serial routines (`$EDD6`/`$EDD9`/`$EEA9`), stack:
  `CHKIN` (`$F247`) <- `diskio.f_open` <- `diskio.exists` <- caller.
  The KERNAL waits for the drive to turn the bus around after TALK + the
  secondary address, with no timeout.
* `$98` (open files) = 1, `$0259` (logical file table) = 12, `$B8/$B9/$BA`
  (LA/SA/FA) = `$0C/$6C/$08`: the C64 is in the CHKIN for logical file 12.
* 1541: PC in its idle loop (`$EC17`/`$EC2B`), error buffer at `$02D5` reads
  `62, FILE NOT FOUND,00,00`.

Something builds up with every failed open, since the first ones work
(in the save loop, the hang came on the 7th to 14th file).

### Workaround in the editor

* `save_file()` deletes the file unconditionally (`diskio.delete`, which
  sends `s:name` on the command channel and is harmless if the file isn't
  there), then writes.  20 saves x 6 runs, and overwriting 20 existing files
  x 4 runs: no hangs.
* `load_file()` calls `file_exists()` before `diskio.f_open()`: OPEN the
  file, read the status from the command channel, CLOSE it, without CHKIN on
  the file's channel.  `bugs/diskio_missing_file_ok.p8` does this 50 times:
  0 of 6 runs hung, and each read shows the right `62`.

### To find out

* Does it happen on a real C64 + 1541, and with other drives (1571, SD2IEC)?
* Does it happen with VICE's non-true-drive (virtual) drive?
* What builds up: drive buffers/channels, C64 file table, bus state?
* Should `diskio.exists()` / `f_open()` check the command channel first, as
  `file_exists()` does, instead of reading from a channel that never opened?

## 2. Keys typed ahead during a failed load are lost

**Status:** not understood, not fixed.

### Symptom

With several failing reads queued in VICE's key buffer:

```
-keybuf ':e t.txt\n:r nofile\n:r nofile\n:r nofile\n'
```

the editor ends up in insert mode with lines like `file` and ` nofile` in the
text.  One or two failed reads in a row work; three or more go wrong, the
same way every time (also with `-keybuf-delay 20` and `100`).

### Key log

A scratch build of the editor logged every key its main loop received
(`cbm.GETIN2`).  Of the 39 keys sent it got 28:

```
sent:     :e t.txt⏎  :r nofile⏎  :r nofile⏎  :r nofile⏎
received: :E T        NOFILE⏎     NOFILE⏎     NOFILE⏎
```

`.TXT⏎:R` and then `:R` each time never arrived.  But `t.txt` *was* loaded,
so the picture is incomplete: maybe the lost keys were read by something
else that acted on them (for example a KERNAL line input that echoes to
the screen).

### Ruled out

* Not caused by `file_exists()`: the same keys are lost when `load_file()`
  goes straight to `diskio.f_open()` (the old code).
* Not caused by `diskio.status()`: the editor now reads the status itself
  with a checked CHKIN (`read_disk_status()` in `src/main.p8`), and the keys
  are still lost.

### Suspects

* `diskio.status()` (and `status_code()`) do `void cbm.CHKIN(15)` and then
  read with `CHRIN`.  If CHKIN fails, CHRIN reads from the *keyboard*: the
  KERNAL screen editor, which takes typed keys up to RETURN.  That would eat
  typed-ahead keys.  It's a real weakness in the library code, but replacing
  it did not make this problem go away, so it is not the (only) cause.
* `diskio.f_open()` and `f_read()` read with `CHRIN` after `CHKIN` too.
* VICE's `-keybuf` feeding (10 keys at a time) while the C64 is in KERNAL
  serial routines; the losses fall near those 10-key boundaries.

### To find out

* Type ahead by hand on a real C64 (or in VICE without `-keybuf`) during a
  failed `:r`: are keys lost?
* Watch `$C6` (keyboard buffer count) and `$0277-$0280` with a VICE
  watchpoint during a failed load, to see which code removes the keys.

## Related

`bugs/side_effect_calls_merged.p8`: a compiler bug that makes
`diskio.status_code()` return the first digit twice (`62` reads as `66`).
