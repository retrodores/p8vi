#
# Simple Makefile for a Prog8 program.
#

# Cross-platform commands
ifeq ($(OS),Windows_NT)
    CLEAN = del /Q build\*
    CP = copy
    RM = del /Q
    MD = mkdir
    SEP = \\
else
    CLEAN = rm -f build/*
    CP = cp -p
    RM = rm -f
    MD = mkdir -p
    SEP = /
endif

# disk image settings: a 1581 disk (800 KB) for the programs and the
# sample files, read with a 1581 drive on the C64 and the VIC-20.
# (tests/vice/ makes its own 1541 disks)
DISKTYPE=d81
DISKNAME=testgap
DISK=build/$(DISKNAME).$(DISKTYPE)

# Emulator settings
EMU_CMD=x64sc
EMU_BASE=-default -keymap 1 -model ntsc
EMU_DISK08=-8 $(DISK) -drive8type 1581
#EMU_DISK10=-fs10 build -device10 1 -iecdevice10 -virtualdev10
EMU_DISK10=
EMU_CART=
EMU_DISK=$(EMU_DISK08) $(EMU_DISK10)
EMU_DOS=
EMU_KERNAL=
EMU_REUSIZE=512
EMU_REU=-reu -reusize $(EMU_REUSIZE)
EMU=$(EMU_CMD) $(EMU_BASE) $(EMU_KERNAL) $(EMU_DISK) $(EMU_DOS) $(EMU_REU)

PCC=prog8c-llvm
PCCARGSC64=-srcdirs src:src/c64 -asmlist -target c64 -out build
# the C64 REU build: src/c64reu (its store_platform) comes before src/c64
PCCARGSC64REU=-srcdirs src:src/c64reu:src/c64 -asmlist -target c64 -out build
# the C64 font build: the REU build with its own font (src/c64/font.p8)
PCCARGSC64FONT=$(PCCARGSC64REU)
PCCARGSCX16=-srcdirs src:src/cx16 -asmlist -target cx16 -out build
PCCARGSVIC20=-srcdirs src:src/vic20 -asmlist -target config/vic20plus24.properties -out build
PCCARGSVM=-srcdirs src:src/virtual -target virtual -out build

# p8vi.p8 is the full editor (c64), p8vi_cx16.p8 the X16's and
# p8vi_vic20.p8 the VIC-20's (each can leave out features); all import
# editor.p8.  The C64 has two builds: p8vi-c64
# with the gap buffer (the most room for text in main RAM) and p8vi-c64reu
# with the page store (for text in an REU, docs/XMEM-DESIGN.md)
PROGS	= build/p8vi-c64.prg build/p8vi-c64reu.prg build/p8vi-cx16.prg build/p8vi-vic20.prg
# an experiment, not in the release yet: p8vi-c64font (src/p8vi_c64font.p8)
# is p8vi-c64reu with a font that has the ASCII characters PETSCII lacks.
# it loads the font from p8vi.fnt (make font, from FONTSRC).
FONTPROG = build/p8vi-c64font.prg
FONTSRC	= custchar/src/c64oscharset.p8
SRCS	= src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/pagestore.p8 src/charset.p8 src/*/platform.p8 \
	  src/*/store_platform.p8 src/*/pagemem_platform.p8 src/*/xmem_platform.p8 src/c64/reu.p8

all: build $(PROGS) $(FONTPROG)

build:
	$(MD) build

build/p8vi-c64.prg: src/p8vi.p8 $(SRCS)
	$(PCC) $(PCCARGSC64) $<
	$(CP) build/p8vi.prg $@
	$(CP) build/p8vi.list build/p8vi-c64.list
	$(CP) build/p8vi.asm build/p8vi-c64.asm
	$(RM) build/p8vi.prg

build/p8vi-c64reu.prg: src/p8vi.p8 $(SRCS)
	$(PCC) $(PCCARGSC64REU) $<
	$(CP) build/p8vi.prg $@
	$(CP) build/p8vi.list build/p8vi-c64reu.list
	$(CP) build/p8vi.asm build/p8vi-c64reu.asm
	$(RM) build/p8vi.prg

build/p8vi-c64font.prg: src/p8vi_c64font.p8 $(SRCS) src/c64/font.p8
	$(PCC) $(PCCARGSC64FONT) $<
	$(CP) build/p8vi_c64font.prg $@
	$(CP) build/p8vi_c64font.list build/p8vi-c64font.list
	$(CP) build/p8vi_c64font.asm build/p8vi-c64font.asm
	$(RM) build/p8vi_c64font.prg

font:	build/p8vi.fnt

build/p8vi.fnt: $(FONTSRC) tools/mkfont.py
	python3 tools/mkfont.py $(FONTSRC) $@

build/p8vi-cx16.prg: src/p8vi_cx16.p8 $(SRCS)
	$(PCC) $(PCCARGSCX16) $<
	$(CP) build/p8vi_cx16.prg $@
	$(CP) build/p8vi_cx16.list build/p8vi-cx16.list
	$(CP) build/p8vi_cx16.asm build/p8vi-cx16.asm
	$(RM) build/p8vi_cx16.prg

build/p8vi-vic20.prg: src/p8vi_vic20.p8 $(SRCS)
	$(PCC) $(PCCARGSVIC20) $<
	$(CP) build/p8vi_vic20.prg $@
	$(CP) build/p8vi_vic20.list build/p8vi-vic20.list
	$(CP) build/p8vi_vic20.asm build/p8vi-vic20.asm
	$(RM) build/p8vi_vic20.prg

clean:
	$(RM) build$(SEP)*

# the programs and the quick start guide, copied to release/ (kept in git:
# the last known good version, whatever build/ holds).  the quick checks
# run first; run make test-c64, test-c64reu and test-c64-screen too before
# a release that matters.
release:	$(PROGS) test audit size
	$(MD) release
	$(CP) build$(SEP)p8vi-c64.prg release
	$(CP) build$(SEP)p8vi-c64reu.prg release
	$(CP) build$(SEP)p8vi-cx16.prg release
	$(CP) build$(SEP)p8vi-vic20.prg release
	$(CP) docs$(SEP)QUICKSTART.md release

disk:	build/p8vi-c64.prg build/p8vi-c64reu.prg build/p8vi-c64font.prg build/p8vi.fnt build/p8vi-vic20.prg
	c1541 -format $(DISKNAME),52 $(DISKTYPE) $(DISK)
	c1541 -attach $(DISK) -write build/p8vi-c64.prg p8vi,p
	c1541 -attach $(DISK) -write build/p8vi-c64reu.prg p8vi-reu,p
	c1541 -attach $(DISK) -write build/p8vi-c64font.prg p8vi-font,p
	c1541 -attach $(DISK) -write build/p8vi.fnt p8vi.fnt,p
	c1541 -attach $(DISK) -write build/p8vi-vic20.prg p8vi-vic20,p
	c1541 -attach $(DISK) -write samples/sampbig.txt sampbig.txt,s
	c1541 -attach $(DISK) -write samples/sampmax.txt sampmax.txt,s
	c1541 -attach $(DISK) -write samples/sampsmall.txt sampsmall.txt,s
	c1541 -attach $(DISK) -write samples/sample.txt sample.txt,s
	c1541 -attach $(DISK) -write src/c64/font.p8 font.p8,s

emu-c64:	build/p8vi-c64.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64.prg

emu-c64reu:	build/p8vi-c64reu.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64reu.prg

# the font build (p8vi.fnt is on the disk)
emu-c64font:	build/p8vi-c64font.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64font.prg

emu-cx16:	build/p8vi-cx16.prg
	x16emu -debug -scale 2 -rtc -fsroot samples/ -run -prg build/p8vi-cx16.prg

EMUVIC=xvic -default -keymap 1 -model ntsc -memory all -8 $(DISK) -drive8type 1581 -monitorfont "JetBrains Mono 16"
emu-vic20:	build/p8vi-vic20.prg disk
	$(EMUVIC) -autostartprgmode 1 build/p8vi-vic20.prg

# self checking text store tests (gap buffer and page store) on the
# virtual target
test-gap:	build
	$(PCC) -quiet $(PCCARGSVM) -emu src/gaptest.p8 | grep -v 'INFO\|WARN' | diff -u tests/expected/virtual_gaptest.txt -
	$(PCC) -quiet $(PCCARGSVM) -emu src/pagetest.p8 | grep -v 'INFO\|WARN' | diff -u tests/expected/virtual_pagetest.txt -

# memory map of each build and the room left below memtop
# (tools/listsize.py LIST for where the bytes go, A.list B.list to compare)
VIC20_MIN_FREE=64
size:	$(PROGS) $(FONTPROG)
	python3 tools/listsize.py build/p8vi-c64.list --map
	python3 tools/listsize.py build/p8vi-c64reu.list --map
	python3 tools/listsize.py build/p8vi-c64font.list --map --memtop 0xc800
	python3 tools/listsize.py build/p8vi-cx16.list --map
	python3 tools/listsize.py build/p8vi-vic20.list --map --min-free $(VIC20_MIN_FREE)

# editor tests on a C64 in VICE (x64sc and c1541 in the PATH)
test-c64:	build/p8vi-c64.prg
	python3 tests/vice/edtest.py files --prg build/p8vi-c64.prg

# the same tests on the C64 REU build (the page store), with an REU and
# without one (then it has 4 KB of text: not the big file suite)
test-c64reu:	build/p8vi-c64reu.prg
	python3 tests/vice/edtest.py files --prg build/p8vi-c64reu.prg --reu 512 --limit 3000000000
	python3 tests/vice/edtest.py files --prg build/p8vi-c64reu.prg --skip big
	python3 tests/vice/rectest.py --prg build/p8vi-c64reu.prg
	python3 tests/vice/edtest.py screen --prg build/p8vi-c64reu.prg --reu 512

# the font build: the REU build's tests, and its own (the font suite).
# it has its own keys for | (and } is shift + minus), its own PETSCII for
# ASCII files and p8vi.fnt on the disk, so g-cmds, ascii and read-dir
# don't apply
FONT_SKIP = --skip g-cmds --skip ascii --skip read-dir
test-c64font:	build/p8vi-c64font.prg build/p8vi.fnt
	python3 tests/vice/edtest.py files --prg build/p8vi-c64font.prg --font build/p8vi.fnt --reu 512 --limit 3000000000 $(FONT_SKIP)
	python3 tests/vice/edtest.py files --prg build/p8vi-c64font.prg --font build/p8vi.fnt --skip big $(FONT_SKIP)
	python3 tests/vice/rectest.py --prg build/p8vi-c64font.prg --font build/p8vi.fnt
	python3 tests/vice/edtest.py screen --prg build/p8vi-c64font.prg --font build/p8vi.fnt --reu 512

# partial redraws must leave the same screen as a full redraw
test-c64-screen:	build/p8vi-c64.prg
	python3 tests/vice/edtest.py screen --prg build/p8vi-c64.prg

# REU tests on a C64 in VICE: detection finds every size and leaves the
# REU's memory alone, and the REU keeps its memory over a reset
test-reu:	build
	$(PCC) -quiet $(PCCARGSC64) tests/reu/reudetect.p8
	$(PCC) -quiet $(PCCARGSC64) tests/reu/reureset.p8
	python3 tests/reu/reutest.py --build build

# look in the generated assembler for the silent miscompiles found so far
# (bugs/uword_array_eq_ubyte.p8, bugs/min_ubyte_expressions.p8)
audit:	$(PROGS) $(FONTPROG)
	python3 tools/asmaudit.py build/p8vi-c64.asm build/p8vi-c64reu.asm build/p8vi-c64font.asm build/p8vi-cx16.asm build/p8vi-vic20.asm

# the 6502 fastmem routines against plain Prog8, on a C64 in VICE
test-fastmem:	build
	$(PCC) -quiet -srcdirs src:src/c64 -target c64 -out build tests/fastmem/fastmemtest.p8
	cd build && x64sc -default -sounddev dummy -warp -debugcart -autostartprgmode 1 -autostart fastmemtest.prg -limitcycles 900000000 -exitscreenshot fastmemtest.png > fastmemtest.log 2>&1; grep -q 'DBGCART: exit(0)' fastmemtest.log && echo "fastmem: ok" || (echo "fastmem: FAIL, see build/fastmemtest.png"; false)

# timings of the text store routines on a C64 in VICE (page store and gap
# buffer), screenshots in build/bench-page.png and build/bench-gap.png
bench:	build
	$(PCC) -quiet -srcdirs src:src/c64reu:src/c64 -target c64 -out build tests/bench/storebench.p8
	cd build && x64sc -default -sounddev dummy -warp -debugcart -autostartprgmode 1 -autostart storebench.prg -limitcycles 900000000 -exitscreenshot bench-page.png >/dev/null 2>&1
	$(PCC) -quiet -srcdirs src:src/c64 -target c64 -out build tests/bench/storebench.p8
	cd build && x64sc -default -sounddev dummy -warp -debugcart -autostartprgmode 1 -autostart storebench.prg -limitcycles 900000000 -exitscreenshot bench-gap.png >/dev/null 2>&1

# the text store tests on the virtual target (output compared with
# tests/expected/)
test:	test-gap

#
# end-of-file
#
