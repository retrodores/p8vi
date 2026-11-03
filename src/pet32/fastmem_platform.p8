; the text stores' byte scans and copies (src/fastmem.p8).  the PET has no
; room for them: like the VIC-20's, its gap buffer keeps its own Prog8
; loops (FAST false; the routines are left out then)
%import fastmem

fastmem {
%option merge
    const bool FAST = false
}
