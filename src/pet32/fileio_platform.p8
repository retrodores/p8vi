; reading and writing files on the PET.  Prog8's PET diskio has no
; iterative file routines, so these are the ones the editor uses, in the
; way the C64's diskio does them (shared_cbm_diskio.p8), merged into diskio.
; f_open doesn't check that the file is there (the C64's reads a byte
; first): the editor does that before (main.file_exists()).

diskio {
    %option merge, no_symbol_prefixing, ignore_unused

    bool read_open
    bool write_open

    ; open a file for reading with f_read
    sub f_open(str name) -> bool {
        f_close()
        cbm.SETNAM(strings.length(name), name)
        cbm.SETLFS(READ_IO_CHANNEL, drivenumber, READ_IO_CHANNEL)
        void cbm.OPEN()
        void cbm.CHKIN(READ_IO_CHANNEL)
        read_open = cbm.READST() == 0
        cbm.CLRCHN()
        if not read_open
            cbm.CLOSE(READ_IO_CHANNEL)
        return read_open
    }

    ; read up to count bytes to p; returns how many were read (0 after an
    ; error, or at the end).  the file is closed at the end.
    sub f_read(uword p, uword count) -> uword {
        uword n = 0
        ubyte status
        if not read_open
            return 0
        void cbm.CHKIN(READ_IO_CHANNEL)
        while n != count {
            @(p + n) = cbm.CHRIN()
            n++
            status = cbm.READST()
            if status != 0 {
                cbm.CLRCHN()
                f_close()
                if status & STATUS_EOF == 0
                    return 0
                return n
            }
        }
        cbm.CLRCHN()
        return n
    }

    sub f_close() {
        if read_open {
            cbm.CLRCHN()
            cbm.CLOSE(READ_IO_CHANNEL)
            read_open = false
        }
    }

    ; open a file for writing with f_write.  (true doesn't mean the drive
    ; took it: the drive status says that, after f_close_w)
    sub f_open_w(str name) -> bool {
        f_close_w()
        cbm.SETNAM(strings.length(name), name)
        cbm.SETLFS(WRITE_IO_CHANNEL, drivenumber, WRITE_IO_CHANNEL)
        void cbm.OPEN()
        write_open = cbm.READST() == 0
        if not write_open
            cbm.CLOSE(WRITE_IO_CHANNEL)
        return write_open
    }

    ; write count bytes from p
    sub f_write(uword p, uword count) -> bool {
        ubyte status
        if count == 0
            return true
        cbm.CHKOUT(WRITE_IO_CHANNEL)
        repeat count {
            cbm.CHROUT(@(p))
            p++
        }
        status = cbm.READST()
        cbm.CLRCHN()
        return status == 0
    }

    sub f_close_w() {
        if write_open {
            cbm.CLRCHN()
            cbm.CLOSE(WRITE_IO_CHANNEL)
            write_open = false
        }
    }
}

; On the PET, OPEN and CHKIN (BASIC 4's routines, which Prog8's pet32
; library calls) return with the carry set also when they worked, and
; when they fail they don't return: BASIC stops the program with an error
; (FILE OPEN, FILE NOT OPEN, DEVICE NOT PRESENT).  The editor reads the
; carry as on the C64 (set: it failed), so here they return it clear.
; (seen in xpet, a 4032)
cbm {
    %option merge

    asmsub OPEN() clobbers(X,Y) -> bool @Pc, ubyte @A {
        %asm {{
            jsr  $f563
            clc
            rts
        }}
    }

    asmsub CHKIN(ubyte logical @X) clobbers(A,X) -> bool @Pc {
        %asm {{
            jsr  $ffc6
            clc
            rts
        }}
    }
}
