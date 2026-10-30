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
    ; Detect an REU and return size in KB, 0 without one.
    ; Destructive: detect() writes 9 bytes at the start of every REU bank.
    ; Afterwards $a000-$bfff holds bank 0.
    ;
    sub init() -> uword {
        ubyte detectbanks
        detectbanks, present = detect()
        if not present
            return 0
        ; both addresses count up (an earlier program may have fixed one)
        reu_addrcontrol = 0
        ; detectbanks is the last REU bank, 0 for 256 of them (16 MB)
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

    ;
    ; Detect an REU and its size in banks: returns the last REU bank (0 for
    ; 256 of them) and whether there is an REU.  Smaller REUs repeat their
    ; banks above their size, so the banks are written from the top down
    ; and read back from the bottom up until one doesn't match.
    ; TODO: Make this use the raster line
    ; detection method. Make size detection
    ; non-destructive
    ;
    sub detect() -> ubyte, bool {
        ubyte[] signature = [$00, 'p', 'r', 'o', 'g', '8', 'r', 'e', 'u']
        ubyte[] xsignature = ['x', 'p', 'r', 'o', 'g', '8', 'r', 'e', 'u']
        ubyte i
        ubyte j
        bool found = false

        for i in 255 downto 0 {
            signature[0] = i
            cmd(signature, 0, 9, i, REU_STASH)
        }

        for i in 0 to 255 {
            signature[0] = i
            cmd(xsignature, 0, 9, i, REU_FETCH)
            for j in 0 to 8 {
                if signature[j] != xsignature[j]
                    return i - 1, found
            }
            found = true
        }
        ; all 256 banks: 16 MB.  (the value of i after the loop is
        ; undefined in Prog8, so it isn't returned)
        return 0, found
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
