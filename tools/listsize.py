#!/usr/bin/env python3
"""Where does the size of a program go?  Reads the 64tass listing that
`prog8c -asmlist` writes (build/<name>.list) and reports:

  * the memory map: load address, code + initialised data, variables (BSS),
    the end of the program, and how much room is left below memtop
  * bytes of code + initialised data per block and per subroutine
  * bytes of variables, from their declarations (.byte ?, .word ?, .fill n)
  * zeropage variables

    tools/listsize.py build/main.list                  # map, blocks, top 25 subs
    tools/listsize.py LIST --top 60                    # more rows
    tools/listsize.py LIST --block main                # only subs of block main
    tools/listsize.py LIST --bss                       # the biggest variables
    tools/listsize.py A.list B.list                    # what changed, A -> B
    tools/listsize.py LIST --map --min-free 128        # exit 1 if less room left

memtop comes from the memtop check in the .asm file next to the listing
(prog8 writes `.cerror * >= $8000` there), or from --memtop.

Code sizes come from address differences, so they include padding and the
data tables that follow a routine.  Local labels (loops, branches) stay with
the routine they are in.  Labels outside any p8b_ block (the runtime that
Prog8 adds, the libraries compiled without symbol prefixes) are reported
under "(runtime)".  Listings from other programs work too: their global
labels are taken as the routines.
"""
import argparse
import os
import re
import sys
from collections import defaultdict

ADDR = re.compile(r"^([.>])([0-9a-f]+)$")
HEX = re.compile(r"[0-9a-f]{2}( [0-9a-f]{2})*")
IDENT = re.compile(r"[A-Za-z_][\w.]*|[+\-]+")
MNEMONICS = set("""adc and asl bcc bcs beq bit bmi bne bpl brk bvc bvs clc cld cli
    clv cmp cpx cpy dec dex dey eor inc inx iny jmp jsr lda ldx ldy lsr nop ora
    pha php pla plp rol ror rti rts sbc sec sed sei sta stx sty tax tay tsx txa
    txs tya bra phx phy plx ply stz trb tsb wai stp""".split())
ZP_LINE = re.compile(r"^=(\d+)\t+(p8v_\w+)\s*=\s*\d+\s*;\s*zp\s+(\w+)")
LOCAL = re.compile(r"^(\+|-|_.*|p8_label_gen_\d+_(?!tempv).*|p8l_.*|\.\w+)$")
BSS_DECL = re.compile(r"^\.(byte|word|dword|long|fill)\b\s*(.*)$")
TYPE_SIZE = {"ubyte": 1, "byte": 1, "bool": 1, "uword": 2, "word": 2,
             "pointer": 2, "long": 4, "float": 5}

# markers prog8 puts in its listings
BSS_START = "prog8_bss_section_start"
PROGRAM_END = "prog8_program_end"


def split_line(raw, monitor):
    """a listing line -> (addr, number of bytes, label, statement), or None.
    the columns are separated by tabs: address, hex bytes, the disassembly
    (only with a Monitor column, on lines with code), then the source line:
    a label and/or a statement."""
    fields = raw.split("\t")
    m = ADDR.match(fields[0])
    if not m:
        return None
    rest = fields[1:]
    hexf = ""
    if rest and HEX.fullmatch(rest[0].strip()):
        hexf = rest.pop(0).strip()
    src = [f.strip() for f in rest if f.strip()]
    if monitor and m.group(1) == "." and hexf and src:
        src.pop(0)
    label, stmt = None, ""
    if len(src) >= 2:
        label, stmt = src[0], " ".join(src[1:])
    elif src:
        parts = src[0].split(None, 1)
        if len(parts) == 2 and IDENT.fullmatch(parts[0]) and parts[0].lower() not in MNEMONICS:
            label, stmt = parts          # label and statement without a tab
        elif IDENT.fullmatch(src[0]) and src[0].lower() not in MNEMONICS:
            label = src[0]
        else:
            stmt = src[0]
    if label and not IDENT.fullmatch(label):
        label, stmt = None, " ".join(src)
    return int(m.group(2), 16), len(hexf.split()), label, stmt


def bss_size(kind, operand):
    """bytes declared by a .byte/.word/.fill line, None if it isn't BSS"""
    operand = operand.split(";")[0].strip()
    if kind == "fill":
        expr = operand.split(",")[0]
        if not re.fullmatch(r"[\d\s*+()]+", expr):
            return None
        return eval(expr)  # only digits and * + ( ), checked above
    if operand.replace(" ", "").strip("?,") != "":
        return None  # initialised data, not BSS
    per = {"byte": 1, "word": 2, "dword": 4, "long": 3}[kind]
    return per * operand.count("?")


class Listing:
    def __init__(self, path):
        self.path = path
        self.subs = defaultdict(int)     # (block, sub) -> code + data bytes
        self.vars = defaultdict(int)     # (block, sub.var) -> BSS bytes
        self.zp = defaultdict(int)       # (block, sub.var) -> zeropage bytes
        self.labels = {}
        self.first = None                # lowest code/data address
        self.last = None                 # 1 past the highest code/data byte
        self.var_first = None            # lowest variable address
        self.var_end = None              # 1 past the highest variable byte
        self._parse()
        self.memtop = memtop_from_asm(path)

    def _parse(self):
        entries = []  # (addr, kind, text, nbytes)
        zp_entries = []
        var = "?"
        monitor = False
        with open(self.path, encoding="utf-8", errors="replace") as f:
            for raw in f:
                raw = raw.rstrip("\n")
                if raw.startswith(";Offset"):
                    monitor = ";Monitor" in raw
                    continue
                m = ZP_LINE.match(raw)
                if m:
                    zp_entries.append((len(entries), m.group(2), m.group(3)))
                    continue
                line = split_line(raw, monitor)
                if not line:
                    continue
                addr, nbytes, label, stmt = line
                d = BSS_DECL.match(stmt)
                size = bss_size(d.group(1), d.group(2)) if d and not nbytes else None
                if size is not None:
                    # a variable; an unnamed one belongs to the one before it
                    var = label or var
                    entries.append((addr, "bss", var, size))
                    continue
                if label:
                    entries.append((addr, "label", label, 0))
                if nbytes or stmt.startswith("."):
                    entries.append((addr, "code", stmt, nbytes))
        # the size of a code/data line is the distance to the next one, in
        # address order (that includes .fill data and alignment padding)
        code = sorted({e[0] for e in entries if e[1] == "code"})
        nxt = {a: b - a for a, b in zip(code, code[1:])}
        if code:
            self.first = code[0]
            last = max((e for e in entries if e[1] == "code"), key=lambda e: e[0])
            nxt[last[0]] = last[3]
            self.last = last[0] + last[3]

        block, cur = "(runtime)", None
        zp_iter = iter(zp_entries)
        zp_next = next(zp_iter, None)
        for i, (addr, kind, text, size) in enumerate(entries):
            while zp_next and zp_next[0] <= i:
                self.zp[(block, qual(cur, zp_next[1]))] += TYPE_SIZE.get(zp_next[2], 2)
                zp_next = next(zp_iter, None)
            if kind == "label":
                self.labels.setdefault(text, addr)
                if text.startswith("p8b_"):
                    block, cur = text[4:], None
                elif text.startswith("p8s_"):
                    cur = text[4:]
                elif text.startswith("prog8_") or text.startswith("p8v_") or \
                        text.startswith("p8c_") or LOCAL.match(text):
                    pass
                elif re.fullmatch(r"string_\d+", text):
                    # interned strings, numbered anew in each build
                    block, cur = "(runtime)", "(strings)"
                else:
                    # a routine outside any p8b_ block
                    block, cur = "(runtime)", text
            elif kind == "bss":
                # reserved space inside the code (the launcher's room for
                # the cx16 registers) is already part of the code's size
                if self.first is None or not self.first <= addr < self.last:
                    self.vars[(block, qual(cur, text))] += size
                    self.var_end = max(self.var_end or 0, addr + size)
                    self.var_first = min(self.var_first or addr, addr)
            else:
                self.subs[(block, cur or "(block data)")] += nxt.pop(addr, 0)
        for _, name, typ in ([zp_next] if zp_next else []) + list(zp_iter):
            self.zp[(block, qual(cur, name))] += TYPE_SIZE.get(typ, 2)
        if not any(t.startswith("p8b_") for t in self.labels):
            # not a prog8 program: its routines are all there is
            for d in (self.subs, self.vars, self.zp):
                for (b, n) in list(d):
                    d[("(program)", n)] = d.pop((b, n))

    @property
    def code_bytes(self):
        return sum(self.subs.values())

    @property
    def bss_bytes(self):
        return sum(self.vars.values())

    @property
    def end(self):
        """1 past the last byte the program uses, variables included"""
        if PROGRAM_END in self.labels:
            return self.labels[PROGRAM_END]
        return max(x for x in (self.last, self.var_end, 0) if x is not None) or None

    @property
    def free(self):
        if self.memtop is None or self.end is None:
            return None
        return self.memtop - self.end


def qual(sub, var):
    var = var.replace("p8v_", "")
    # temporaries are numbered anew in each build; keep diffs readable
    if re.fullmatch(r"p8_label_gen_\d+_tempv", var):
        var = "(temp)"
    return f"{sub}.{var}" if sub else var


def memtop_from_asm(list_path):
    asm = os.path.splitext(list_path)[0] + ".asm"
    try:
        with open(asm, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.search(r"\.cerror\s+\*\s*>=?\s*\$([0-9a-fA-F]+)", line)
                if m:
                    return int(m.group(1), 16)
    except OSError:
        pass
    return None


def hexa(a):
    return "?" if a is None else f"${a:04x}"


def show_map(lst):
    print(f"{lst.path}:")
    print(f"  code + data  {hexa(lst.first)}-{hexa(lst.last)}  {lst.code_bytes:6d} bytes")
    bss_start = lst.labels.get(BSS_START, lst.var_first)
    where = f"from {hexa(bss_start)}" if bss_start is not None else ""
    print(f"  variables    {where:11s}  {lst.bss_bytes:6d} bytes")
    zp = sum(lst.zp.values())
    if zp:
        print(f"  zeropage     {'':11s}  {zp:6d} bytes")
    line = f"  end          {hexa(lst.end)}"
    if lst.memtop is not None:
        line += f"   memtop {hexa(lst.memtop)}   free {lst.free} bytes"
        if lst.free < 0:
            line += "   (TOO BIG)"
    print(line)


def table(rows, total, top, fmt="{n:6d}  {pct:5.1f}%  {name}"):
    for (block, name), n in rows[:top]:
        print("  " + fmt.format(n=n, pct=100.0 * n / total, name=f"{block}.{name}"))
    rest = sum(n for _, n in rows[top:])
    if rest:
        print(f"  {rest:6d}  {100.0 * rest / total:5.1f}%  ({len(rows) - top} more)")


def show(lst, args):
    show_map(lst)
    if args.map:
        return
    if args.bss:
        rows = sorted(lst.vars.items(), key=lambda kv: -kv[1])
        print("variables:")
        table(rows, lst.bss_bytes or 1, args.top)
        if lst.zp:
            print("zeropage variables:")
            table(sorted(lst.zp.items(), key=lambda kv: -kv[1]),
                  sum(lst.zp.values()), args.top)
        return
    total = lst.code_bytes or 1
    blocks = defaultdict(int)
    for (b, _), n in lst.subs.items():
        blocks[b] += n
    print("code + data by block:")
    for b, n in sorted(blocks.items(), key=lambda kv: -kv[1]):
        print(f"  {n:6d}  {100.0 * n / total:5.1f}%  {b}")
    rows = [kv for kv in lst.subs.items() if not args.block or kv[0][0] == args.block]
    rows.sort(key=lambda kv: -kv[1])
    print("code + data by subroutine:" + (f" (block {args.block})" if args.block else ""))
    table(rows, total, args.top)


def changes(a, b, top, title):
    keys = set(a) | set(b)
    rows = sorted(((k, b.get(k, 0) - a.get(k, 0)) for k in keys),
                  key=lambda kv: (-abs(kv[1]), kv[0]))
    rows = [r for r in rows if r[1]]
    if not rows:
        return
    print(f"{title}:")
    for (block, name), d in rows[:top]:
        note = " (new)" if (block, name) not in a else " (gone)" if (block, name) not in b else ""
        print(f"  {d:+7d}  {block}.{name}{note}")
    rest = sum(d for _, d in rows[top:])
    if rest:
        print(f"  {rest:+7d}  ({len(rows) - top} more)")


def diff(a, b, args):
    print(f"{a.path} -> {b.path}")

    def line(label, x, y):
        if x is None or y is None:
            return
        print(f"  {label:13s}{x:7d} -> {y:7d}  {y - x:+d}")
    line("code + data", a.code_bytes, b.code_bytes)
    line("variables", a.bss_bytes, b.bss_bytes)
    line("zeropage", sum(a.zp.values()), sum(b.zp.values()))
    line("free", a.free, b.free)
    changes(a.subs, b.subs, args.top, "code + data")
    changes(a.vars, b.vars, args.top, "variables")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("lists", nargs="+", help="one .list file, or two to compare")
    ap.add_argument("--top", type=int, default=25, help="rows to show (default 25)")
    ap.add_argument("--block", help="only subroutines of this block (main, txt ...)")
    ap.add_argument("--bss", action="store_true", help="list the biggest variables")
    ap.add_argument("--map", action="store_true", help="only the memory map")
    ap.add_argument("--memtop", type=lambda s: int(s.replace("$", "0x"), 0),
                    help="first address the program may not use ($8000, 0x8000)")
    ap.add_argument("--min-free", type=int, metavar="N",
                    help="exit 1 if fewer than N bytes are left below memtop")
    args = ap.parse_args()
    if len(args.lists) > 2:
        sys.exit("give one or two .list files")
    lists = [Listing(p) for p in args.lists]
    for lst in lists:
        if args.memtop is not None:
            lst.memtop = args.memtop
    if len(lists) == 1:
        show(lists[0], args)
    else:
        diff(lists[0], lists[1], args)
    if args.min_free is not None:
        lst = lists[-1]
        if lst.free is None:
            sys.exit(f"{lst.path}: memtop unknown, use --memtop")
        if lst.free < args.min_free:
            sys.exit(f"{lst.path}: only {lst.free} bytes free, want {args.min_free}")


if __name__ == "__main__":
    main()
