#
# Simple Makefile for a Prog8 program.
#

# Cross-platform commands
# (PS: the separator of prog8c's -srcdirs list, ; on Windows; the Python
# command: python on Windows, python3 elsewhere, make PYTHON=py for the
# Windows launcher.  Windows' copy, del and mkdir take the / in a path for
# an option, so there tools/fileop.py does their work)
ifeq ($(OS),Windows_NT)
    CP = $(PYTHON) $(FILEOP) cp
    RM = $(PYTHON) $(FILEOP) rm
    MD = $(PYTHON) $(FILEOP) mkdir
    PS = ;
    PYTHON ?= python
else
    CP = cp -p
    RM = rm -fr
    MD = mkdir -p
    PS = :
    PYTHON ?= python3
endif

# the Python scripts the recipes run: their paths are here, not in the
# commands (forward slashes: Python takes them on Windows too)
EDTEST = tests/vice/edtest.py
RECTEST = tests/vice/rectest.py
CPMTEST = tests/cpm/cpmtest.py
M4TEST = tests/cpm/m4test.py
M65TEST = tests/mega65/edtest.py
M65KEYMAP = tests/mega65/keymap.py
TRSTEST = tests/trs80/trstest.py
TRSRECTEST = tests/trs80/rectest.py
REUTEST = tests/reu/reutest.py
QUICKTEST = tests/quick.py
AMIGATEST = tests/amiga/amigatest.py
LISTSIZE = tools/listsize.py
ASMAUDIT = tools/asmaudit.py
MKFONT = tools/mkfont.py
M4DISK = tools/cpm/m4disk.py
ENCODE_COPY = tools/encode_copy.py
FILEOP = tools/fileop.py

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
PCCARGSC64=-srcdirs "src$(PS)src/c64" -asmlist -target c64 -out build
# the C64 REU build: src/c64reu (its store_platform) comes before src/c64
PCCARGSC64REU=-srcdirs "src$(PS)src/c64reu$(PS)src/c64" -asmlist -target c64 -out build
# the C64 disk build: the page store with its pages in SEQ files on the disk
PCCARGSC64DISK=-srcdirs "src$(PS)src/diskpage$(PS)src/c64" -asmlist -target c64 -out build
# the C64 font build: the REU build with its own font (src/c64/font.p8)
PCCARGSC64FONT=$(PCCARGSC64REU)
PCCARGSCX16=-srcdirs "src$(PS)src/cx16" -asmlist -target cx16 -out build
# the X16's ISO mode build: every module of the program compiled with
# %encoding iso, from copies tools/encode_copy.py makes in build/cx16iso
# (the library keeps PETSCII; bugs/encoding_option.md)
CX16ISO=build/cx16iso
CX16ISO_DIRS=src src/cx16
PCCARGSCX16ISO=-srcdirs "$(CX16ISO)/src$(PS)$(CX16ISO)/cx16" -asmlist -target cx16 -out build
PCCARGSM65=-srcdirs "src$(PS)src/mega65" -asmlist -target config/mega65.properties -out build
# the MEGA65 page store build: text in chip RAM banks 4 and 5 through DMA
PCCARGSM65DMA=-srcdirs "src$(PS)src/mega65dma$(PS)src/mega65" -asmlist -target config/mega65.properties -out build
PCCARGSPLUS4=-srcdirs "src$(PS)src/plus4" -asmlist -target config/plus4.properties -out build
# the C128 in its own mode, on the VIC-II or the VDC (src/c128/textio.p8)
PCCARGSC128=-srcdirs "src$(PS)src/c128" -asmlist -target c128 -out build
# the C128 bank 1 build: src/c128bank1 (the page store, its pages in RAM
# bank 1) before src/c128
PCCARGSC128X=-srcdirs "src$(PS)src/c128bank1$(PS)src/c128font$(PS)src/c128" -asmlist -target c128 -out build
# the C128 REU build: src/c128reu (the page store in an REU, or bank 1),
# then src/c128, and src/c64 for its reu.p8
PCCARGSC128REU=-srcdirs "src$(PS)src/c128reu$(PS)src/c128$(PS)src/c64" -asmlist -target c128 -out build
PCCARGSPET32=-srcdirs "src$(PS)src/pet32" -asmlist -target pet32 -out build
PCCARGSVIC20=-srcdirs "src$(PS)src/vic20" -asmlist -target config/vic20plus24.properties -out build
PCCARGSVM=-srcdirs "src$(PS)src/virtual" -target virtual -out build

# p8vi.p8 is the full editor (c64), p8vi_cx16.p8 the X16's and
# p8vi_vic20.p8 the VIC-20's (each can leave out features); all import
# editor.p8.  The C64 has two builds: p8vi-c64
# with the gap buffer (the most room for text in main RAM) and p8vi-c64reu
# (p8vi_c64reu.p8, p8vi.p8 with fewer features) with the page store (for
# text in an REU, docs/XMEM-DESIGN.md)
PROGS	= build/p8vi-c64.prg build/p8vi-c64reu.prg build/p8vi-c64disk.prg build/p8vi-cx16.prg build/p8vi-cx16iso.prg build/p8vi-mega65.prg build/p8vi-mega65dma.prg build/p8vi-pet32.prg build/p8vi-plus4.prg build/p8vi-c128.prg build/p8vi-c128x.prg build/p8vi-c128reu.prg build/p8vi-vic20.prg
# an experiment, not in the release yet: p8vi-c64font (src/p8vi_c64font.p8)
# is p8vi-c64reu with a font that has the ASCII characters PETSCII lacks.
# it loads the font from oscii.fnt (make font, from FONTSRC).
FONTPROG = build/p8vi-c64font.prg
FONTSRC	= src/c64/oscii.p8
SRCS	= src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/pagestore.p8 src/charset.p8 src/cbmkernal.p8 src/*/platform.p8 \
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

build/p8vi-c64reu.prg: src/p8vi_c64reu.p8 $(SRCS)
	$(PCC) $(PCCARGSC64REU) $<
	$(CP) build/p8vi_c64reu.prg $@
	$(CP) build/p8vi_c64reu.list build/p8vi-c64reu.list
	$(CP) build/p8vi_c64reu.asm build/p8vi-c64reu.asm
	$(RM) build/p8vi_c64reu.prg

# the C64 disk build: the full editor with the page store, its pages in
# SEQ files (p8vi.swp...) on the drive (src/diskpage), for IDE64, RAMLink,
# CMD HD and the like
build/p8vi-c64disk.prg: src/p8vi.p8 $(SRCS) src/diskpage/*.p8
	$(PCC) $(PCCARGSC64DISK) $<
	$(CP) build/p8vi.prg $@
	$(CP) build/p8vi.list build/p8vi-c64disk.list
	$(CP) build/p8vi.asm build/p8vi-c64disk.asm
	$(RM) build/p8vi.prg

build/p8vi-c64font.prg: src/p8vi_c64font.p8 $(SRCS) src/c64/font.p8 build/oscii.fnt
	$(PCC) $(PCCARGSC64FONT) $<
	$(CP) build/p8vi_c64font.prg $@
	$(CP) build/p8vi_c64font.list build/p8vi-c64font.list
	$(CP) build/p8vi_c64font.asm build/p8vi-c64font.asm
	$(RM) build/p8vi_c64font.prg

font:	build/oscii.fnt

build/oscii.fnt: $(FONTSRC) $(MKFONT)
	$(PYTHON) $(MKFONT) $(FONTSRC) $@

build/p8vi-cx16.prg: src/p8vi_cx16.p8 $(SRCS)
	$(PCC) $(PCCARGSCX16) $<
	$(CP) build/p8vi_cx16.prg $@
	$(CP) build/p8vi_cx16.list build/p8vi-cx16.list
	$(CP) build/p8vi_cx16.asm build/p8vi-cx16.asm
	$(RM) build/p8vi_cx16.prg

build/p8vi-cx16iso.prg: src/p8vi_cx16iso.p8 $(SRCS) $(ENCODE_COPY)
	$(PYTHON) $(ENCODE_COPY) --encoding iso $(CX16ISO) $(CX16ISO_DIRS)
	$(PCC) $(PCCARGSCX16ISO) $(CX16ISO)/src/p8vi_cx16iso.p8
	$(CP) build/p8vi_cx16iso.prg $@
	$(CP) build/p8vi_cx16iso.list build/p8vi-cx16iso.list
	$(CP) build/p8vi_cx16iso.asm build/p8vi-cx16iso.asm
	$(RM) build/p8vi_cx16iso.prg

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
# also a font build: it shows oscii.fnt if it is on the disk (src/c128font/font.p8)
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

# the TRS-80 Model III with LDOS: a .cmd program, through prog8c's llvm16
# target and the z80-trs80-cmd profile, which need llvm-z80 and z88dk (not
# in "all").  The source is src/p8vi_trs80.p8 with src/trs80.
LLVM_Z80 ?= $(HOME)/.local/llvm-z80
Z88DK ?= $(HOME)/.local/z88dk
export LLVM_Z80 Z88DK
PCCARGSTRS80=-srcdirs "src$(PS)src/trs80" -target llvm16 -triple z80-trs80-cmd
trs80: build/p8vi-trs80.cmd
build/p8vi-trs80.cmd: src/p8vi_trs80.p8 src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSTRS80) -o build/p8vi-trs80 $<
# the test build: it plays the keys in KEYS/TXT first (features.KEYFILE)
# the file tests on the TRS-80 (trs80gp, a window per suite; see
# tests/trs80/trstest.py): the suites for CBM things are left out
test-trs80:	build/p8vi-trs80test.cmd
	$(PYTHON) -B $(TRSTEST) -j 3
trs80-test: build/p8vi-trs80test.cmd
build/p8vi-trs80test.cmd: src/p8vi_trs80test.p8 src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSTRS80) -o build/p8vi-trs80test $<

# the TRS-80 Model 4 in its own mode (TRSDOS 6, LS-DOS 6.3; 80 x 24): the
# z80-trs80-m4 profile.  The source is src/p8vi_trs80m4.p8 with
# src/trs80m4, and src/trs80 for the files the two share.
PCCARGSTRS80M4=-srcdirs "src$(PS)src/trs80m4$(PS)src/trs80" -target llvm16 -triple z80-trs80-m4
trs80m4: build/p8vi-trs80m4.cmd
build/p8vi-trs80m4.cmd: src/p8vi_trs80m4.p8 src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/trs80m4/*.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSTRS80M4) -o build/p8vi-trs80m4 $<
# the file tests, as test-trs80 (LS-DOS 6.3 here), marks and zview too
test-trs80m4:	build/p8vi-trs80m4test.cmd
	$(PYTHON) -B $(TRSTEST) --model 4 -j 3
# the test build: it plays the keys in KEYS/TXT first (features.KEYFILE)
trs80m4-test: build/p8vi-trs80m4test.cmd
build/p8vi-trs80m4test.cmd: src/p8vi_trs80m4test.p8 src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/trs80m4/*.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSTRS80M4) -o build/p8vi-trs80m4test $<

# the Model 4 with 128 KB: the text in the second 64 KB (src/trs80m4x, the
# page store), up to about 62 KB
PCCARGSTRS80M4X=-srcdirs "src$(PS)src/trs80m4x$(PS)src/trs80m4$(PS)src/trs80" -target llvm16 -triple z80-trs80-m4
trs80m4x: build/p8vi-trs80m4x.cmd
build/p8vi-trs80m4x.cmd: src/p8vi_trs80m4x.p8 src/editor.p8 src/buffer.p8 src/pagestore.p8 src/trs80m4x/* src/trs80m4/*.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSTRS80M4X) -o build/p8vi-trs80m4x $<
test-trs80m4x:	build/p8vi-trs80m4xtest.cmd
	$(PYTHON) -B $(TRSTEST) --model 4x -j 3
	$(PYTHON) -B $(TRSRECTEST)
trs80m4x-test: build/p8vi-trs80m4xtest.cmd
build/p8vi-trs80m4xtest.cmd: src/p8vi_trs80m4xtest.p8 src/editor.p8 src/buffer.p8 src/pagestore.p8 src/trs80m4x/* src/trs80m4/*.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSTRS80M4X) -o build/p8vi-trs80m4xtest $<

# the host version: a program for this machine (llvm64 and clang: macOS,
# Linux, Windows), in a terminal.  The CP/M version's screen (src/cpm,
# src/trs80) with the terminal as its console (src/host).
#   build/p8vi-host [-t ansi|vt52|adm3a] [-40] [file]
# 32-bit text positions (up to pos.TEXT_MAX, 16 MB): the editor core is
# compiled from copies with uword made long (tools/encode_copy.py --wide),
# src/wide/postype.p8 first.  (it needs a compiler whose sys.memcopy/memset
# take a long count on llvm64)
HOSTWIDE=build/hostwide
WIDEMODS=editor,buffer,gapbuffer,fastmem_platform,charset_platform
HOSTWIDE_DIRS=src src/trs80
PCCARGSHOST=-srcdirs "src/wide$(PS)$(HOSTWIDE)/src$(PS)src/host$(PS)src/cpm$(PS)$(HOSTWIDE)/trs80" -target llvm64
host: build/p8vi-host
build/p8vi-host: src/p8vi_host.p8 src/*.p8 src/wide/*.p8 src/host/*.p8 src/cpm/*.p8 src/trs80/*.p8 $(ENCODE_COPY)
	$(PYTHON) $(ENCODE_COPY) --wide $(WIDEMODS) $(HOSTWIDE) $(HOSTWIDE_DIRS)
	$(PCC) $(PCCARGSHOST) -o build/p8vi-host $(HOSTWIDE)/src/p8vi_host.p8
# edtest's file and screen suites, with the keys piped in (tests/cpm/cpmtest.py
# --host); :set number, :d and :y with ranges, a 4.5 MB file, and the
# screen the terminal's size
test-host:	build/p8vi-host
	$(PYTHON) -B $(CPMTEST) --host files
	$(PYTHON) -B $(CPMTEST) --host screen
	$(PYTHON) -B $(CPMTEST) --host number
	$(PYTHON) -B $(CPMTEST) --host lines
	$(PYTHON) -B $(CPMTEST) --host big
	$(PYTHON) -B $(CPMTEST) --host size

# CP/M 2.2 and later on a Z80 (src/cpm, with src/trs80's charset, fastmem
# and store): a .com for any machine with a terminal (-t ansi, vt52 or
# adm3a).  The z80-cpm profile leaves z88dk's heap off: the link options
# turn it on (AMALLOC: from the program's end up toward the stack).
# tnylpo runs it on the host: copy it as p8vi.com, then tnylpo -s p8vi -t vt52
PCCARGSCPM=-srcdirs "src$(PS)src/cpm$(PS)src/trs80" -target llvm16 -triple z80-cpm \
	-Xlink -pragma-define:CRT_HEAP_AMALLOC=1 -Xlink -pragma-define:CRT_HEAP_ENABLE=1
cpm: build/p8vi-cpm.com
build/p8vi-cpm.com: src/p8vi_cpm.p8 src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/cpm/*.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSCPM) -o build/p8vi-cpm $<
# the tests in tnylpo (skipped without it): the file suites, and the screen
# suites on each terminal (see tests/cpm/cpmtest.py); then the TRS-80 Model 4
# with Montezuma Micro CP/M in trs80gp, if its disk image is there
# (tests/cpm/m4test.py: CPM_DISK, or build/cpm222_work.dsk)
test-cpm:	build/p8vi-cpmtest.com build/p8vi-cpm.com
	$(PYTHON) -B $(CPMTEST) files
	$(PYTHON) -B $(CPMTEST) screen
	$(PYTHON) -B $(CPMTEST) number
	$(PYTHON) -B $(CPMTEST) lines
	$(PYTHON) -B $(M4TEST)
cpm-test: build/p8vi-cpmtest.com
build/p8vi-cpmtest.com: src/p8vi_cpmtest.p8 src/editor.p8 src/buffer.p8 src/gapbuffer.p8 src/cpm/*.p8 src/trs80/*.p8
	$(PCC) $(PCCARGSCPM) -o build/p8vi-cpmtest $<
# p8vi in tnylpo's full screen console (VT52 codes) in this terminal, in
# build/cpm with the samples (tnylpo's drive A is the directory; it only
# sees 8.3 names, so sampsmall.txt is sampsmal.txt too)
CPMDIR=build/cpm
emu-cpm:	build/p8vi-cpm.com
	$(MD) $(CPMDIR)
	$(CP) samples/*.txt $(CPMDIR)
	$(CP) samples/sampsmall.txt $(CPMDIR)/sampsmal.txt
	$(CP) build/p8vi-cpm.com $(CPMDIR)/p8vi.com
	cd $(CPMDIR) && tnylpo -s -w p8vi -t vt52
# the Amiga version (src/p8vi_amiga.p8, src/amiga; amiga500: a 68000 and
# Kickstart 1.3): the wide core as the host's, its undo records read a byte
# at a time (--bytewise: a 68000 long must be at an even address), with
# src/cpm's screen and src/trs80's charset, fastmem and store
AMIGAWIDE=build/amigawide
AMIGAWIDE_DIRS=src src/trs80
PCCARGSAMIGA=-srcdirs "src/wide$(PS)$(AMIGAWIDE)/src$(PS)src/amiga$(PS)src/cpm$(PS)$(AMIGAWIDE)/trs80" -target amiga500 -out build
amiga: build/p8vi-amiga
build/p8vi-amiga: src/p8vi_amiga.p8 src/*.p8 src/wide/*.p8 src/amiga/*.p8 src/cpm/*.p8 src/trs80/*.p8 $(ENCODE_COPY)
	$(PYTHON) $(ENCODE_COPY) --wide $(WIDEMODS) --bytewise $(AMIGAWIDE) $(AMIGAWIDE_DIRS)
	$(PCC) $(PCCARGSAMIGA) $(AMIGAWIDE)/src/p8vi_amiga.p8
	$(CP) build/p8vi_amiga $@
	$(RM) build/p8vi_amiga
# the test build: it plays the keys in keys.txt first (features.KEYFILE)
amiga-test: build/p8vi-amigatest
build/p8vi-amigatest: src/p8vi_amigatest.p8 src/*.p8 src/wide/*.p8 src/amiga/*.p8 src/cpm/*.p8 src/trs80/*.p8 $(ENCODE_COPY)
	$(PYTHON) $(ENCODE_COPY) --wide $(WIDEMODS) --bytewise $(AMIGAWIDE) $(AMIGAWIDE_DIRS)
	$(PCC) $(PCCARGSAMIGA) $(AMIGAWIDE)/src/p8vi_amigatest.p8
	$(CP) build/p8vi_amigatest $@
	$(RM) build/p8vi_amigatest
# edtest's file and screen suites and :set number's on an A500 in
# Copperline (tests/amiga/amigatest.py: Kickstart 1.3 if it's there, else
# AROS; the screen from p8vi's output redirected to a file; about a
# minute), and with 1.3 the window resized while p8vi runs (the mouse
# drags its size gadget)
test-amiga:	build/p8vi-amigatest
	$(PYTHON) -B $(AMIGATEST)
	$(PYTHON) -B $(AMIGATEST) screen
	$(PYTHON) -B $(AMIGATEST) number
	$(if $(AMIGA_ROM),$(PYTHON) -B $(AMIGATEST) --resize)

# p8vi on an A500 in Copperline (Kickstart 1.3 if it's there, else AROS),
# with the samples in its directory
emu-amiga:	build/p8vi-amiga
	$(MD) build/amiga
	$(CP) build/p8vi-amiga build/amiga/p8vi
	$(CP) samples/*.txt build/amiga
	cd build/amiga && copperline --model A500 --run p8vi --run-args sample.txt $(AMIGA_ROM)

# the Amiga port, step 1: the console's keys in raw mode (tests/amiga/
# keyecho.p8) on an A500 in Copperline, with Kickstart 1.3 if it's there
# (else Copperline's AROS)
AMIGA_ROM ?= $(wildcard $(HOME)/Documents/FS-UAE/Kickstarts/amiga-os-130.rom)
emu-amiga-keyecho:	build
	$(PCC) -target amiga500 -out build tests/amiga/keyecho.p8
	copperline --model A500 --run build/keyecho $(AMIGA_ROM)
# the TRS-80 Model 4 with Montezuma Micro CP/M 2.2 in trs80gp: drive A a
# copy of the system disk (CPM_DISK), drive B a new data disk with p8vi.com
# and samples (tools/cpm/m4disk.py; made again each time, so edits there
# aren't kept).  In CP/M: b: then p8vi -t adm3a.  The keyboard gives
# capitals until CAPS is pressed, and BREAK is Escape.
CPM_DISK ?= build/cpm222_work.dsk
emu-trs80m4-cpm:	build/p8vi-cpm.com
	$(CP) $(CPM_DISK) build/cpm-m4-a.dsk
	$(PYTHON) -B $(M4DISK) $(CPM_DISK) build/cpm-m4-b.dsk build/p8vi-cpm.com:p8vi.com \
		samples/sample.txt samples/sampsmall.txt samples/sample6.txt samples/sampmax.txt
	$(TRS80GP) -m4 -mem 64 -d0 build/cpm-m4-a.dsk -d1 build/cpm-m4-b.dsk

clean:
	$(RM) build/*

# the programs and the quick start guide, copied to release/ (kept in git:
# the last known good version, whatever build/ holds).  the quick checks
# run first; run make test-c64, test-c64reu and test-c64-screen too before
# a release that matters.  (the TRS-80 builds need llvm-z80 and z88dk, see
# trs80 above)
release:	$(PROGS) font build/p8vi-trs80.cmd build/p8vi-trs80m4.cmd build/p8vi-trs80m4x.cmd build/p8vi-cpm.com test audit size
	$(MD) release
	$(CP) build/p8vi-c64.prg release
	$(CP) build/p8vi-c64font.prg release
	$(CP) build/oscii.fnt release
	$(CP) build/p8vi-c64reu.prg release
	$(CP) build/p8vi-c64disk.prg release
	$(CP) build/p8vi-c128.prg release
	$(CP) build/p8vi-c128x.prg release
	$(CP) build/p8vi-c128reu.prg release
	$(CP) build/p8vi-cx16.prg release
	$(CP) build/p8vi-cx16iso.prg release
	$(CP) build/p8vi-mega65.prg release
	$(CP) build/p8vi-mega65dma.prg release
	$(CP) build/p8vi-pet32.prg release
	$(CP) build/p8vi-plus4.prg release
	$(CP) build/p8vi-vic20.prg release
	$(CP) build/p8vi-trs80.cmd release
	$(CP) build/p8vi-trs80m4.cmd release
	$(CP) build/p8vi-trs80m4x.cmd release
	$(CP) build/p8vi-cpm.com release
	$(CP) docs/QUICKSTART.md release

disk:	build/p8vi-c64.prg build/p8vi-c64reu.prg build/p8vi-c64font.prg build/oscii.fnt build/p8vi-vic20.prg
	c1541 -format $(DISKNAME),52 $(DISKTYPE) $(DISK)
	c1541 -attach $(DISK) -write build/p8vi-c64.prg p8vi,p
	c1541 -attach $(DISK) -write build/p8vi-c64reu.prg p8vi-reu,p
	c1541 -attach $(DISK) -write build/p8vi-c64font.prg p8vi-font,p
	c1541 -attach $(DISK) -write build/oscii.fnt oscii.fnt,p
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

# the font build (oscii.fnt is on the disk)
emu-c64font:	build/p8vi-c64font.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64font.prg

emu-cx16:	build/p8vi-cx16.prg
	x16emu -debug -scale 2 -rtc -fsroot samples/ -run -prg build/p8vi-cx16.prg

emu-cx16iso:	build/p8vi-cx16iso.prg
	x16emu -debug -scale 2 -rtc -fsroot samples/ -run -prg build/p8vi-cx16iso.prg

emu-mega65:	build/p8vi-mega65.prg
	xmega65 -prg build/p8vi-mega65.prg

emu-mega65dma:	build/p8vi-mega65dma.prg
	xmega65 -prg build/p8vi-mega65dma.prg

# which zero page bytes the MEGA65 ROM changes in KERNAL calls (for the
# zp_* lists in config/mega65.properties), in xmega65 headless.  the
# program is also on the disk as zpload, for its LOAD test.
ZPDISK=build/zpwatch.d81
test-mega65-zp:	build
	$(PCC) -target config/mega65.properties -srcdirs "tests/mega65" -out build tests/mega65/zpwatch.p8
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
	$(PYTHON) -B $(M65TEST) --font $(FONT_SKIP_M65) files
	$(PYTHON) -B $(M65TEST) screen

# the same on the MEGA65 page store build, with the suites for more text
# than main RAM holds (--paged) and the font suite: the pages in attic RAM
# (xemu has it).  left out: subst, subst-again, read-dir, marks and zview (SUBST, DIR,
# MARKS and Z_VIEW are off in this build), and g-cmds and ascii as above.  then some of them as on a
# Nexys4 board (model ID $40), without attic RAM: the pages in banks 4 and
# 5 (not bigundo: 30 KB of text, undo and yank need more than their 126
# pages; it fails the same way on a C64 with a 128 KB REU)
test-mega65dma:	build/p8vi-mega65dma.prg
	$(PYTHON) -B $(M65TEST) --prg build/p8vi-mega65dma.prg --paged --font \
		--skip subst --skip subst-again --skip read-dir --skip prefix --skip marks --skip zview $(FONT_SKIP_M65) files
	$(PYTHON) -B $(M65TEST) --prg build/p8vi-mega65dma.prg --paged --model 64 \
		files delete-put undo pages huge
	$(PYTHON) -B $(M65TEST) --prg build/p8vi-mega65dma.prg screen

# which keys give which PETSCII codes (the table in tools/m65harness.py)
test-mega65-keymap:	build
	$(PCC) -target config/mega65.properties -srcdirs "tests/mega65" -out build tests/mega65/keyecho.p8
	$(PYTHON) -B $(M65KEYMAP) --prg build/keyecho.prg

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

# the C64 disk paging build: its swap files go on the test disk (a 1581
# in VICE is slow; the build is meant for fast drives)
emu-c64disk:	build/p8vi-c64disk.prg disk
	$(EMU) -monitorfont "JetBrains Mono 16" -autostartprgmode 1 build/p8vi-c64disk.prg

# the C128 builds in their own mode, with the test disk (oscii.fnt is on
# it, for p8vi-c128x).  the 40 column screen; make emu-c128 C128COL=-80col
# for the 80 column one
C128COL=-40col
EMU128=x128 -default -keymap 1 -model ntsc $(C128COL) -8 $(DISK) -drive8type 1581 -monitorfont "JetBrains Mono 16"
emu-c128:	build/p8vi-c128.prg disk
	$(EMU128) -autostartprgmode 1 build/p8vi-c128.prg
emu-c128x:	build/p8vi-c128x.prg disk
	$(EMU128) -autostartprgmode 1 build/p8vi-c128x.prg
emu-c128reu:	build/p8vi-c128reu.prg disk
	$(EMU128) $(EMU_REU) -autostartprgmode 1 build/p8vi-c128reu.prg

# the TRS-80s in trs80gp (TRS80GP, the path of its binary): it boots the
# DOS and runs p8vi itself, with its utility disk in drive 1 (FreHD's
# IMPORT2 and EXPORT2) and build/frehd as the FreHD's directory (p8vi and
# samples/).  "IMPORT2 sample.txt SAMPLE/TXT:1" brings in a sample, and
# "IMPORT2 p8vi.cmd P8VI/CMD:1" p8vi to run it again (changes to the
# built-in disks aren't kept).  (this needs a compiler from 2026-11-10 or
# later: before, z88dk's start-up code zeroed the DOS's ENTER when trs80gp
# ran a .cmd itself, bugs/trs80m4_enter_key.md.)  the Model III with
# LDOS, the Model 4 with TRSDOS 6 (m4x: 128 KB)
TRS80GP ?= $(HOME)/Applications/trs80gp.app/Contents/MacOS/trs80gp
FREHD=build/frehd
TRS80RUN=-frehd -frehd_dir $(FREHD)
emu-trs80:	build/p8vi-trs80.cmd
	$(MD) $(FREHD)
	$(CP) samples/*.txt $(FREHD)
	$(CP) build/p8vi-trs80.cmd $(FREHD)/p8vi.cmd
	$(TRS80GP) -m3 -ld -d1 :lu3 $(TRS80RUN) build/p8vi-trs80.cmd
emu-trs80m4:	build/p8vi-trs80m4.cmd
	$(MD) $(FREHD)
	$(CP) samples/*.txt $(FREHD)
	$(CP) build/p8vi-trs80m4.cmd $(FREHD)/p8vi.cmd
	$(TRS80GP) -m4 -d1 :lu4 $(TRS80RUN) build/p8vi-trs80m4.cmd
emu-trs80m4x:	build/p8vi-trs80m4x.cmd
	$(MD) $(FREHD)
	$(CP) samples/*.txt $(FREHD)
	$(CP) build/p8vi-trs80m4x.cmd $(FREHD)/p8vi.cmd
	$(TRS80GP) -m4 -mem 128 -d1 :lu4 $(TRS80RUN) build/p8vi-trs80m4x.cmd

# self checking text store tests (gap buffer and page store) on the
# virtual target
test-gap:	build
	$(PCC) -quiet $(PCCARGSVM) -emu src/gaptest.p8 | grep -v 'INFO\|WARN' | diff -u tests/expected/virtual_gaptest.txt -
	$(PCC) -quiet $(PCCARGSVM) -emu src/pagetest.p8 | grep -v 'INFO\|WARN' | diff -u tests/expected/virtual_pagetest.txt -

# memory map of each build and the room left below memtop
# (tools/listsize.py LIST for where the bytes go, A.list B.list to compare)
VIC20_MIN_FREE=64
size:	$(PROGS) $(FONTPROG)
	$(PYTHON) $(LISTSIZE) build/p8vi-c64.list --map
	$(PYTHON) $(LISTSIZE) build/p8vi-c64reu.list --map
	$(PYTHON) $(LISTSIZE) build/p8vi-c64disk.list --map
	$(PYTHON) $(LISTSIZE) build/p8vi-c64font.list --map --memtop 0xc800
	$(PYTHON) $(LISTSIZE) build/p8vi-cx16.list --map
	$(PYTHON) $(LISTSIZE) build/p8vi-cx16iso.list --map
	$(PYTHON) $(LISTSIZE) build/p8vi-mega65.list --map --memtop 0xc000
	$(PYTHON) $(LISTSIZE) build/p8vi-mega65dma.list --map --memtop 0xc000
	$(PYTHON) $(LISTSIZE) build/p8vi-pet32.list --map --memtop 0x8000
	$(PYTHON) $(LISTSIZE) build/p8vi-c128.list --map --memtop 0xc000
	$(PYTHON) $(LISTSIZE) build/p8vi-c128x.list --map --memtop 0xc000
	$(PYTHON) $(LISTSIZE) build/p8vi-c128reu.list --map --memtop 0xc000
	$(PYTHON) $(LISTSIZE) build/p8vi-plus4.list --map --memtop 0xfc00
	$(PYTHON) $(LISTSIZE) build/p8vi-vic20.list --map --min-free $(VIC20_MIN_FREE)

# the quick tier, for iterating: the virtual tests, the size checks, then one
# or two suites per build side by side (tests/quick.py, a few minutes).  the
# full suites (test-c64 ... test-trs80m4x) before a release.  only some
# builds: make quick QUICK="c64 c128x" (tests/quick.py --list shows them)
quick:	$(PROGS) $(FONTPROG) build/oscii.fnt build/p8vi-host build/p8vi-cpmtest.com build/p8vi-trs80test.cmd build/p8vi-trs80m4test.cmd build/p8vi-trs80m4xtest.cmd build/p8vi-amigatest test size
	$(PYTHON) -B $(QUICKTEST) $(QUICK)

# editor tests on a C64 in VICE (x64sc and c1541 in the PATH)
test-c64:	build/p8vi-c64.prg
	$(PYTHON) $(EDTEST) files --prg build/p8vi-c64.prg

# the same tests on the Plus/4 (VICE's xplus4 with a 1541)
test-plus4:	build/p8vi-plus4.prg
	$(PYTHON) -B $(EDTEST) files --machine plus4 -j 4 --prg build/p8vi-plus4.prg
	$(PYTHON) -B $(EDTEST) screen --machine plus4 -j 4 --prg build/p8vi-plus4.prg

# the same tests on the C128 (VICE's x128, a 1541), on the 40 column and
# the 80 column (VDC) screen
test-c128:	build/p8vi-c128.prg
	$(PYTHON) -B $(EDTEST) files --machine c128 -j 4 --prg build/p8vi-c128.prg
	$(PYTHON) -B $(EDTEST) screen --machine c128 -j 4 --prg build/p8vi-c128.prg
	$(PYTHON) -B $(EDTEST) files --machine c128-80 -j 4 --prg build/p8vi-c128.prg
	$(PYTHON) -B $(EDTEST) screen --machine c128-80 -j 4 --prg build/p8vi-c128.prg

# the C128 bank 1 build: also the page store's suites (--paged), except
# read-dir (no :@$ in this build) and the two that need more than bank 1
# holds (huge: about 87 KB of text; bigundo: 29 KB and its undo), and
# marks and zview (features.MARKS and Z_VIEW are off for room)
C128X_SKIP = --skip read-dir --skip huge --skip bigundo --skip marks --skip zview
# p8vi-c128x is also a font build (oscii.fnt on its disks, and the font
# suite): it leaves out g-cmds and ascii as the C64 font build does
C128X_FONT = --font build/oscii.fnt --skip g-cmds --skip ascii
test-c128x:	build/p8vi-c128x.prg build/oscii.fnt
	$(PYTHON) -B $(EDTEST) files --machine c128 --paged --limit 3000000000 -j 4 $(C128X_SKIP) $(C128X_FONT) --prg build/p8vi-c128x.prg
	$(PYTHON) -B $(EDTEST) screen --machine c128 -j 4 --font build/oscii.fnt --prg build/p8vi-c128x.prg
	$(PYTHON) -B $(EDTEST) files --machine c128-80 --paged --limit 3000000000 -j 4 $(C128X_SKIP) $(C128X_FONT) --prg build/p8vi-c128x.prg
	$(PYTHON) -B $(EDTEST) screen --machine c128-80 -j 4 --font build/oscii.fnt --prg build/p8vi-c128x.prg
	$(PYTHON) -B $(RECTEST) --machine c128 --no-reu --font build/oscii.fnt --prg build/p8vi-c128x.prg

# the C128 REU build: with a 512 KB REU (all the page store's suites), and
# without one (bank 1, as test-c128x); read-dir: no :@$ in this build,
# no marks or & either
test-c128reu:	build/p8vi-c128reu.prg
	$(PYTHON) -B $(EDTEST) files --machine c128 --reu 512 --limit 3000000000 -j 4 --skip read-dir --skip prefix --skip marks --skip subst-again --prg build/p8vi-c128reu.prg
	$(PYTHON) -B $(EDTEST) screen --machine c128 --reu 512 -j 4 --prg build/p8vi-c128reu.prg
	$(PYTHON) -B $(EDTEST) files --machine c128-80 --reu 512 --limit 3000000000 -j 4 --skip read-dir --skip prefix --skip marks --skip subst-again --prg build/p8vi-c128reu.prg
	$(PYTHON) -B $(EDTEST) screen --machine c128-80 --reu 512 -j 4 --prg build/p8vi-c128reu.prg
	$(PYTHON) -B $(EDTEST) files --machine c128 --paged --limit 3000000000 -j 4 $(C128X_SKIP) --skip prefix --skip subst-again --prg build/p8vi-c128reu.prg
	$(PYTHON) -B $(RECTEST) --machine c128 --prg build/p8vi-c128reu.prg
	$(PYTHON) -B $(RECTEST) --machine c128-80 --no-reu --prg build/p8vi-c128reu.prg

# the same tests on the PET (VICE's xpet, a 4032 with a 2031 drive).  left
# out, for the features it doesn't have: ascii, crlf, big, final-eol,
# read-format, find (ASCII and CR LF files), subst, subst-again, dos, read-dir
PET_SKIP = --skip ascii --skip crlf --skip big --skip final-eol --skip read-format --skip find \
	--skip subst --skip subst-again --skip dos --skip read-dir
test-pet32:	build/p8vi-pet32.prg
	$(PYTHON) -B $(EDTEST) files --machine pet -j 4 --prg build/p8vi-pet32.prg $(PET_SKIP)
	$(PYTHON) -B $(EDTEST) screen --machine pet -j 4 --prg build/p8vi-pet32.prg

# the same tests on the C64 disk build (pages in SEQ files on the 1541),
# with the REU suites' 6 KB text (--paged).  huge and bigundo are left
# out: their 30-64 KB of text and its pages don't fit on a 1541 disk
# beside the program
test-c64disk:	build/p8vi-c64disk.prg
	$(PYTHON) -B $(EDTEST) files --prg build/p8vi-c64disk.prg --paged --limit 3000000000 \
		--skip huge --skip bigundo
	$(PYTHON) -B $(EDTEST) screen --prg build/p8vi-c64disk.prg

# the same tests on the C64 REU build (the page store), with an REU and
# without one (then it has 4 KB of text: not the big file suite)
test-c64reu:	build/p8vi-c64reu.prg
	$(PYTHON) $(EDTEST) files --prg build/p8vi-c64reu.prg --reu 512 --limit 3000000000
	$(PYTHON) $(EDTEST) files --prg build/p8vi-c64reu.prg --skip big
	$(PYTHON) $(RECTEST) --prg build/p8vi-c64reu.prg
	$(PYTHON) $(EDTEST) screen --prg build/p8vi-c64reu.prg --reu 512

# the font build: the REU build's tests, and its own (the font suite).
# it has its own keys for | (and } is shift + minus), its own PETSCII for
# ASCII files and oscii.fnt on the disk, so g-cmds, ascii and read-dir
# don't apply, and marks and zview: it has neither (features.MARKS, Z_VIEW)
FONT_SKIP = --skip g-cmds --skip ascii --skip read-dir --skip marks --skip zview
test-c64font:	build/p8vi-c64font.prg build/oscii.fnt
	$(PYTHON) $(EDTEST) files --prg build/p8vi-c64font.prg --font build/oscii.fnt --reu 512 --limit 3000000000 $(FONT_SKIP)
	$(PYTHON) $(EDTEST) files --prg build/p8vi-c64font.prg --font build/oscii.fnt --skip big $(FONT_SKIP)
	$(PYTHON) $(RECTEST) --prg build/p8vi-c64font.prg --font build/oscii.fnt
	$(PYTHON) $(EDTEST) screen --prg build/p8vi-c64font.prg --font build/oscii.fnt --reu 512

# partial redraws must leave the same screen as a full redraw
test-c64-screen:	build/p8vi-c64.prg
	$(PYTHON) $(EDTEST) screen --prg build/p8vi-c64.prg

# the same C64 tests with JiffyDOS (VICE's jiffykernal and jiffy1541II
# ROMs, in its ROM directories, as EMU_KERNAL and EMU_DOS above), to
# compare with the ones above
JIFFY = --jiffydos
test-c64-jiffydos:	build/p8vi-c64.prg
	$(PYTHON) -B $(EDTEST) files $(JIFFY) --prg build/p8vi-c64.prg

test-c64-screen-jiffydos:	build/p8vi-c64.prg
	$(PYTHON) -B $(EDTEST) screen $(JIFFY) --prg build/p8vi-c64.prg

test-c64reu-jiffydos:	build/p8vi-c64reu.prg
	$(PYTHON) -B $(EDTEST) files $(JIFFY) --prg build/p8vi-c64reu.prg --reu 512 --limit 3000000000
	$(PYTHON) -B $(EDTEST) files $(JIFFY) --prg build/p8vi-c64reu.prg --skip big
	$(PYTHON) -B $(RECTEST) $(JIFFY) --prg build/p8vi-c64reu.prg
	$(PYTHON) -B $(EDTEST) screen $(JIFFY) --prg build/p8vi-c64reu.prg --reu 512

test-c64font-jiffydos:	build/p8vi-c64font.prg build/oscii.fnt
	$(PYTHON) -B $(EDTEST) files $(JIFFY) --prg build/p8vi-c64font.prg --font build/oscii.fnt --reu 512 --limit 3000000000 $(FONT_SKIP)
	$(PYTHON) -B $(EDTEST) files $(JIFFY) --prg build/p8vi-c64font.prg --font build/oscii.fnt --skip big $(FONT_SKIP)
	$(PYTHON) -B $(RECTEST) $(JIFFY) --prg build/p8vi-c64font.prg --font build/oscii.fnt
	$(PYTHON) -B $(EDTEST) screen $(JIFFY) --prg build/p8vi-c64font.prg --font build/oscii.fnt --reu 512

test-c64disk-jiffydos:	build/p8vi-c64disk.prg
	$(PYTHON) -B $(EDTEST) files $(JIFFY) --prg build/p8vi-c64disk.prg --paged --limit 3000000000 \
		--skip huge --skip bigundo
	$(PYTHON) -B $(EDTEST) screen $(JIFFY) --prg build/p8vi-c64disk.prg

# all the C64 tests with JiffyDOS
test-jiffydos:	test-c64-jiffydos test-c64-screen-jiffydos test-c64reu-jiffydos test-c64font-jiffydos test-c64disk-jiffydos

# REU tests on a C64 in VICE: detection finds every size and leaves the
# REU's memory alone, and the REU keeps its memory over a reset
test-reu:	build
	$(PCC) -quiet $(PCCARGSC64) tests/reu/reudetect.p8
	$(PCC) -quiet $(PCCARGSC64) tests/reu/reureset.p8
	$(PYTHON) $(REUTEST) --build build

# look in the generated assembler for the silent miscompiles found so far
# (bugs/uword_array_eq_ubyte.p8, bugs/min_ubyte_expressions.p8)
audit:	$(PROGS) $(FONTPROG)
	$(PYTHON) $(ASMAUDIT) build/p8vi-c64.asm build/p8vi-c64reu.asm build/p8vi-c64font.asm build/p8vi-cx16.asm build/p8vi-vic20.asm

# the 6502 fastmem routines against plain Prog8, on a C64 in VICE
test-fastmem:	build
	$(PCC) -quiet -srcdirs "src$(PS)src/c64" -target c64 -out build tests/fastmem/fastmemtest.p8
	cd build && x64sc -default -minimized -sounddev dummy -warp -debugcart -autostartprgmode 1 -autostart fastmemtest.prg -limitcycles 900000000 -exitscreenshot fastmemtest.png > fastmemtest.log 2>&1; grep -q 'DBGCART: exit(0)' fastmemtest.log && echo "fastmem: ok" || (echo "fastmem: FAIL, see build/fastmemtest.png"; false)

# timings of the text store routines on a C64 in VICE (page store and gap
# buffer), screenshots in build/bench-page.png and build/bench-gap.png
bench:	build
	$(PCC) -quiet -srcdirs "src$(PS)src/c64reu$(PS)src/c64" -target c64 -out build tests/bench/storebench.p8
	cd build && x64sc -default -minimized -sounddev dummy -warp -debugcart -autostartprgmode 1 -autostart storebench.prg -limitcycles 900000000 -exitscreenshot bench-page.png >/dev/null 2>&1
	$(PCC) -quiet -srcdirs "src$(PS)src/c64" -target c64 -out build tests/bench/storebench.p8
	cd build && x64sc -default -minimized -sounddev dummy -warp -debugcart -autostartprgmode 1 -autostart storebench.prg -limitcycles 900000000 -exitscreenshot bench-gap.png >/dev/null 2>&1

# the text store tests on the virtual target (output compared with
# tests/expected/)
test:	test-gap

#
# end-of-file
#
