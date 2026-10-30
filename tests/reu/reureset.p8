%import conv
%import textio
%import reu
%zeropage basicsafe

; Does the REU keep its memory over a reset?  The first run writes a
; pattern into REU bank 3, puts a CBM80 "cartridge" in RAM at $8000 that
; starts this program again after a reset, prints "pattern written" and
; waits for a reset (tests/reu/reutest.py resets VICE through its
; monitor).  The second run finds the pattern: exit code 0, or 1 if it is
; gone.
main {
    str pattern = "survives reset?!"
    ubyte[16] seen
    ; the KERNAL's reset jumps through $8000 if $8004 holds "CBM80", before
    ; it sets up anything.  this does what it would (IOINIT, RAMTAS,
    ; RESTOR, CINT), removes the signature and starts the program again;
    ; the address is filled in from the BASIC stub's SYS line.
    ubyte[] hook = [$09, $80, $09, $80, $c3, $c2, $cd, $38, $30,
                    $20, $a3, $fd, $20, $50, $fd, $20, $15, $fd, $20, $5b, $ff,
                    $a9, $00, $8d, $04, $80, $58, $4c, $00, $00]

    sub start() {
        bool same = true
        uword entry
        ubyte i
        void reu.init()
        reu.cmd(seen, $1234, 16, 3, reu.REU_FETCH)
        for i in 0 to 15 {
            if seen[i] != pattern[i]
                same = false
        }
        if reu.present and seen[0] == 0 and seen[15] == 0 {
            ; first run (VICE starts with an empty REU)
            reu.cmd(pattern, $1234, 16, 3, reu.REU_STASH)
            ; the stub is "<link> <line> SYS 2071 ..." from $0801
            entry = conv.str2uword($0807)
            hook[len(hook) - 2] = lsb(entry)
            hook[len(hook) - 1] = msb(entry)
            sys.memcopy(hook, $8000, len(hook))
            txt.print("pattern written")
            repeat { }
        }
        txt.print(if same "pattern kept" else "pattern GONE")
        repeat 5 sys.waitvsync()
        @($d7ff) = if same 0 else 1
    }
}
