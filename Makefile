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
    RM = rm -fr
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
EMU_DOS=-dos1541 jiffy1541II -dos1541II jiffy1541II -dos1571 jiffy1571 -dos1581 jiffy1581
EMU_KERNAL=-kernal jiffykernal
EMU_REUSIZE=512
EMU_REU=-reu -reusize $(EMU_REUSIZE)
EMU=$(EMU_CMD) $(EMU_BASE) $(EMU_KERNAL) $(EMU_DISK) $(EMU_DOS) $(EMU_REU)

PCC=prog8c-llvm
PCCARGSC64=-srcdirs src:src/c64 -asmlist -target c64 -out build
# the C64 REU build: src/c64reu (its store_platform) comes before src/c64
PCCARGSC64REU=-srcdirs src:src/c64reu:src/c64 -asmlist -target c64 -out build
# the C64 disk build: the page store with its pages in SEQ files on the disk
PCCARGSC64DISK=-srcdirs src:src/diskpage:src/c64 -asmlist -target c64 -out build
# the C64 font build: the REU build with its own font (src/c64/font.p8)
PCCARGSC64FONT=$(PCCARGSC64REU)
PCCARGSCX16=-srcdirs src:src/cx16 -asmlist -target cx16 -out build
PCCARGSM65=-srcdirs src:src/mega65 -asmlist -target config/mega65.properties -out build
# the MEGA65 page store build: text in chip RAM banks 4 and 5 through DMA
PCCARGSM65DMA=-srcdirs src:src/mega65dma:src/mega65 -asmlist -target config/mega65.properties -out build
PCCARGSPLUS4=-srcdirs src:src/plus4 -asmlist -target config/plus4.properties -out build
# the C128 in its own mode, on the VIC-II or the VDC (src/c128/textio.p8)
PCCARGSC128=-srcdirs src:src/c128 -asmlist -target c128 -out build
# the C128 bank 1 build: src/c128bank1 (the page store, its pages in RAM
# bank 1) before src/c128
PCCARGSC128X=-srcdirs src:src/c128bank1:src/c128font:src/c128 -asmlist -target c128 -out build
# the C128 REU build: src/c128reu (the page store in an REU, or bank 1),
# then src/c128, and src/c64 for its reu.p8
PCCARGSC128REU=-srcdirs src:src/c128reu:src/c128:src/c64 -asmlist -target c128 -out build
PCCARGSPET32=-srcdirs src:src/pet32 -asmlist -target pet32 -out build
PCCARGSVIC20=-srcdirs src:src/vic20 -asmlist -target config/vic20plus24.properties -out build
PCCARGSVM=-srcdirs src:src/virtual -target virtual -out build

# p8vi.p8 is the full editor (c64), p8vi_cx16.p8 the X16's and
# p8vi_vic20.p8 the VIC-20's (each can leave out features); all import
# editor.p8.  The C64 has two builds: p8vi-c64
# with the gap buffer (the most room for text in main RAM) and p8vi-c64reu
# with the page store (for text in an REU, docs/XMEM-DESIGN.md)
PROGS	= build/p8vi-c64.prg build/p8vi-c64reu.prg build/p8vi-c64disk.prg build/p8vi-cx16.prg build/p8vi-mega65.prg build/p8vi-mega65dma.prg build/p8vi-pet32.prg build/p8vi-plus4.prg build/p8vi-c128.prg build/p8vi-c128x.prg build/p8vi-c128reu.prg build/p8vi-vic20.prg
# an experiment, not in the release yet: p8vi-c64font (src/p8vi_c64font.p8)
# is p8vi-c64reu with a font that has the ASCII characters PETSCII lacks.
# it loads the font from p8vi.fnt (make font, from FONTSRC).
FONTPROG = build/p8vi-c64font.prg
FONTSRC	= src/c64/c64oscharset.p8
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

# the C64 disk build: the full editor with the page store, its pages in
# SEQ files (p8vi.swp...) on the drive (src/diskpage), for IDE64, RAMLink,
# CMD HD and the like
build/p8vi-c64disk.prg: src/p8vi.p8 $(SRCS) src/diskpage/*.p8
	$(PCC) $(PCCARGSC64DISK) $<
	$(CP) build/p8vi.prg $@
	$(CP) build/p8vi.list build/p8vi-c64disk.list
	$(CP) build/p8vi.asm build/p8vi-c64disk.asm
	$(RM) build/p8vi.prg

build/p8vi-c64font.prg: src/p8vi_c64font.p8 $(SRCS) src/c64/font.p8 font
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

# the MEGA65 builds have the font build's character set (the font follows
# the text: ASCII or PETSCII).  p8vi-mega65 (src/p8vi_mega65.p8): the gap
# buffer, all features
build/p8vi-mega65.prg: src/p8vi_mega65.p8 $(SRCS) src/mega65/*.p8 config/mega65.properties $(wildcard libraries/mega65/*.p8)
	$(PCC) $(PCCARGSM65) $<
	$(CP) build/p8vi_mega65.prg $@
	$(CP) build/p8vi_mega65.list build/p8vi-mega65.list
	$(CP) build/p8vi_mega65.asm build/p8vi-mega65.asm
	$(RM) build/p8vi_mega65.prg

# p8vi-mega65dma (src/p8vi_mega65dma.p8, src/mega65dma): the page store,
# the text in attic RAM, or chip RAM banks 4 and 5 without it, copied in
# and out with DMA.  the program has to end below $c000, so some features
# are off
build/p8vi-mega65dma.prg: src/p8vi_mega65dma.p8 $(SRCS) src/mega65/*.p8 src/mega65dma/*.p8 config/mega65.properties $(wildcard libraries/mega65/*.p8)
	$(PCC) $(PCCARGSM65DMA) $<
	$(CP) build/p8vi_mega65dma.prg $@
	$(CP) build/p8vi_mega65dma.list build/p8vi-mega65dma.list
	$(CP) build/p8vi_mega65dma.asm build/p8vi-mega65dma.asm
	$(RM) build/p8vi_mega65dma.prg

# the Plus/4 (src/p8vi_plus4.p8, src/plus4): the full editor and the gap
# buffer, running with the RAM in up to $fc00 (src/plus4/rammode.p8)
build/p8vi-plus4.prg: src/p8vi_plus4.p8 $(SRCS) src/plus4/*.p8 config/plus4.properties $(wildcard libraries/plus4/*.p8)
	$(PCC) $(PCCARGSPLUS4) $<
	$(CP) build/p8vi_plus4.prg $@
	$(CP) build/p8vi_plus4.list build/p8vi-plus4.list
	$(CP) build/p8vi_plus4.asm build/p8vi-plus4.asm
	$(RM) build/p8vi_plus4.prg

# the C128 (native mode, not GO64, src/p8vi_c128.p8): the full editor and
# the gap buffer, on the 40 column or the 80 column screen, whichever is
# active when it starts.  (needs prog8c-llvm ab65226d8 or later: the c128
# startup, bugs/c128_startup_under_basic_rom.p8)
build/p8vi-c128.prg: src/p8vi_c128.p8 $(SRCS) src/c128/*.p8
	$(PCC) $(PCCARGSC128) $<
	$(CP) build/p8vi_c128.prg $@
	$(CP) build/p8vi_c128.list build/p8vi-c128.list
	$(CP) build/p8vi_c128.asm build/p8vi-c128.asm
	$(RM) build/p8vi_c128.prg

# the C128 bank 1 build (src/p8vi_c128x.p8): the page store with its pages
# in RAM bank 1, text up to about 60 KB; without the start screen and :@$.
# also a font build: it shows p8vi.fnt if it is on the disk (src/c128font/font.p8)
build/p8vi-c128x.prg: src/p8vi_c128x.p8 $(SRCS) src/c128/*.p8 src/c128bank1/*.p8 src/c128font/*.p8
	$(PCC) $(PCCARGSC128X) $<
	$(CP) build/p8vi_c128x.prg $@
	$(CP) build/p8vi_c128x.list build/p8vi-c128x.list
	$(CP) build/p8vi_c128x.asm build/p8vi-c128x.asm
	$(RM) build/p8vi_c128x.prg

# the C128 REU build (src/p8vi_c128reu.p8): the page store with its pages
# in an REU (192 KB for the text, yank and undo), or in RAM bank 1 without one; without
# the start screen, :@$ and the one row scrolling
build/p8vi-c128reu.prg: src/p8vi_c128reu.p8 $(SRCS) src/c128/*.p8 src/c128reu/*.p8 src/c64/reu.p8
	$(PCC) $(PCCARGSC128REU) $<
	$(CP) build/p8vi_c128reu.prg $@
	$(CP) build/p8vi_c128reu.list build/p8vi-c128reu.list
	$(CP) build/p8vi_c128reu.asm build/p8vi-c128reu.asm
	$(RM) build/p8vi_c128reu.prg

# the PET (a 32 KB PET with BASIC 4, Prog8's pet32 target): the gap buffer,
# with the VIC-20's features and no ASCII or CR LF files, for room for text
build/p8vi-pet32.prg: src/p8vi_pet32.p8 $(SRCS) src/pet32/*.p8
	$(PCC) $(PCCARGSPET32) $<
	$(CP) build/p8vi_pet32.prg $@
	$(CP) build/p8vi_pet32.list build/p8vi-pet32.list
	$(CP) build/p8vi_pet32.asm build/p8vi-pet32.asm
	$(RM) build/p8vi_pet32.prg

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
release:	$(PROGS) font test audit size
	$(MD) release
	$(CP) build$(SEP)p8vi-c64.prg release
	$(CP) build$(SEP)p8vi-c64font.prg release
	$(CP) build$(SEP)p8vi.fnt release
	$(CP) build$(SEP)p8vi-c64reu.prg release
	$(CP) build$(SEP)p8vi-cx16.prg release
	$(CP) build$(SEP)p8vi-mega65.prg release
	$(CP) build$(SEP)p8vi-mega65dma.prg release
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

emu-mega65:	build/p8vi-mega65.prg
	xmega65 -prg build/p8vi-mega65.prg

emu-mega65dma:	build/p8vi-mega65dma.prg
	xmega65 -prg build/p8vi-mega65dma.prg

# which zero page bytes the MEGA65 ROM changes in KERNAL calls (for the
# zp_* lists in config/mega65.properties), in xmega65 headless.  the
# program is also on the disk as zpload, for its LOAD test.
ZPDISK=build/zpwatch.d81
test-mega65-zp:	build
	$(PCC) -target config/mega65.properties -srcdirs tests/mega65 -out build tests/mega65/zpwatch.p8
	c1541 -format zpwatch,01 d81 $(ZPDISK)
	c1541 -attach $(ZPDISK) -write build/zpwatch.prg zpload,p
	xmega65 -headless -sleepless -besure -prg build/zpwatch.prg -prgexit \
		-8 $(abspath $(ZPDISK)) -dumpscreen build/zpwatch.txt
	cat build/zpwatch.txt

# editor tests on a MEGA65 in xmega65 (and c1541), driven through its
# serial monitor by tools/m65harness.py: the suites of tests/vice/edtest.py
# and the font suite.  left out, as for the C64 font build: g-cmds and
# ascii (they type and keep PETSCII graphics in ways the font build maps
# to the ASCII characters)
FONT_SKIP_M65 = --skip g-cmds --skip ascii
test-mega65:	build/p8vi-mega65.prg
	python3 -B tests/mega65/edtest.py --font $(FONT_SKIP_M65) files
	python3 -B tests/mega65/edtest.py screen

# the same on the MEGA65 page store build, with the suites for more text
# than main RAM holds (--paged) and the font suite: the pages in attic RAM
# (xemu has it).  left out: subst and read-dir (SUBST and DIR are off in
# this build), and g-cmds and ascii as above.  then some of them as on a
# Nexys4 board (model ID $40), without attic RAM: the pages in banks 4 and
# 5 (not bigundo: 30 KB of text, undo and yank need more than their 126
# pages; it fails the same way on a C64 with a 128 KB REU)
test-mega65dma:	build/p8vi-mega65dma.prg
	python3 -B tests/mega65/edtest.py --prg build/p8vi-mega65dma.prg --paged --font \
		--skip subst --skip read-dir $(FONT_SKIP_M65) files
	python3 -B tests/mega65/edtest.py --prg build/p8vi-mega65dma.prg --paged --model 64 \
		files delete-put undo pages huge
	python3 -B tests/mega65/edtest.py --prg build/p8vi-mega65dma.prg screen

# which keys give which PETSCII codes (the table in tools/m65harness.py)
test-mega65-keymap:	build
	$(PCC) -target config/mega65.properties -srcdirs tests/mega65 -out build tests/mega65/keyecho.p8
	python3 -B tests/mega65/keymap.py --prg build/keyecho.prg

# the PET: a 4032 with an IEEE-488 2031 drive (it takes .d64 images); its
# own disk, with files small enough for its 3.3 KB of text
PETDISK=build/testpet.d64
emu-pet32:	build/p8vi-pet32.prg
	c1541 -format testpet,52 d64 $(PETDISK)
	c1541 -attach $(PETDISK) -write build/p8vi-pet32.prg p8vi,p
	c1541 -attach $(PETDISK) -write src/c64/font.p8 font.p8,s
	c1541 -attach $(PETDISK) -write README.md readme.md,s
	xpet -default -model 4032 -drive8type 2031 -8 $(PETDISK) -autostart $(PETDISK)

# the Plus/4 with the test disk's samples (a 1541 .d64 of its own: the
# test disk is a 1581, which the Plus/4 can also use, but this keeps it simple)
P4DISK=build/testplus4.d64
emu-plus4:	build/p8vi-plus4.prg
	c1541 -format testplus4,52 d64 $(P4DISK)
	c1541 -attach $(P4DISK) -write build/p8vi-plus4.prg p8vi,p
	c1541 -attach $(P4DISK) -write samples/sample.txt sample.txt,s
	c1541 -attach $(P4DISK) -write samples/sampmax.txt sampmax.txt,s
	c1541 -attach $(P4DISK) -write src/c64/font.p8 font.p8,s
	xplus4 -default -drive8type 1541 -8 $(P4DISK) -autostart $(P4DISK)

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
	python3 tools/listsize.py build/p8vi-c64disk.list --map
	python3 tools/listsize.py build/p8vi-c64font.list --map --memtop 0xc800
	python3 tools/listsize.py build/p8vi-cx16.list --map
	python3 tools/listsize.py build/p8vi-mega65.list --map --memtop 0xc000
	python3 tools/listsize.py build/p8vi-mega65dma.list --map --memtop 0xc000
	python3 tools/listsize.py build/p8vi-pet32.list --map --memtop 0x8000
	python3 tools/listsize.py build/p8vi-c128.list --map --memtop 0xc000
	python3 tools/listsize.py build/p8vi-c128x.list --map --memtop 0xc000
	python3 tools/listsize.py build/p8vi-c128reu.list --map --memtop 0xc000
	python3 tools/listsize.py build/p8vi-plus4.list --map --memtop 0xfc00
	python3 tools/listsize.py build/p8vi-vic20.list --map --min-free $(VIC20_MIN_FREE)

# editor tests on a C64 in VICE (x64sc and c1541 in the PATH)
test-c64:	build/p8vi-c64.prg
	python3 tests/vice/edtest.py files --prg build/p8vi-c64.prg

# the same tests on the Plus/4 (VICE's xplus4 with a 1541)
test-plus4:	build/p8vi-plus4.prg
	python3 -B tests/vice/edtest.py files --machine plus4 -j 4 --prg build/p8vi-plus4.prg
	python3 -B tests/vice/edtest.py screen --machine plus4 -j 4 --prg build/p8vi-plus4.prg

# the same tests on the C128 (VICE's x128, a 1541), on the 40 column and
# the 80 column (VDC) screen
test-c128:	build/p8vi-c128.prg
	python3 -B tests/vice/edtest.py files --machine c128 -j 4 --prg build/p8vi-c128.prg
	python3 -B tests/vice/edtest.py screen --machine c128 -j 4 --prg build/p8vi-c128.prg
	python3 -B tests/vice/edtest.py files --machine c128-80 -j 4 --prg build/p8vi-c128.prg
	python3 -B tests/vice/edtest.py screen --machine c128-80 -j 4 --prg build/p8vi-c128.prg

# the C128 bank 1 build: also the page store's suites (--paged), except
# read-dir (no :@$ in this build) and the two that need more than bank 1
# holds (huge: about 87 KB of text; bigundo: 29 KB and its undo)
C128X_SKIP = --skip read-dir --skip huge --skip bigundo
# p8vi-c128x is also a font build (p8vi.fnt on its disks, and the font
# suite): it leaves out g-cmds and ascii as the C64 font build does
C128X_FONT = --font build/p8vi.fnt --skip g-cmds --skip ascii
test-c128x:	build/p8vi-c128x.prg build/p8vi.fnt
	python3 -B tests/vice/edtest.py files --machine c128 --paged --limit 3000000000 -j 4 $(C128X_SKIP) $(C128X_FONT) --prg build/p8vi-c128x.prg
	python3 -B tests/vice/edtest.py screen --machine c128 -j 4 --font build/p8vi.fnt --prg build/p8vi-c128x.prg
	python3 -B tests/vice/edtest.py files --machine c128-80 --paged --limit 3000000000 -j 4 $(C128X_SKIP) $(C128X_FONT) --prg build/p8vi-c128x.prg
	python3 -B tests/vice/edtest.py screen --machine c128-80 -j 4 --font build/p8vi.fnt --prg build/p8vi-c128x.prg
	python3 -B tests/vice/rectest.py --machine c128 --no-reu --font build/p8vi.fnt --prg build/p8vi-c128x.prg

# the C128 REU build: with a 512 KB REU (all the page store's suites), and
# without one (bank 1, as test-c128x); read-dir: no :@$ in this build
test-c128reu:	build/p8vi-c128reu.prg
	python3 -B tests/vice/edtest.py files --machine c128 --reu 512 --limit 3000000000 -j 4 --skip read-dir --prg build/p8vi-c128reu.prg
	python3 -B tests/vice/edtest.py screen --machine c128 --reu 512 -j 4 --prg build/p8vi-c128reu.prg
	python3 -B tests/vice/edtest.py files --machine c128-80 --reu 512 --limit 3000000000 -j 4 --skip read-dir --prg build/p8vi-c128reu.prg
	python3 -B tests/vice/edtest.py screen --machine c128-80 --reu 512 -j 4 --prg build/p8vi-c128reu.prg
	python3 -B tests/vice/edtest.py files --machine c128 --paged --limit 3000000000 -j 4 $(C128X_SKIP) --prg build/p8vi-c128reu.prg
	python3 -B tests/vice/rectest.py --machine c128 --prg build/p8vi-c128reu.prg
	python3 -B tests/vice/rectest.py --machine c128-80 --no-reu --prg build/p8vi-c128reu.prg

# the same tests on the PET (VICE's xpet, a 4032 with a 2031 drive).  left
# out, for the features it doesn't have: ascii, crlf, big, final-eol,
# read-format, find (ASCII and CR LF files), subst, dos, read-dir
PET_SKIP = --skip ascii --skip crlf --skip big --skip final-eol --skip read-format --skip find \
	--skip subst --skip dos --skip read-dir
test-pet32:	build/p8vi-pet32.prg
	python3 -B tests/vice/edtest.py files --machine pet -j 4 --prg build/p8vi-pet32.prg $(PET_SKIP)
	python3 -B tests/vice/edtest.py screen --machine pet -j 4 --prg build/p8vi-pet32.prg

# the same tests on the C64 disk build (pages in SEQ files on the 1541),
# with the REU suites' 6 KB text (--paged).  huge and bigundo are left
# out: their 30-64 KB of text and its pages don't fit on a 1541 disk
# beside the program
test-c64disk:	build/p8vi-c64disk.prg
	python3 -B tests/vice/edtest.py files --prg build/p8vi-c64disk.prg --paged --limit 3000000000 \
		--skip huge --skip bigundo
	python3 -B tests/vice/edtest.py screen --prg build/p8vi-c64disk.prg

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

# the same C64 tests with JiffyDOS (VICE's jiffykernal and jiffy1541II
# ROMs, in its ROM directories, as EMU_KERNAL and EMU_DOS above), to
# compare with the ones above
JIFFY = --jiffydos
test-c64-jiffydos:	build/p8vi-c64.prg
	python3 -B tests/vice/edtest.py files $(JIFFY) --prg build/p8vi-c64.prg

test-c64-screen-jiffydos:	build/p8vi-c64.prg
	python3 -B tests/vice/edtest.py screen $(JIFFY) --prg build/p8vi-c64.prg

test-c64reu-jiffydos:	build/p8vi-c64reu.prg
	python3 -B tests/vice/edtest.py files $(JIFFY) --prg build/p8vi-c64reu.prg --reu 512 --limit 3000000000
	python3 -B tests/vice/edtest.py files $(JIFFY) --prg build/p8vi-c64reu.prg --skip big
	python3 -B tests/vice/rectest.py $(JIFFY) --prg build/p8vi-c64reu.prg
	python3 -B tests/vice/edtest.py screen $(JIFFY) --prg build/p8vi-c64reu.prg --reu 512

test-c64font-jiffydos:	build/p8vi-c64font.prg build/p8vi.fnt
	python3 -B tests/vice/edtest.py files $(JIFFY) --prg build/p8vi-c64font.prg --font build/p8vi.fnt --reu 512 --limit 3000000000 $(FONT_SKIP)
	python3 -B tests/vice/edtest.py files $(JIFFY) --prg build/p8vi-c64font.prg --font build/p8vi.fnt --skip big $(FONT_SKIP)
	python3 -B tests/vice/rectest.py $(JIFFY) --prg build/p8vi-c64font.prg --font build/p8vi.fnt
	python3 -B tests/vice/edtest.py screen $(JIFFY) --prg build/p8vi-c64font.prg --font build/p8vi.fnt --reu 512

test-c64disk-jiffydos:	build/p8vi-c64disk.prg
	python3 -B tests/vice/edtest.py files $(JIFFY) --prg build/p8vi-c64disk.prg --paged --limit 3000000000 \
		--skip huge --skip bigundo
	python3 -B tests/vice/edtest.py screen $(JIFFY) --prg build/p8vi-c64disk.prg

# all the C64 tests with JiffyDOS
test-jiffydos:	test-c64-jiffydos test-c64-screen-jiffydos test-c64reu-jiffydos test-c64font-jiffydos test-c64disk-jiffydos

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
