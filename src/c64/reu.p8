;
; C64 REU banking: 8 KB "RAM banks" at $a000-$bfff, like the Commander X16.
;
; The REU holds the banks; the current one is copied into $a000-$bfff and
; back.  Switching stashes the current bank and fetches the new one, 16 KB
; of DMA: about 18 ms (60 switches take 66 jiffies).  With track_changes
; set, a bank that wasn't modified isn't stashed, which halves that.
;
; The REU sees the same memory map as the CPU, so BASIC must be banked out
; (Prog8's startup does that, unless floats are used or %option no_sysinit
; is set), or a stash of $a000 would save the BASIC ROM.
;

reu {
%option force_output    ; avoids circular reference issue

    ; memory-mapped ubyte
    &ubyte reu_status           = $df00 ; read-only
    &ubyte reu_cmdreg           = $df01

    ; command bits
    const ubyte REU_EXECUTE     = %10000000
    const ubyte REU_AUTOLOAD    = %00100000
    const ubyte REU_IMMEDIATE   = %00010000
    const ubyte REU_C64TOREU    = %00000000
    const ubyte REU_REUTOC64    = %00000001
    const ubyte REU_DOSWAP      = %00000010
    const ubyte REU_DOCOMPARE   = %00000011

    ; reu commands
    const ubyte REU_FETCH       = REU_EXECUTE|REU_IMMEDIATE|REU_REUTOC64
    const ubyte REU_STASH       = REU_EXECUTE|REU_IMMEDIATE|REU_C64TOREU
    const ubyte REU_SWAP        = REU_EXECUTE|REU_IMMEDIATE|REU_DOSWAP

    ; memory mapped uword
    &uword reu_c64addr          = $df02 ; low, $df03 high
    &uword reu_extaddr          = $df04 ; low, $df05 high

    ; memory-mapped ubyte
    &ubyte reu_extbank          = $df06

    ; memory mapped uword
    &uword reu_len              = $df07 ; low, $df08 high

    ; memory-mapped ubyte
    &ubyte reu_intmask          = $df09
    &ubyte reu_addrcontrol      = $df0a
    const ubyte REU_ADDRFIXC64  = %10000000
    const ubyte REU_ADDRFIXREU  = %01000000
    &ubyte reu_start            = $ff00 ; write anything to start

    ; is an REU present?
    bool present = false
    ; current bank
    ubyte current_bank = 0
    ; number of reu real banks (256 max)
    uword banks = 0
    ; number of simulated 8KB banks (capped at 256, 2 MB, like the X16)
    uword rambanks = 0

    ; with track_changes set, the current bank is only stashed when
    ; modified is set (set it after writing to $a000-$bfff).  without it,
    ; every switch stashes the current bank, which is always safe.
    ; (modified stays true then)
    bool track_changes = false
    bool modified = true

    ;
    ; Detect an REU and return size in KB, 0 without one.  The REU's memory
    ; is left as it was (see detect()).  Afterwards $a000-$bfff holds bank 0.
    ;
    sub init() -> uword {
        ubyte detectbanks
        detectbanks, present = detect()
        if not present
            return 0
        ; detectbanks is the last REU bank
        banks = detectbanks as uword + 1
        rambanks = banks * 8
        if rambanks > 256
            rambanks = 256
        ; $a000-$bfff becomes bank 0, so the first switch doesn't stash
        ; whatever was there before into it
        current_bank = 0
        cmd($a000, 0, 8192, 0, REU_FETCH)
        modified = not track_changes
        return banks * 64
    }

    ; where detect() probes, in every REU bank: the end of the bank, away
    ; from anything a program keeps at the start of bank 0
    const uword PROBE_ADDR = $fff8
    const ubyte PROBE_LEN = 8

    ;
    ; Detect an REU and its size in banks: returns the last REU bank (255
    ; for 16 MB) and whether there is an REU.
    ;
    ; Doesn't change the REU's memory, so whatever is in it (text to
    ; recover after a reset, say) survives.  REU sizes are powers of two, so
    ; a marker is put in bank 1, 2, 4 ... 128 in turn until one doesn't
    ; stay there (a 1764 has no banks 4-7) or shows up in bank 0 (a smaller
    ; REU repeats its banks above its size).  Each probe swaps its marker in
    ; and back out again (REU_SWAP), 8 bytes at a time.  The REU registers
    ; are changed.
    ;
    sub detect() -> ubyte, bool {
        ubyte n
        ; both addresses count up (an earlier program may have fixed one)
        reu_addrcontrol = 0
        ; there is an REU if a marker put in bank 0 can be read back
        if not probe(0)
            return 0, false
        n = 1
        repeat 8 {
            if not probe(n)
                return n - 1, true
            n <<= 1
        }
        return 255, true
    }

    ubyte[PROBE_LEN] probe_mark = ['p', '8', 'r', 'e', 'u', 'd', 'e', 't']
    ubyte[PROBE_LEN] probe_saved
    ubyte[PROBE_LEN] probe_seen

    ; puts a marker in REU bank b and returns whether bank b is there: the
    ; marker can be read back from it, and (unless b is 0) not from bank 0.
    ; then puts back what was there.
    sub probe(ubyte b) -> bool {
        bool found
        probe_mark[PROBE_LEN - 1] = b
        sys.memcopy(probe_mark, probe_saved, PROBE_LEN)
        ; afterwards bank b holds the marker, probe_saved what was there
        cmd(probe_saved, PROBE_ADDR, PROBE_LEN, b, REU_SWAP)
        found = marked(b) and (b == 0 or not marked(0))
        cmd(probe_saved, PROBE_ADDR, PROBE_LEN, b, REU_SWAP)
        return found
    }

    ; whether REU bank b holds probe_mark
    sub marked(ubyte b) -> bool {
        ubyte i
        ; without an REU nothing is fetched, so start with something else
        probe_seen[PROBE_LEN - 1] = ~probe_mark[PROBE_LEN - 1]
        cmd(probe_seen, PROBE_ADDR, PROBE_LEN, b, REU_FETCH)
        ; (not sys.memcmp: with basicsafe it doesn't assemble on the C64,
        ; see bugs/memcmp_c64_basicsafe.p8)
        for i in 0 to PROBE_LEN - 1 {
            if probe_seen[i] != probe_mark[i]
                return false
        }
        return true
    }

    sub cmd(uword c64addr, uword reuaddr, uword length, ubyte bank, ubyte command) {
        reu_c64addr = c64addr
        reu_extaddr = reuaddr
        reu_extbank = bank
        reu_len = length
        reu_cmdreg = command
    }

    ; switch to logical bank banknum (0 to rambanks-1).  A bank number past
    ; the end of a smaller REU lands on a lower bank, so check it first.
    sub bank(ubyte banknum) {
        ; if banknum == current_bank we want
        ; to leave the bank alone. do nothing.
        if banknum == current_bank
            return

        ; save our current bank
        if modified
            save(current_bank)

        ; fetch new bank
        cmd($a000, (banknum % 8) as uword * 8192, 8192, banknum / 8, REU_FETCH)
        current_bank = banknum
        modified = not track_changes
    }

    ; save/copy $A000 to arbitary logical bank
    sub save(ubyte savebank) {
        cmd($a000, (savebank % 8) as uword * 8192, 8192, savebank / 8, REU_STASH)
    }
}
