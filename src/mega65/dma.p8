;
; MEGA65 DMA: copies with the DMA controller (F018 "DMAgic"), for the page
; store's pages in banks 4 and 5 (src/mega65dma) and the font build's
; character set (src/mega65/font.p8).
;
; One enhanced job in the F018A list layout (.mega65-reference chapters 5
; and 8): options ($0a: F018A, $80/$81: the source and destination
; megabytes, $00: end), then command, count, source (address, bank),
; destination (address, bank) and modulo.  The banks are the 64 KB banks of
; the megabyte; bit 7 of a bank byte would select I/O, so they must stay
; below $80.  The CPU stops until the job is done, and the job doesn't
; change the memory map, so the KERNAL and interrupts aren't affected (a
; 1 KB copy takes about 50 microseconds).
;
dma {
    ubyte[17] @shared job = [$0a,               ; option: F018A
                             $80, 0,            ; source megabyte
                             $81, 0,            ; destination megabyte
                             $00,               ; end of options
                             $00,               ; command: copy
                             0, 0,              ; count
                             0, 0, 0,           ; source address, bank
                             0, 0, 0,           ; destination address, bank
                             0, 0]              ; modulo (unused)

    ; copy count bytes from src in bank sbank to dst in bank dbank, in
    ; chip RAM (the first megabyte)
    sub copy(uword src, ubyte sbank, uword dst, ubyte dbank, uword count) {
        far(0, src, sbank, 0, dst, dbank, count)
    }

    ; the same anywhere: megabyte, bank and address of each end (so
    ; $ff7e800 is megabyte $ff, bank $07, $e800)
    sub far(ubyte smb, uword src, ubyte sbank, ubyte dmb, uword dst, ubyte dbank, uword count) {
        job[2] = smb
        job[4] = dmb
        pokew(&job + 7, count)
        pokew(&job + 9, src)
        job[11] = sbank
        pokew(&job + 12, dst)
        job[14] = dbank
        run()
    }

    ; start the job.  all the list address registers are written every time:
    ; BASIC 65 uses DMA too (screen scrolling), and writing $d702 clears $d704
    asmsub run() clobbers(A) {
        %asm {{
            lda  #0
            sta  $d702              ; the list is in bank 0
            sta  $d704              ; of megabyte 0
            lda  #>p8b_dma.p8v_job
            sta  $d701
            lda  #<p8b_dma.p8v_job
            sta  $d705              ; start an enhanced job
            rts
        }}
    }
}
