; sys.memcmp() doesn't assemble on the C64 with %zeropage basicsafe
;
;   prog8c-llvm -target c64 -out build bugs/memcmp_c64_basicsafe.p8
;
;   memcmp_c64_basicsafe.asm:...: error: not a direct page address bits '$cfe0'
;   (4 times)
;
; memcmp in shared_sys_functions.p8 takes its addresses in cx16.r0 and
; cx16.r1 and reads them with "lda (cx16.r0),y".  That needs the virtual
; registers in zero page, but on the C64 with basicsafe they are at
; $cfe0-$cfff.  With %zeropage kernalsafe it assembles (the registers
; are in zero page then).  Seen with prog8c 14.0-BETA3 (f1ab1ed4); the upstream
; library has the same code.  (Other routines that use (cx16.rN),y may
; have the same problem.)

%import textio
%zeropage basicsafe

main {
    ubyte[4] a = [1, 2, 3, 4]
    ubyte[4] b = [1, 2, 3, 5]

    sub start() {
        txt.print_b(sys.memcmp(a, b, 4) as byte)
    }
}
