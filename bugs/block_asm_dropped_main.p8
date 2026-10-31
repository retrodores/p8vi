; see block_asm_dropped.p8

%import textio

main {
    sub start() {
        txt.print_ub(level())
        txt.nl()
    }

    asmsub level() -> ubyte @A {
        %asm {{
            lda  #p8b_settings.LEVEL
            rts
        }}
    }
}
