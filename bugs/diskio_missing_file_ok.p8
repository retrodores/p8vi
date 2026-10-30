; The workaround for bugs/diskio_missing_file_hang.p8 (see
; bugs/diskio_missing_file.md): open the missing file, read the status from
; the command channel, close it - no CHKIN/CHRIN on the file's own channel.
; Prints the second digit of the status ("2" of "62") 50 times.
; Same build and run commands as diskio_missing_file_hang.p8: 0 of 6 runs hung.

%import diskio
%import strings
%import textio
%zeropage basicsafe

main {
    str name = "nofile"
    sub start() {
        ubyte i
        pointer msg
        for i in 0 to 49 {
            cbm.SETNAM(strings.length(name), name)
            cbm.SETLFS(12, 8, 12)
            void cbm.OPEN()
            msg = diskio.status()
            cbm.CLOSE(12)
            txt.chrout(msg[1])
        }
        txt.print("\ndone\n")
        @($d7ff) = 0        ; VICE debug cartridge: exit
    }
}
