%import textio
%zeropage basicsafe

; Does the X16 keep its banked RAM over a reset?  Checks a pattern at the
; start, middle and end of a few banks and prints what it finds (and the
; start of bank 1); if none is there, writes the patterns and resets
; through the SMC, like the reset button.  Run as AUTOBOOT.X16, so it runs
; again after the reset:
;
;   prog8c-llvm -srcdirs src:src/cx16 -target cx16 -out build tests/x16/bankreset.p8
;   mkdir -p build/x16fs && cp build/bankreset.prg build/x16fs/AUTOBOOT.X16
;   x16emu -fsroot build/x16fs -echo -warp     (then quit it)
;
; Seen with x16emu and ROM R49: everything kept except the first byte of
; bank 1 ($a000 is $a0 after the reset).
main {
    ubyte[] banks = [1, 2, 5, 63]
    uword[] addrs = [$a000, $b000, $bff0]
    str pattern = "kept over reset!"

    sub at(ubyte bank, uword addr) -> bool {
        ubyte i
        cx16.rambank(bank)
        for i in 0 to 15 {
            if @(addr + i) != pattern[i] ^ bank
                return false
        }
        return true
    }

    sub start() {
        ubyte b
        ubyte a
        ubyte i
        bool any = false
        txt.print("check:")
        for b in 0 to len(banks) - 1 {
            for a in 0 to len(addrs) - 1 {
                txt.spc()
                txt.print_ub(banks[b])
                txt.chrout(':')
                txt.print_uwhex(addrs[a], true)
                if at(banks[b], addrs[a]) {
                    any = true
                    txt.print("=kept")
                } else
                    txt.print("=no")
            }
        }
        txt.nl()
        if any {
            cx16.rambank(1)
            for i in 0 to 31 {
                txt.print_ubhex(@($a000 + i), false)
                txt.spc()
            }
            txt.nl()
            txt.print("done\n")
            return
        }
        for b in 0 to len(banks) - 1 {
            cx16.rambank(banks[b])
            for a in 0 to len(addrs) - 1 {
                for i in 0 to 15
                    @(addrs[a] + i) = pattern[i] ^ banks[b]
            }
        }
        cx16.rambank(1)
        sys.memset($a000, 64, $77)
        txt.print("written, reset\n")
        sys.reset_system()
    }
}
