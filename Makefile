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

# disk image settings
DISKTYPE=d64
DISKNAME=testgap
DISK=build/$(DISKNAME).$(DISKTYPE)

# Emulator settings
EMU_CMD=x64sc
EMU_BASE=-default -keymap 1 -model ntsc
EMU_DISK08=-8 $(DISK) -drive8type 1542
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
PCCARGSCX16=-srcdirs src:src/cx16 -asmlist -target cx16 -out build
PCCARGSVIC20=-srcdirs src:src/vic20 -asmlist -target config/vic20plus24.properties -out build
PCCARGSVM=-srcdirs src:src/virtual -target virtual -out build

# p8vi.p8 is the full editor (c64), p8vi_cx16.p8 the X16's and
# p8vi_vic20.p8 the VIC-20's (each can leave out features); all import
# editor.p8.  The C64 has two builds: p8vi-c64
# with the gap buffer (the most room for text in main RAM) and p8vi-c64reu
# with the page store (for text in an REU, docs/XMEM-DESIGN.md)
PROGS	= build/p8vi-c64.prg build/p8vi-c64reu.prg build/p8vi-cx16.prg build/p8vi-vic20.prg
SRCS	= src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/pagestore.p8 src/charset.p8 src/*/platform.p8 \
	  src/*/store_platform.p8 src/*/pagemem_platform.p8 src/*/xmem_platform.p8 src/c64/reu.p8

all: build $(PROGS)

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

build/testcx16.prg: src/test.p8 src/buffer.p8 src/gapbuffer.p8
	$(PCC) $(PCCARGSCX16) $<
	$(CP) build/test.prg $@
	$(RM) build/test.prg

clean:
	$(RM) build$(SEP)*

disk:	build/p8vi-c64.prg build/p8vi-c64reu.prg
	c1541 -format $(DISKNAME),52 $(DISKTYPE) $(DISK)
	c1541 -attach $(DISK) -write build/p8vi-c64.prg p8vi,p
	c1541 -attach $(DISK) -write build/p8vi-c64reu.prg p8vi-reu,p
	c1541 -attach $(DISK) -write samples/sampbig.txt sampbig.txt,s
	c1541 -attach $(DISK) -write samples/sampmax.txt sampmax.txt,s
	c1541 -attach $(DISK) -write samples/sampsmall.txt sampsmall.txt,s
	c1541 -attach $(DISK) -write samples/sample.txt sample.txt,s

emu-c64:	build/p8vi-c64.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64.prg

emu-c64reu:	build/p8vi-c64reu.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64reu.prg

emu-cx16:	build/p8vi-cx16.prg
	x16emu -debug -scale 2 -rtc -fsroot samples/ -run -prg build/p8vi-cx16.prg

EMUVIC=xvic -default -keymap 1 -model ntsc -memory all -8 build/testgap.d64 -drive8type 1542 -monitorfont "JetBrains Mono 16"
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
size:	$(PROGS)
	python3 tools/listsize.py build/p8vi-c64.list --map
	python3 tools/listsize.py build/p8vi-c64reu.list --map
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
audit:	$(PROGS)
	python3 tools/asmaudit.py build/p8vi-c64.asm build/p8vi-c64reu.asm build/p8vi-cx16.asm build/p8vi-vic20.asm

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

test:	build/testcx16.prg
	x16emu -gif output.gif -debug -scale 2 -rtc -run -prg build/testcx16.prg

#
# end-of-file
#
