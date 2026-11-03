; keyecho: stores every key the KERNAL's GETIN returns, for measuring which
; key presses give which PETSCII codes (tests/mega65/keymap.py).
; $7000 counts the keys (mod 256), $7100-$71ff holds them, $7000+1 is set
; to $a5 once the program is running.
%zeropage dontuse

main {
    const uword COUNT = $7000
    const uword READY = $7001
    const uword KEYS = $7100

    sub start() {
        @(COUNT) = 0
        @(READY) = $a5
        repeat {
            ubyte k = cbm.GETIN2()
            if k != 0 {
                @(KEYS + @(COUNT)) = k
                @(COUNT)++
            }
        }
    }
}
