; RAM bank 1 of the C128, for the text: copying between it and bank 0.
;
; The MMU can only show the CPU all of one bank or the other (apart from
; the shared RAM, $0000-$03ff), so the copy runs from the shared RAM, at
; $0200 (BASIC's input buffer, unused while p8vi runs; copied there again
; for every transfer), switching banks for every byte through the MMU's
; preset configurations: a write to $ff02 selects PCRB, bank 1 all RAM
; ($7f); $ff01 PCRA, bank 0 all RAM ($3f), as the KERNAL sets them up.
; About 24 cycles a byte, 25 ms for 1 KB at 1 MHz; with interrupts off
; (bank 1 all RAM has no KERNAL for them), and the program's own
; configuration ($0e: bank 0, KERNAL and I/O) back after.
;
; Used by the page store's drivers in src/c128bank1 and src/c128reu.

bank1 {

    ; copy count bytes from bank 1 at src to bank 0 at dest
    sub fetch(uword src, uword dest, uword count) {
        copy(src, dest, count, 0)
    }

    ; copy count bytes from bank 0 at src to bank 1 at dest
    sub stash(uword src, uword dest, uword count) {
        copy(src, dest, count, COPY_STASH - COPY_FETCH)
    }

    ; the copy loops go to the shared RAM, then run from there
    const uword COPY_AT = $0200
    sub copy(uword src, uword dest, uword count, ubyte entry) {
        sys.memcopy(&copy_code, COPY_AT, COPY_SIZE)
        %asm {{
            lda  p8v_src
            sta  P8ZP_SCRATCH_W1
            lda  p8v_src+1
            sta  P8ZP_SCRATCH_W1+1
            lda  p8v_dest
            sta  P8ZP_SCRATCH_W2
            lda  p8v_dest+1
            sta  P8ZP_SCRATCH_W2+1
            lda  p8v_count
            sta  P8ZP_SCRATCH_B1        ; the bytes after the whole pages
            ldx  p8v_count+1            ; whole pages
            lda  p8v_entry
            beq  +
            jmp  $0200 + (p8b_bank1.p8s_copy_code.stash - p8b_bank1.p8s_copy_code)
+           jmp  $0200                  ; COPY_AT
        }}
    }

    ; the two loops: fetch at the start, stash after it.  relocatable (only
    ; relative branches inside), run at COPY_AT.  in: P8ZP_SCRATCH_W1 the
    ; source, P8ZP_SCRATCH_W2 the destination, X whole pages, then
    ; P8ZP_SCRATCH_B1 more bytes
    const ubyte COPY_FETCH = 0
    const ubyte COPY_STASH = 1          ; (only != COPY_FETCH matters)
    const ubyte COPY_SIZE = 112         ; (BASIC's input buffer has 161 bytes)
    asmsub copy_code() {
        %asm {{
            ; ---- fetch: bank 1 to bank 0
            sei
            ldy  #0
            cpx  #0
            beq  _frest
_fpage      sta  $ff02                  ; bank 1
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff01                  ; bank 0
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _fpage
            inc  P8ZP_SCRATCH_W1+1
            inc  P8ZP_SCRATCH_W2+1
            dex
            bne  _fpage
_frest      cpy  P8ZP_SCRATCH_B1
            beq  _fdone
            sta  $ff02
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff01
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _frest
_fdone      lda  #$0e                   ; the program's configuration
            sta  $ff00
            cli
            rts
stash
            ; ---- stash: bank 0 to bank 1
            sei
            ldy  #0
            cpx  #0
            beq  _srest
_spage      sta  $ff01                  ; bank 0
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff02                  ; bank 1
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _spage
            inc  P8ZP_SCRATCH_W1+1
            inc  P8ZP_SCRATCH_W2+1
            dex
            bne  _spage
_srest      cpy  P8ZP_SCRATCH_B1
            beq  _sdone
            sta  $ff01
            lda  (P8ZP_SCRATCH_W1),y
            sta  $ff02
            sta  (P8ZP_SCRATCH_W2),y
            iny
            bne  _srest
_sdone      lda  #$0e
            sta  $ff00
            cli
            rts
_end
            .cerror _end - p8b_bank1.p8s_copy_code > 112, "copy_code is longer than COPY_SIZE"
            ; !notreached!
        }}
    }
}
