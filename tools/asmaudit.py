#!/usr/bin/env python3
"""Look in Prog8's generated 64tass assembler for signs of the silent
miscompiles found so far (see bugs/):

  wide byte   a byte variable used as a word: "cmp p8v_id+1" where p8v_id
              is a ubyte (bugs/uword_array_eq_ubyte.p8)
  self cmp    "sta X" straight followed by "cmp X": A compared with itself
              (bugs/min_ubyte_expressions.p8)

    python3 tools/asmaudit.py build/p8vi-c64.asm [more.asm ...]

Prints each finding with its source line (from the asm's "; source:"
comments) and exits 1 if there are any.
"""

import re
import sys

DECL_MEM = re.compile(r'^(\w+)\s+\.(byte|word|fill|text|null|dword|sint|char)\b(.*)$')
DECL_EQU = re.compile(r'^(\w+)\s*=\s*\S+\s*;\s*zp\s+(\w+)')
PROC = re.compile(r'^(\w+)\s+\.proc\b')
PEND = re.compile(r'^\s+\.pend\b')
INSTR = re.compile(r'^\s+([a-z]{3})\s+(.*?)\s*(;.*)?$')
OPERAND_REF = re.compile(r'([A-Za-z_][\w.]*)\+(\d+)')
SOURCE = re.compile(r';\s*source:\s*(.*)$')

BYTE_TYPES = {'byte', 'ubyte', 'bool'}


def scan(path):
    lines = open(path, errors='replace').read().splitlines()
    # pass 1: the variables in every scope, and their size
    sizes = {}          # (scope tuple, name) -> 'byte' / 'word' / 'array'
    scope = []
    for line in lines:
        m = PROC.match(line)
        if m:
            scope.append(m.group(1))
            continue
        if PEND.match(line):
            if scope:
                scope.pop()
            continue
        m = DECL_EQU.match(line)
        if m:
            sizes[(tuple(scope), m.group(1))] = 'byte' if m.group(2) in BYTE_TYPES else 'other'
            continue
        m = DECL_MEM.match(line)
        if m:
            name, kind, rest = m.groups()
            if kind == 'byte' and rest.strip().split(',')[0].strip() in ('?', '0', '1') and ',' not in rest:
                sizes[(tuple(scope), name)] = 'byte'
            else:
                sizes[(tuple(scope), name)] = 'other'

    def resolve(scope, name):
        """the size of name as 64tass finds it from scope (inner scopes first)"""
        parts = name.split('.')
        for depth in range(len(scope), -1, -1):
            key = (tuple(scope[:depth]) + tuple(parts[:-1]), parts[-1])
            if key in sizes:
                return sizes[key]
        return None

    # pass 2: references
    findings = []
    scope = []
    source = '?'
    prev = None         # (opcode, operand) of the instruction before
    for n, line in enumerate(lines, 1):
        m = SOURCE.search(line)
        if m and line.lstrip().startswith(';'):
            source = m.group(1)
            continue
        m = PROC.match(line)
        if m:
            scope.append(m.group(1))
            prev = None
            continue
        if PEND.match(line):
            if scope:
                scope.pop()
            prev = None
            continue
        m = INSTR.match(line)
        if not m:
            if line.strip() and not line.lstrip().startswith(';'):
                prev = None     # a label: something can jump in here
            continue
        op, operand = m.group(1), m.group(2)
        for ref in OPERAND_REF.finditer(operand):
            name, offset = ref.group(1), int(ref.group(2))
            if name.startswith('P8ZP_') or name.startswith('cx16.r'):
                continue
            if resolve(scope, name) == 'byte' and offset >= 1:
                findings.append((path, n, 'wide byte', f'{op}  {operand}', source))
        if prev and prev[0] == 'sta' and op == 'cmp' and prev[1] == operand and not operand.startswith('#'):
            findings.append((path, n, 'self cmp', f'sta/cmp  {operand}', source))
        prev = (op, operand)
    return findings


def main():
    findings = []
    for path in sys.argv[1:]:
        findings += scan(path)
    for path, n, kind, code, source in findings:
        print(f'{path}:{n}: {kind}: {code}\n    {source}')
    print(f'{len(findings)} finding(s) in {len(sys.argv) - 1} file(s)')
    sys.exit(1 if findings else 0)


if __name__ == '__main__':
    main()
