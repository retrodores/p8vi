; zpwatch: which zero page bytes does the MEGA65 ROM change in KERNAL calls?
; (make test-mega65-zp: runs it in xmega65 headless and shows the result)
;
; Prog8's zp_* lists in config/mega65.properties were copied from the C64,
; but the MEGA65 ROM uses zero page differently and its use is private
; (it can change between ROM versions).  For each operation below this
; fills the candidate addresses with $55, copies page 0, runs the
; operation (asm only, so Prog8's own scratch bytes aren't touched), and
; marks every byte that changed; then again with $aa, so a write of the
; same value is still seen.  It prints, per operation, the drive status
; after it (each runs twice, so a write or rename shows 63 the second
; time), how many candidates and how many bytes in all changed, then the
; candidates that changed and every byte that changed.
;
; Not covered: typing a line (CHRIN from the keyboard), SAVE,
; RUN/STOP-RESTORE, and what BASIC 65 needs after the program exits.
%import textio
%zeropage dontuse

main {
    const ubyte NOPS = 10
    ; zp_kernalsafe, the old (C64) zp_basicsafe and Prog8's scratch bytes
    ubyte[] @shared cands = [$02,$03,$04,$05,$06,$07,$08,$09,$0a,$0b,$0c,$0d,$0e,$0f,$10,$11,
                             $12,$13,$14,$15,$16,$17,$18,$19,$1a,$1b,$1c,$1d,$1e,$1f,$20,$21,
                             $22,$23,$24,$25,$39,$3a,$3b,$3c,$3d,$3e,$3f,$40,$41,$42,$43,$44,
                             $45,$46,$47,$48,$4b,$4c,$4d,$4e,$4f,$51,$52,$53,$57,$58,$59,$5a,
                             $5b,$5c,$5d,$5e,$5f,$60,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6a,
                             $6b,$6c,$6d,$6e,$6f,$70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7a,
                             $7b,$7c,$7d,$7e,$7f,$80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$8a,
                             $8b,$8c,$8d,$8e,$8f,$92,$96,$9b,$9c,$9e,$9f,$a6,$b0,$b1,$be,$bf,
                             $f9,$fb,$fc,$fd,$fe,$ff]
    const ubyte NCANDS = len(cands)
    str[NOPS] names = ["getin idle", "chrout+scroll", "open/write/close", "status ch15",
                       "open/read/close", "rename r0:", "scratch s:", "load", "directory", "plot"]
    str @shared s_w = "zptest,s,w"
    str @shared s_r = "zptest,s,r"
    str @shared s_ren = "r0:zpt2=0:zptest"
    str @shared s_scr = "s:zpt2"
    str @shared s_load = "zpload"
    str @shared s_dir = "$"
    str @shared s_line = "zero page watch test line, scrolling the screen\r"
    ubyte[256] @shared mark
    ubyte[256] @shared snap
    ubyte[NOPS] st_hi
    ubyte[NOPS] st_lo

    sub start() {
        ubyte op
        for op in 0 to NOPS-1 {
            sys.memset(&mark, 256, 0)
            probe(op)
            sys.memcopy(&mark, $6000 + (op as uword) * 256, 256)
            st_hi[op], st_lo[op] = status()
        }
        txt.chrout(147)
        ubyte i
        ubyte[256] all
        sys.memset(&all, 256, 0)
        for op in 0 to NOPS-1 {
            uword tab = $6000 + (op as uword) * 256
            txt.print(names[op])
            txt.column(17)
            txt.chrout(st_hi[op])
            txt.chrout(st_lo[op])
            ubyte n = 0
            for i in 0 to NCANDS-1 {
                if @(tab + cands[i]) != 0
                    n++
            }
            txt.print(" cand:")
            txt.print_ub(n)
            n = 0
            i = 0
            repeat 256 {
                if @(tab + i) != 0 {
                    all[i] = 1
                    n++
                }
                i++
            }
            txt.print(" all:")
            txt.print_ub(n)
            txt.nl()
        }
        txt.print("candidates changed:")
        for i in 0 to NCANDS-1 {
            if all[cands[i]] != 0 {
                txt.spc()
                txt.print_ubhex(cands[i], false)
            }
        }
        txt.nl()
        txt.print("all changed:")
        i = 0
        repeat 256 {
            if all[i] != 0 {
                txt.spc()
                txt.print_ubhex(i, false)
            }
            i++
        }
        txt.nl()
    }

    ; drive status, first two characters
    sub status() -> ubyte, ubyte {
        ubyte a = '?'
        ubyte b = '?'
        cbm.SETNAM(0, s_dir)
        cbm.SETLFS(15, 8, 15)
        void cbm.OPEN()
        if cbm.CHKIN(15) == false {
            a = cbm.CHRIN()
            b = cbm.CHRIN()
            while cbm.READST() == 0
                void cbm.CHRIN()
        }
        cbm.CLRCHN()
        cbm.CLOSE(15)
        return a, b
    }

    asmsub probe(ubyte op @A) clobbers(A, X, Y) {
        %asm {{
            sta  _op
            lda  #$55
            jsr  _one
            lda  #$aa
            jsr  _one
            rts
_one
            sta  _pat
            ldx  #p8c_NCANDS
-           ldy  p8v_cands-1,x
            lda  _pat
            sta  $0000,y
            dex
            bne  -
            ldx  #0
-           lda  $00,x
            sta  p8v_snap,x
            inx
            bne  -
            jsr  _call
            ldx  #0
-           lda  $00,x
            cmp  p8v_snap,x
            beq  +
            lda  #1
            sta  p8v_mark,x
+           inx
            bne  -
            rts
_call
            lda  _op
            asl  a
            tax
            lda  _ops,x
            sta  _vec
            lda  _ops+1,x
            sta  _vec+1
            jmp  (_vec)

_op     .byte 0
_pat    .byte 0
_vec    .word 0
_ops    .word _idle, _print, _write, _status, _read, _rename, _scratch, _load, _dir, _plot

_bank0
            lda  #0
            ldx  #0
            jmp  $ff6b

_idle
            ldx  #0
-           ldy  #0
-           sty  _y
            stx  _x
            jsr  $ffe4
            ldy  _y
            ldx  _x
            iny
            bne  -
            dex
            bne  --
            rts
_x      .byte 0
_y      .byte 0

_print
            lda  #30
            sta  _x
_pl         ldy  #0
-           lda  p8v_s_line,y
            beq  +
            sty  _y
            jsr  $ffd2
            ldy  _y
            iny
            bne  -
+           dec  _x
            bne  _pl
            rts

_write
            jsr  _bank0
            lda  #10
            ldx  #<p8v_s_w
            ldy  #>p8v_s_w
            jsr  $ffbd
            lda  #2
            ldx  #8
            ldy  #2
            jsr  $ffba
            jsr  $ffc0
            ldx  #2
            jsr  $ffc9
            lda  #4
            sta  _x
_wl         ldy  #0
-           sty  _y
            tya
            and  #$1f
            ora  #$40
            jsr  $ffd2
            ldy  _y
            iny
            bne  -
            dec  _x
            bne  _wl
            jsr  $ffcc
            lda  #2
            clc
            jmp  $ffc3

_status
            jsr  _bank0
            lda  #0
            jsr  $ffbd
            lda  #15
            ldx  #8
            ldy  #15
            jsr  $ffba
            jsr  $ffc0
            ldx  #15
            jsr  $ffc6
-           jsr  $ffcf
            cmp  #13
            beq  +
            jsr  $ffb7
            beq  -
+           jsr  $ffcc
            lda  #15
            clc
            jmp  $ffc3

_read
            jsr  _bank0
            lda  #10
            ldx  #<p8v_s_r
            ldy  #>p8v_s_r
            jsr  $ffbd
            lda  #2
            ldx  #8
            ldy  #2
            jsr  $ffba
            jsr  $ffc0
            ldx  #2
            jsr  $ffc6
-           jsr  $ffcf
            jsr  $ffb7
            beq  -
            jsr  $ffcc
            lda  #2
            clc
            jmp  $ffc3

_command
            jsr  $ffbd
            lda  #1
            ldx  #8
            ldy  #15
            jsr  $ffba
            jsr  $ffc0
            jsr  $ffcc
            lda  #1
            clc
            jmp  $ffc3

_rename
            jsr  _bank0
            lda  #16
            ldx  #<p8v_s_ren
            ldy  #>p8v_s_ren
            jmp  _command

_scratch
            jsr  _bank0
            lda  #6
            ldx  #<p8v_s_scr
            ldy  #>p8v_s_scr
            jmp  _command

_load
            jsr  _bank0
            lda  #6
            ldx  #<p8v_s_load
            ldy  #>p8v_s_load
            jsr  $ffbd
            lda  #1
            ldx  #8
            ldy  #0
            jsr  $ffba
            lda  #0
            ldx  #<$7000
            ldy  #>$7000
            jmp  $ffd5

_dir
            jsr  _bank0
            lda  #1
            ldx  #<p8v_s_dir
            ldy  #>p8v_s_dir
            jsr  $ffbd
            lda  #2
            ldx  #8
            ldy  #0
            jsr  $ffba
            jsr  $ffc0
            ldx  #2
            jsr  $ffc6
-           jsr  $ffcf
            jsr  $ffb7
            beq  -
            jsr  $ffcc
            lda  #2
            clc
            jmp  $ffc3

_plot
            sec
            jsr  $fff0
            ldx  #5
            ldy  #5
            clc
            jmp  $fff0
        }}
    }
}
