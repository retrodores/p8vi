#!/usr/bin/env python3
"""The quick test tier: one or two suites per build, run side by side.

    quick.py [-j N] [--list] [JOB...]

The full suites (make test-c64, test-c128x, ...) take an hour or more for
every build.  This runs a few minutes' worth: for each build the suites
most likely to show a break, picked so that each problem the v0.4 full run
found would have shown here:

  - every build: delete-put (read, edit, save) on its runner;
  - the page-store builds: pages (a 150-line text over many pages), and
    with an REU the reu-in-use check (the pages are in the REU, not main
    RAM: p8vi-c64font's slots once stopped fitting and it quietly fell
    back);
  - p8vi-c64reu without an REU: marks (its 1.4 KB text needs more than
    one page of main RAM);
  - the C64 screen check, :set number and :d/:y on the host.

Each job has its own work directory (build/quick/JOB) and remote monitor
ports, so runs don't share files.  The MEGA65 jobs run one after the
other in one job (Xemus started together fight over one config file).
A job passes when its runners exit with 0; a failed job's output is in
build/quick/JOB.log.  It doesn't build anything: make quick does that.

Run the full suite of a build after changing it in a way these don't
reach, and all of them before a release (make release names them).
"""

import argparse
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

PY = [sys.executable, '-B']
VICE = 'tests/vice/edtest.py'
FONT = 'build/oscii.fnt'
LIMIT = ['--limit', '3000000000']


def jobs():
    """name -> list of commands; {work} and {port} are filled in per job"""
    vice = lambda *a: PY + [VICE, '--work', '{work}', '--port', '{port}', '-j', '2'] + list(a)
    return {
        'host': [PY + ['tests/cpm/cpmtest.py', '--host', '--work', '{work}', 'files', 'delete-put', 'marks'],
                 PY + ['tests/cpm/cpmtest.py', '--host', '--work', '{work}', 'number'],
                 PY + ['tests/cpm/cpmtest.py', '--host', '--work', '{work}', 'lines']],
        'cpm': [PY + ['tests/cpm/cpmtest.py', '--work', '{work}', 'files', 'delete-put']],
        'c64': [vice('files', '--prg', 'build/p8vi-c64.prg', 'delete-put', 'marks'),
                vice('screen', '--prg', 'build/p8vi-c64.prg', 'long-dd-mid', 'scroll-mixed')],
        'c64reu': [vice('files', '--prg', 'build/p8vi-c64reu.prg', '--reu', '512', *LIMIT, 'reu-in-use', 'pages'),
                   vice('files', '--prg', 'build/p8vi-c64reu.prg', 'marks')],
        'c64font': [vice('files', '--prg', 'build/p8vi-c64font.prg', '--font', FONT, '--reu', '512', *LIMIT,
                         'reu-in-use', 'pages', 'font')],
        'c64disk': [vice('files', '--prg', 'build/p8vi-c64disk.prg', '--paged', *LIMIT, 'delete-put', 'pages')],
        'c128': [vice('files', '--machine', 'c128', '--prg', 'build/p8vi-c128.prg', 'delete-put')],
        'c128x': [vice('files', '--machine', 'c128', '--paged', '--font', FONT, *LIMIT,
                       '--prg', 'build/p8vi-c128x.prg', 'delete-put', 'pages')],
        'c128reu': [vice('files', '--machine', 'c128', '--reu', '512', *LIMIT,
                         '--prg', 'build/p8vi-c128reu.prg', 'reu-in-use', 'pages'),
                    vice('files', '--machine', 'c128', '--paged', *LIMIT,
                         '--prg', 'build/p8vi-c128reu.prg', 'pages')],
        'pet32': [vice('files', '--machine', 'pet', '--prg', 'build/p8vi-pet32.prg', 'delete-put')],
        'plus4': [vice('files', '--machine', 'plus4', '--prg', 'build/p8vi-plus4.prg', 'delete-put')],
        'mega65': [PY + ['tests/mega65/edtest.py', '--work', '{work}', '--font', 'files', 'delete-put'],
                   PY + ['tests/mega65/edtest.py', '--work', '{work}', '--prg', 'build/p8vi-mega65dma.prg',
                         '--paged', '--font', 'files', 'pages']],
        'trs80': [PY + ['tests/trs80/trstest.py', '--work', '{work}', 'delete-put']],
        'trs80m4': [PY + ['tests/trs80/trstest.py', '--model', '4', '--work', '{work}', 'delete-put']],
        'trs80m4x': [PY + ['tests/trs80/trstest.py', '--model', '4x', '--work', '{work}', 'pages']],
    }


def run_job(name, cmds, port):
    work = os.path.join('build', 'quick', name)
    os.makedirs(work, exist_ok=True)
    start = time.time()
    ok = True
    with open(work + '.log', 'w') as log:
        for cmd in cmds:
            cmd = [c.format(work=work, port=port) for c in cmd]
            log.write('$ ' + ' '.join(cmd) + '\n')
            log.flush()
            r = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
            if r.returncode != 0:
                ok = False
    return name, ok, time.time() - start


def main():
    all_jobs = jobs()
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('names', nargs='*', help='only these jobs: ' + ' '.join(all_jobs))
    ap.add_argument('-j', type=int, default=6, help='jobs at once (default 6)')
    ap.add_argument('--list', action='store_true', help='show the jobs and their commands')
    args = ap.parse_args()
    bad = [n for n in args.names if n not in all_jobs]
    if bad:
        sys.exit('no such job: ' + ' '.join(bad) + ' (jobs: ' + ' '.join(all_jobs) + ')')
    names = args.names or list(all_jobs)
    if args.list:
        for n in names:
            for cmd in all_jobs[n]:
                print(f'{n}: ' + ' '.join(cmd[1:]))
        return
    start = time.time()
    failed = []
    with ThreadPoolExecutor(args.j) as pool:
        futures = [pool.submit(run_job, n, all_jobs[n], 7000 + 40 * i) for i, n in enumerate(names)]
        for f in futures:
            name, ok, secs = f.result()
            print(f'{name}: {"ok" if ok else "FAIL"} ({secs:.0f} s)' +
                  ('' if ok else f', see build/quick/{name}.log'), flush=True)
            if not ok:
                failed.append(name)
    print(f'quick: {len(names) - len(failed)} of {len(names)} jobs passed in {time.time() - start:.0f} s')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
