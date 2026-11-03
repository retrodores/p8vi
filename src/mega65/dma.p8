;
; MEGA65 DMA: copies in chip RAM with the DMA controller (F018 "DMAgic"),
; for the page store's pages in banks 4 and 5 (src/mega65dma).
;
; One enhanced job in the F018A list layout (.mega65-reference chapters 5
; and 8): options ($0a: F018A, $00: end), then command, count, source
; (address, bank), destination (address, bank) and modulo.  The banks are
; the 64 KB banks of the first megabyte; bit 7 of a bank byte would select
; I/O, so they must stay below $80.  The CPU stops until the job is done,
; and the job doesn't change the memory map, so the KERNAL and interrupts
; aren't affected (a 1 KB copy takes about 50 microseconds).
;
dma {
    ubyte[13] @shared job = [$0a, $00,         ; options: F018A, end
                             $00,               ; command: copy
                             0, 0,              ; count
                             0, 0, 0,           ; source address, bank
                             0, 0, 0,           ; destination address, bank
                             0, 0]              ; modulo (unused)

    ; copy count bytes from src in bank sbank to dst in bank dbank
    sub copy(uword src, ubyte sbank, uword dst, ubyte dbank, uword count) {
        pokew(&job + 3, count)
        pokew(&job + 5, src)
        job[7] = sbank
        pokew(&job + 8, dst)
        job[10] = dbank
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
