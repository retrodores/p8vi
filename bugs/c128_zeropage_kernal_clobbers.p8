; c128 target: %zeropage basicsafe hands out $92 and $a4, which the C128
; KERNAL changes during disk I/O
;
; Compiler: prog8c-llvm v14.0-BETA3 (git adcfe18e, branch llvm)
; Target: c128
;
; Build and run (a 1541 disk with a SEQ file t.txt on it):
;   prog8c-llvm -target c128 -out build bugs/c128_zeropage_kernal_clobbers.p8
;   x128 -8 disk.d64 -autostart disk.d64
;
; It copies the zero page, reads t.txt, writes, scratches and reads the
; status (diskio), copies the zero page again, and prints the addresses
; that changed (3 rounds).  With %zeropage dontuse, so nothing here is in
; the zero page but the compiler's scratch bytes.
;
; Printed (x128, 1541):  0B 0C 75 92 A1 A2 A4 B7 B8 BB BC FE
;   0B 0C 75 FE   Prog8's scratch bytes (P8ZP_SCRATCH_PTR, _REG, _W2)
;   A1 A2         the jiffy clock
;   B7 B8 BB BC   the KERNAL's file name length, LA, file name pointer
;   92 A4         the KERNAL's tape/serial bytes -- and free for Prog8:
;
; Expected: basicsafe leaves $92 and $a4 alone on the c128.
; Actual: p8vi (%zeropage basicsafe) got its mode variable at $92 and
; another at $a4; loading a file changed mode to $40 and no key worked
; after that.  (p8vi works around it with %zpreserved in its main module,
; src/p8vi_c128.p8.)
;
; Also: %zpreserved in a module other than the main one has no effect
; (p8vi had it in src/c128/platform.p8 first: still allocated $92).

%import textio
%import diskio
%zeropage dontuse
; which zero page bytes the C128 KERNAL changes during p8vi-like disk I/O
main {
    ubyte[256] before
    ubyte[256] after
    ubyte[256] buf
    bool[256] changed
    sub start() {
        ubyte i
        c128.SETBNK(0, 0)
        repeat 3 {
            sys.memcopy(0, &before, 256)
            ; read a file
            if diskio.f_open("t.txt") {
                while diskio.f_read(&buf, 200) != 0 { }
                diskio.f_close()
            }
            ; write a file, scratch it, read the status
            void diskio.f_open_w("zz,s,w")
            void diskio.f_write(&buf, 200)
            diskio.f_close_w()
            diskio.delete("zz")
            void diskio.status()
            sys.memcopy(0, &after, 256)
            for i in 2 to 255 {
                if before[i] != after[i]
                    changed[i] = true
            }
        }
        for i in 2 to 255 {
            if changed[i] {
                txt.print_ubhex(i, false)
                txt.spc()
            }
        }
        txt.print("\nend\n")
        repeat { }
    }
}
