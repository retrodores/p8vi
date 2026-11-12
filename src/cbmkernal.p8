; p8vi's CBM parts: the KERNAL and CBM DOS calls of the editor (main), for
; the CBM targets (each platform.p8 imports this).  Another kind of machine
; gives the same names in its own platform: get_key, ticks, cursor_char,
; rename_file, str2uword_digits, screen_code, EMPTY_ROW, disk_code, status_text, file_exists, read_disk_status,
; disk_error, dos_cmd, dir_cmd (features.DIR), dos_command and scratch
; (features.PREFIX), and the charset module.

%import diskio
%import charset

main {
%option merge

    ; platform.stop() is only for the font builds here (features.FONT)
    const bool PLATFORM_STOP = false
    ; p8vi draws its own cursor (only the TRS-80 Model 4 has the DOS's)
    const bool DOS_CURSOR = false
    sub dos_cursor(bool on) {
    }
    ; a drive spec comes after the file name (the TRS-80's name:1), not
    ; before it (features.PREFIX)
    ; (CP/M: text files end at the first ^Z)
    const bool CTRL_Z_EOF = false
    ; a new text's line ending (editor.p8's ENDING_*): CR
    const ubyte NEW_ENDING = 0
    const bool DRIVE_SUFFIX = false
    ; (features.PREFIX) what ends a drive or path prefix
    const ubyte PATH_SEP = ':'
    sub opened_drive() -> ubyte {
        return 255
    }

    ; a key from the keyboard buffer, 0 for none
    alias get_key = cbm.GETIN2
    ; the jiffy clock (1/60 s), low 16 bits
    alias ticks = cbm.RDTIM16

    ; the cursor: the character under it in reverse
    inline sub cursor_char(ubyte char) -> ubyte {
        return char ^ $80
    }

    ; a character as txt.setchr wants it
    ; (only the start screen uses it, which the X16's ISO build hasn't:
    ; in ISO mode it would be the character itself)
    inline sub screen_code(ubyte char) -> ubyte {
        return txt.petscii2scr(char)
    }

    ; the rows past the end of the text (vi uses ~, PETSCII hasn't one; the
    ; X16's ISO build sets ~ in platform.init)
    str EMPTY_ROW = "-"

    ; rename a file (the safe save: p8vi.tmp to the file's name)
    alias rename_file = diskio.rename

    ; the number of digits the last conv.str2uword() read (it leaves them
    ; in r15)
    inline sub str2uword_digits() -> ubyte {
        return cx16.r15L
    }

    ; send DOS command c ('s' scratch, 'r' rename) for name, keeping its
    ; prefix at the front ("s0:name"; "s0:name" too without one: the MEGA65
    ; wants the drive, "r:new=old" gives 79 SINGLE DRIVE D0 ONLY), with
    ; "=old" after it if old isn't 0.  (diskio.delete() and rename() put "s:"
    ; and "r:" before the whole name, which a prefix doesn't survive)
    sub dos_command(ubyte c, str name, str old) {
        ubyte i = 1
        diskio.list_filename[0] = c
        if prefix_len(name) == 0 {
            diskio.list_filename[1] = '0'
            diskio.list_filename[2] = ':'
            i = 3
        }
        i += strings.copy(name, &diskio.list_filename + i)
        if old != 0 {
            diskio.list_filename[i] = '='
            void strings.copy(old, &diskio.list_filename + i + 1)
        }
        diskio.send_command(diskio.list_filename)
    }

    ; (features.PREFIX) delete a file (one that isn't there is no error)
    sub scratch(str name) {
        dos_command('s', name, 0)
    }

    ; drive status code, from the last read_disk_status(); the message is in status_text
    ubyte disk_code

    ; true if the file can be opened for reading.  diskio.f_open() reads from
    ; the file to find out, and doing that for a file that isn't there (the
    ; drive never opens the channel) makes the 1541 stop responding after a
    ; number of tries.  so open it and read the status from the command
    ; channel instead.
    sub file_exists(str name) -> bool {
        cbm.SETNAM(strings.length(name), name)
        cbm.SETLFS(11, diskio.drivenumber, 11)
        void cbm.OPEN()
        read_disk_status()
        cbm.CLOSE(11)
        return disk_code < 20
    }

    ; read the drive status message and its code.  reading the status clears
    ; it, so check disk_code afterwards, not diskio.status_code().
    ; (like diskio.status(), but that ignores a failing CHKIN and then reads
    ; with CHRIN from the keyboard instead, eating typed keys)
    str status_text = " " * 40
    sub read_disk_status() {
        ubyte n = 0
        ubyte char
        status_text[0] = 0
        cbm.SETNAM(0, status_text)
        cbm.SETLFS(15, diskio.drivenumber, 15)
        void cbm.OPEN()
        if_cc {
            if not cbm.CHKIN(15) {
                while cbm.READST() == 0 and n < len(status_text) - 1 {
                    char = cbm.CHRIN()
                    if char == '\r' or char == '\n'
                        break
                    status_text[n] = char
                    n++
                }
                status_text[n] = 0
            }
            cbm.CLRCHN()
            cbm.CLOSE(15)
        }
        if status_text[0] == 0
            void strings.copy("no drive status", status_text)
        disk_code = 255
        if status_text[0] >= '0' and status_text[0] <= '9'
            disk_code = conv.str2uword(status_text) as ubyte
    }

    ; read and show the drive status message
    sub disk_error() {
        read_disk_status()
        status(status_text)
    }

    ; :@cmd - send a command to the drive (like @ in the DOS wedge) and show
    ; its reply; :@ alone shows the drive status.  :@$ shows the directory.
    sub dos_cmd(str command) {
        if features.DIR and command[0] == '$' {
            dir_cmd(command, false)
            return
        }
        ; (features.ISO, the X16's ISO mode) the command's letters, before
        ; the ':', in capitals: CMDR-DOS wants S, not ISO's s ($73)
        if features.ISO {
            %asm {{
                lda  p8v_command
                sta  P8ZP_SCRATCH_W1
                lda  p8v_command+1
                sta  P8ZP_SCRATCH_W1+1
                ldy  #0
_letter         lda  (P8ZP_SCRATCH_W1),y
                beq  _done
                cmp  #$3a           ; ':'
                beq  _done
                cmp  #$61           ; 'a'
                bcc  +
                cmp  #$7b           ; after 'z'
                bcs  +
                and  #$df
                sta  (P8ZP_SCRATCH_W1),y
+               iny
                bne  _letter
_done
            }}
        }
        ; opening the command channel with a name runs it as a command
        cbm.SETNAM(strings.length(command), command)
        cbm.SETLFS(15, diskio.drivenumber, 15)
        void cbm.OPEN()
        cbm.CLOSE(15)
        disk_error()
    }

    ; :@$ - show the disk directory a screen at a time, :@$:*.txt only the
    ; files that match.  A key shows the next screen, Escape or RUN/STOP
    ; stops, and at the end a key goes back to the text.
    ; :r $ - with insert, read it into the text below the cursor line.
    str dir_line = " " * 40
    sub dir_cmd(str name, bool insert) {
        ubyte rows = 0
        ubyte n
        ubyte low
        ubyte char
        bool more = true
        uword start = 0
        uword position = 0
        if insert {
            ; below the cursor line, as load_file() does
            start = buffer.next_line(cursor())
            if start == buffer.NONE {
                start = buffer.length()
                if add_eol_before(start)
                    start++
            }
            position = start
        } else
            txt.cls()
        cbm.SETNAM(strings.length(name), name)
        cbm.SETLFS(12, diskio.drivenumber, 0)
        void cbm.OPEN()
        if_cc {
            if not cbm.CHKIN(12) {
                ; the drive sends the directory as a BASIC program: skip
                ; its load address and the link of the first line
                repeat 4
                    void cbm.CHRIN()
                while more and cbm.READST() == 0 {
                    ; each line: its number (the size in blocks), the text
                    ; up to a 0, then the link of the next line
                    low = cbm.CHRIN()
                    n = strings.copy(conv.str_uw(mkword(cbm.CHRIN(), low)), dir_line)
                    dir_line[n] = ' '
                    n++
                    repeat {
                        char = cbm.CHRIN()
                        if char == 0
                            break
                        ; (the text gets no control codes, like the reverse
                        ; video of the disk name)
                        if n < len(dir_line) - 1 and (not insert or char >= ' ') {
                            dir_line[n] = char
                            n++
                        }
                    }
                    ; (the drive pads the lines with spaces)
                    while dir_line[n - 1] == ' '
                        n--
                    dir_line[n] = 0
                    void cbm.CHRIN()
                    void cbm.CHRIN()
                    if insert {
                        if buffer.free() <= n {
                            more = false
                            status("buffer full")
                        } else {
                            ; lines go in with a line end between them
                            if position != start {
                                void buffer.insert_char(buffer.eol, position)
                                position++
                            }
                            void buffer.insert(dir_line, position)
                            position += n
                        }
                    } else {
                        txt.print(dir_line)
                        txt.nl()
                        rows++
                        if rows == SCREEN_HEIGHT - 1 {
                            ; (keys are read from the keyboard, not the drive)
                            cbm.CLRCHN()
                            more = wait_key("more")
                            txt.cls()
                            rows = 0
                            void cbm.CHKIN(12)
                        }
                    }
                }
            }
            cbm.CLRCHN()
            cbm.CLOSE(12)
        }
        ; an error (no disk, ...) is shown in place of "end"
        read_disk_status()
        if insert {
            ; like a file: the last line must not join the line after it
            if position < buffer.length()
                void add_eol_before(position)
            set_cursor(start)
            goal_col = 0
            if disk_code >= 20
                status(status_text)
            return
        }
        if disk_code < 20
            void strings.copy("end", status_text)
        if more
            void wait_key(status_text)
        txt.cls()
        view.refresh(true)
    }
}
