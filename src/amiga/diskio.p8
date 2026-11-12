; File I/O routines for the amiga500 and amiga1200 targets, through
; dos.library (Kickstart 1.3 and later): the part of the library's diskio
; module that p8vi uses, with the same names and calls as the other
; targets' (the llvm targets' in particular), until the compiler's
; library has an Amiga diskio.  File names are AmigaDOS's: df0:name,
; work:dir/name, or relative to the current directory.
;
; NOTE: status() and status_code() say only whether the last operation
; worked ("00,ok" and 0, else "01,error" and 1), as on the llvm targets.

%import dos

diskio {
    %option ignore_unused

    bool internal_ok = true     ; whether the last disk operation succeeded, for status() and status_code()
    pointer read_fh             ; the file open for reading (f_open), 0 for none
    pointer write_fh            ; the file open for writing (f_open_w), 0 for none

    sub diskname() -> str {
        ; -- the name of the "disk": AmigaDOS's file system
        return "amigados"
    }

    ; ----- iterative file loader functions -----

    sub f_open(str filenameptr) -> bool {
        ; -- open a file for iterative reading with f_read.
        ;    only one file can be open for reading at a time; opening the next one closes it.
        ;    Returns true if the file is open; else the file that was open stays open.
        pointer fh = dos.Open(filenameptr, dos.MODE_OLDFILE)
        internal_ok = fh != 0
        if not internal_ok
            return false
        f_close()
        read_fh = fh
        return true
    }

    sub f_read(pointer bufferpointer, pointer num_bytes) -> pointer {
        ; -- read from the currently open file, up to the given number of bytes.
        ;    returns the actual number of bytes read, 0 at the end of the file or on an error.
        if read_fh == 0
            return 0
        long actual = dos.Read(read_fh, bufferpointer, num_bytes as long)
        if actual < 0
            return 0
        return actual as pointer
    }

    sub f_close() {
        ; -- end an iterative file loading session.
        ;    it is safe to call this multiple times, or when no file is open for reading.
        if read_fh != 0 {
            void dos.Close(read_fh)
            read_fh = 0
        }
    }

    sub f_open_w(str filenameptr) -> bool {
        ; -- open a file for iterative writing with f_write.
        ;    An existing file is overwritten. Returns true if the file is successfully opened.
        f_close_w()
        write_fh = dos.Open(filenameptr, dos.MODE_NEWFILE)
        internal_ok = write_fh != 0
        return internal_ok
    }

    sub f_write(pointer bufferpointer, pointer num_bytes) -> bool {
        ; -- write the given number of bytes to the currently open file
        ;    you can call this multiple times to append more data
        if write_fh == 0
            return false
        if num_bytes == 0
            return true
        return dos.Write(write_fh, bufferpointer, num_bytes as long) == (num_bytes as long)
    }

    sub f_close_w() {
        ; -- end an iterative file writing session.
        ;    it is safe to call this multiple times, or when no file is open for writing.
        if write_fh != 0 {
            void dos.Close(write_fh)
            write_fh = 0
        }
    }

    ; ---- other functions ----

    sub status() -> str {
        ; -- the status of the last disk operation: "00,ok" when it succeeded, else "01,error".
        if internal_ok
            return "00,ok"
        return "01,error"
    }

    sub status_code() -> ubyte {
        ; -- the status code of the last disk operation: 0 when it succeeded, else 1.
        if internal_ok
            return 0
        return 1
    }

    sub last_drive() -> ubyte {
        ; -- (the TRS-80's drive search) not known here: 255
        return 255
    }

    sub delete(str filenameptr) {
        ; -- delete a file
        internal_ok = dos.DeleteFile(filenameptr) != 0
    }

    sub rename(str oldfileptr, str newfileptr) {
        ; -- rename a file (on one volume; the new name must not exist)
        internal_ok = dos.Rename(oldfileptr, newfileptr) != 0
    }

    sub exists(str filename) -> bool {
        ; -- returns true if the given file exists, otherwise false.
        pointer lock = dos.Lock(filename, dos.ACCESS_READ)
        if lock == 0
            return false
        dos.UnLock(lock)
        return true
    }
}
