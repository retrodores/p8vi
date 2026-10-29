;
; test routines for gap buffer code
;
%import strings
%import textio
%zeropage basicsafe
%option no_sysinit

; data structure
%import gapbuffer

main {
    sub start() {
        ubyte i

        ; clear with marker byte
        sys.memset(sys.progend(), $9f00-sys.progend(), $55)

        ; our test buffer is 49 bytes
        gapbuffer.init(sys.progend(), sys.progend() + 49)

        txt.cls()

        txt.print("after init\n")

        dump_ram()
        dump_buffer()
;        dump_pointers()

        repeat 20 {
        void gapbuffer.insert_char(' ', gapbuffer.bufend)
        }
        void gapbuffer.insert("abcde", gapbuffer.gappos)
;        gapbuffer.insert_char('a', gapbuffer.gappos)
;        gapbuffer.insert_char('b', gapbuffer.gappos)
;        gapbuffer.insert_char('c', gapbuffer.gappos)
;        gapbuffer.insert_char('d', gapbuffer.gappos)
;        gapbuffer.insert_char('e', gapbuffer.gappos)
        txt.print("after insert\n")
        dump_pointers()
        dump_ram()
        dump_buffer()
;        repeat {}

        void gapbuffer.insert("fghij", gapbuffer.gappos)
        dump_pointers()
        dump_ram()
        dump_buffer()

;        repeat {}
        gapbuffer.move_gap(23)
        void gapbuffer.insert("klmno", gapbuffer.gappos)

        ; move_cursor should move to the spot to the right
        ; of point on delete as gapstart will move 1 byte left
        ; to delete character.  (backspace it perhaps)
        ; perhaps insert should move one to the right also but
        ; the inserted character goes at gapstart?
        ; meaning the point is between the existing character and
        ; the spot for the new one.
        gapbuffer.move_gap(2)
        repeat 20 {
            void gapbuffer.delete_char(gapbuffer.gappos)
        }
        dump_pointers()
        dump_ram()
        dump_buffer()
        gapbuffer.move_gap(40)
        void gapbuffer.insert("Prog8", gapbuffer.gappos)
        dump_pointers()
        dump_ram()
        dump_buffer()
        repeat {}
    }

    sub dump_pointers() {
        txt.print("ramstart: ")
        txt.print_uwhex(gapbuffer.ramstart, true)
        txt.nl()
        txt.print("ramtop: ")
        txt.print_uwhex(gapbuffer.ramtop, true)
        txt.nl()
        txt.print("gapstart: ")
        txt.print_uwhex(gapbuffer.gapstart, true)
        txt.nl()
        txt.print("gapend: ")
        txt.print_uwhex(gapbuffer.gapend, true)
        txt.nl()
        txt.print("gapsize: ")
        txt.print_uwhex(gapbuffer.gapsize, true)
        txt.nl()
        txt.print("bufend: ")
        txt.print_uwhex(gapbuffer.bufend, true)
        txt.nl()
        txt.print("gappos: ")
        txt.print_uwhex(gapbuffer.gappos, true)
        txt.nl()
        txt.print("free(): ")
        txt.print_uwhex(gapbuffer.free(), true)
        txt.nl()
    }

    sub dump_buffer() {
        ubyte i
        txt.nl()
        for i in 0 to 15 {
            txt.print_ubhex(gapbuffer.get(i), false)
            txt.spc()
        }
        txt.nl()
        for i in 16 to 31 {
            txt.print_ubhex(gapbuffer.get(i), false)
            txt.spc()
        }
        txt.nl()
        for i in 32 to 47 {
            txt.print_ubhex(gapbuffer.get(i), false)
            txt.spc()
        }
        txt.nl()
        for i in 48 to 63 {
            txt.print_ubhex(gapbuffer.get(i), false)
            txt.spc()
        }
        txt.nl()
    }

    sub dump_ram() {
        ubyte i
        txt.nl()
        for i in 0 to 15 {
            txt.print_ubhex(gapbuffer.ramstart[i], false)
            txt.spc()
        }
        txt.nl()
        for i in 16 to 31 {
            txt.print_ubhex(gapbuffer.ramstart[i], false)
            txt.spc()
        }
        txt.nl()
        for i in 32 to 47 {
            txt.print_ubhex(gapbuffer.ramstart[i], false)
            txt.spc()
        }
        txt.nl()
        for i in 48 to 63 {
            txt.print_ubhex(gapbuffer.ramstart[i], false)
            txt.spc()
        }
        txt.nl()
    }


} ; end of main block

;
; Lets try merging this straight into main for now
;
main {
%option merge

    ; special characters
    const ubyte CHAR_CURSOR     = ' ' + 128

    ; control style keys
    const ubyte KEY_ESCAPE      = 27
    const ubyte KEY_CONTROL_L   = 12

    ; numbers & letters
    const ubyte KEY_0           = '0'
    const ubyte KEY_1           = '1'
    const ubyte KEY_2           = '2'
    const ubyte KEY_3           = '3'
    const ubyte KEY_4           = '4'
    const ubyte KEY_5           = '5'
    const ubyte KEY_6           = '6'
    const ubyte KEY_7           = '7'
    const ubyte KEY_8           = '8'
    const ubyte KEY_9           = '9'
    const ubyte KEY_A           = 'a'
    const ubyte KEY_B           = 'b'
    const ubyte KEY_C           = 'c'
    const ubyte KEY_D           = 'd'
    const ubyte KEY_E           = 'e'
    const ubyte KEY_F           = 'f'
    const ubyte KEY_G           = 'g'
    const ubyte KEY_H           = 'h'
    const ubyte KEY_I           = 'i'
    const ubyte KEY_J           = 'j'
    const ubyte KEY_K           = 'k'
    const ubyte KEY_L           = 'l'
    const ubyte KEY_M           = 'm'
    const ubyte KEY_N           = 'n'
    const ubyte KEY_O           = 'o'
    const ubyte KEY_P           = 'p'
    const ubyte KEY_Q           = 'q'
    const ubyte KEY_R           = 'r'
    const ubyte KEY_S           = 's'
    const ubyte KEY_T           = 't'
    const ubyte KEY_U           = 'u'
    const ubyte KEY_V           = 'v'
    const ubyte KEY_W           = 'w'
    const ubyte KEY_X           = 'x'
    const ubyte KEY_Y           = 'y'
    const ubyte KEY_Z           = 'z'
    ; capital / shifted
    const ubyte KEY_SHIFT_A     = 'A'
    const ubyte KEY_SHIFT_B     = 'B'
    const ubyte KEY_SHIFT_C     = 'C'
    const ubyte KEY_SHIFT_D     = 'D'
    const ubyte KEY_SHIFT_E     = 'E'
    const ubyte KEY_SHIFT_F     = 'F'
    const ubyte KEY_SHIFT_G     = 'G'
    const ubyte KEY_SHIFT_H     = 'H'
    const ubyte KEY_SHIFT_I     = 'I'
    const ubyte KEY_SHIFT_J     = 'J'
    const ubyte KEY_SHIFT_K     = 'K'
    const ubyte KEY_SHIFT_L     = 'L'
    const ubyte KEY_SHIFT_M     = 'M'
    const ubyte KEY_SHIFT_N     = 'N'
    const ubyte KEY_SHIFT_O     = 'O'
    const ubyte KEY_SHIFT_P     = 'P'
    const ubyte KEY_SHIFT_Q     = 'Q'
    const ubyte KEY_SHIFT_R     = 'R'
    const ubyte KEY_SHIFT_S     = 'S'
    const ubyte KEY_SHIFT_T     = 'T'
    const ubyte KEY_SHIFT_U     = 'U'
    const ubyte KEY_SHIFT_V     = 'V'
    const ubyte KEY_SHIFT_W     = 'W'
    const ubyte KEY_SHIFT_X     = 'X'
    const ubyte KEY_SHIFT_Y     = 'Y'
    const ubyte KEY_SHIFT_Z     = 'Z'

}
