; c128 target, %zeropage basicsafe: BASIC prints garbage after the program
;
; FIXED in prog8c-llvm (2026-11-07, after 008ea6fb): C128Zeropage.kt no
; longer hands out $18-$1a (TEMPPT, LASTPT).  Verified: w5 now lands at
; $1b.  p8vi keeps its %zpreserved $18,$18 for older and upstream compilers.
;
; Compiler: prog8c-llvm v14.0-BETA3 (git ab65226d8, branch llvm); the
; C128 zero page lists are the same in prog8c-beta (master).
; Target: c128 (BASIC 7)
;
; Build and run:
;   prog8c-llvm -target c128 -asmlist -out build bugs/c128_basicsafe_temppt.p8
;   x128 -autostart build/c128_basicsafe_temppt.prg
; then at READY type:  print 7
;
; Expected: " 7".
; Actual: " 7" followed by garbage (strings and numbers print with the
; rest of BASIC's string pool after them, until RUN or CLR).
;
; codeCore/src/prog8/code/target/zp/C128Zeropage.kt, BASICSAFE, hands
; out $16-$23 among others: BASIC 7's TEMPPT ($18, the index into the
; temporary string descriptor stack, normally $1b), LASTPT ($19/$1a) and
; TEMPST ($1b-$23).  BASIC resets TEMPPT only on RUN, CLR and errors, not
; when SYS returns, so a variable left at $18 breaks every later string.
; What it does depends on the value left there: 1 (as p8vi left it)
; puts the descriptors at $01-$03, over the processor port; $34 happened
; to print fine.  Here w5 lands at $18/$19 (see the .asm: "p8v_w5 = 24 ; zp uword").
; (C64Zeropage.kt's BASICSAFE list leaves its $16-$21 alone.)
;
; Workaround: %zpreserved $18,$18 in the main module.  A fix: take $16-$23
; out of the C128 BASICSAFE list (at least $18; $16/$17 LINNUM and the
; descriptors are scratch to BASIC, TEMPPT is not).  p8vi found it: the
; C128 builds left BASIC printing garbage after :q.

%import textio
%zeropage basicsafe

main {
    uword @requirezp @shared w1
    uword @requirezp @shared w2
    uword @requirezp @shared w3
    uword @requirezp @shared w4
    uword @requirezp @shared w5

    sub start() {
        w1 = $1234
        w2 = $1234
        w3 = $1234
        w4 = $1234
        w5 = 1          ; (TEMPPT = 1, as p8vi left it)
        txt.print("now type: print 7\n")
    }
}
