; 1541 stops responding after repeated diskio.exists() on a missing file
; (see bugs/diskio_missing_file.md)
;
; Calls diskio.exists("nofile") 50 times, printing a dot after each.
; Seen with prog8c 14.0-BETA3 (f1ab1ed4) on VICE 3.10 x64sc with a
; true-drive 1541: hung in 6 of 6 runs, and 1 of 2 later, after around
; 20 dots.  Run it a few times.
;
;   prog8c-llvm -target c64 -out build bugs/diskio_missing_file_hang.p8
;   c1541 -format test,52 d64 build/t.d64 -attach build/t.d64 \
;         -write build/diskio_missing_file_hang.prg t,p
;   x64sc -default -warp +autostart-warp -debugcart -drive8type 1541 \
;         -8 build/t.d64 -autostart build/t.d64 -limitcycles 900000000
;
; "done" then a VICE exit through the debug cartridge = no hang;
; "Main CPU: Error - cycle limit reached" in the log = hung.

%import diskio
%import textio
%zeropage basicsafe

main {
    str name = "nofile"
    sub start() {
        ubyte i
        for i in 0 to 49 {
            void diskio.exists(name)
            txt.chrout('.')
        }
        txt.print("done\n")
        @($d7ff) = 0        ; VICE debug cartridge: exit
    }
}
