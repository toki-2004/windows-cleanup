#!/usr/bin/env python3
"""Read-only disk cleanup scanner (companion to windows-cleanup.ps1).

Walks one drive once and reports what is worth reviewing before cleaning:

  * size of every top-level folder, largest first
  * folders whose name looks like junk (cache / temp / log / update / old ...)
    above a size threshold - these are cleanup candidates, not orders to delete
  * side-by-side version folders of the same app (only the newest is in use)
  * large loose files sitting in the drive root
  * what the recycle bin of that drive still holds

Nothing is deleted or modified. Directory junctions and symlinks are never
followed, so a linked folder is not counted twice.

Usage:
  python scan-drive.py D:
  python scan-drive.py D: --min-mb 200
  python scan-drive.py --self-check
"""

import datetime
import os
import re
import shutil
import struct
import sys

REPARSE = 0x400
GB = 1024 ** 3
DEFAULT_MIN_MB = 50

# Name-substring heuristic. Review the hits, never delete from this list blindly.
JUNK_NAME = re.compile(
    r'(cache|caches|temp|tmp|log|logs|crash|dumps?|scratch|shadercache|htmlcache|'
    r'gpucache|httpcache|thumbs?|update|updates|pending|backup|bak|old|reports?)',
    re.I)
VERSION = re.compile(r'\d+(\.\d+)+')
# Folders where same-looking "versions" are per-version runtime data, not stale
# copies of an app: deleting the older ones breaks those instances/projects.
NO_VERSION_HINT = {'libraries', 'versions', 'saves', 'mods', 'assets', 'runtime',
                   'node_modules', '.git', 'venv', 'site-packages', 'plugins',
                   'screenshots', 'logs', 'config'}

TOPS = []
JUNK = []
VERGROUPS = []
LINKS = []
ROOTFILES = []
MIN = DEFAULT_MIN_MB * 1024 ** 2


def version_key(name):
    """Sort key for a version-like folder name; None if it does not look like one.

    Numeric parts, not string order: '1.9' must rank below '1.10'. Names longer
    than 24 chars are ignored - real version folders are short, while files such
    as 'report 2026-09 (1).txt' style folders would match by accident.
    """
    if len(name) > 24:
        return None
    m = VERSION.search(name)
    if not m or m.start() > 4:
        return None
    parts = [int(x) for x in m.group(0).split('.')]
    parts += [0] * (4 - len(parts))
    return tuple(parts[:4])


def walk(path, level, inside_junk):
    """Return the total size of path; collect junk dirs and version groups."""
    total = 0
    child = {}
    try:
        it = os.scandir(path)
    except OSError:
        return 0
    with it:
        for e in it:
            try:
                if e.is_dir(follow_symlinks=False):
                    st = e.stat(follow_symlinks=False)
                    if e.is_symlink() or (st.st_file_attributes & REPARSE):
                        LINKS.append(e.path)
                        continue
                    if not inside_junk and JUNK_NAME.search(e.name):
                        size = walk(e.path, level + 1, True)
                        JUNK.append((size, e.path))
                    else:
                        size = walk(e.path, level + 1, inside_junk)
                    child[e.name] = size
                    total += size
                elif e.is_file(follow_symlinks=False):
                    total += e.stat(follow_symlinks=False).st_size
            except OSError:
                pass
    if level == 1:
        TOPS.append((total, path))
    versions = [(version_key(n), n, s) for n, s in child.items()]
    versions = [v for v in versions if v[0]]
    if len(versions) >= 2 and os.path.basename(path).lower() not in NO_VERSION_HINT:
        versions.sort()
        old = versions[:-1]
        old_total = sum(v[2] for v in old)
        if old_total >= MIN:
            VERGROUPS.append((old_total, path, versions[-1][1], old))
    return total


def parse_recycle_i(raw):
    """Parse a $I record: (deleted size, deleted at, original path)."""
    if len(raw) < 28:
        return None
    size = struct.unpack('<Q', raw[8:16])[0]
    ticks = struct.unpack('<Q', raw[16:24])[0]
    try:
        when = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=ticks / 10)
    except OverflowError:
        when = None
    path = raw[28:].decode('utf-16-le', 'replace').split('\x00')[0]
    return size, when, path


def dir_size(path):
    """Size of a folder, without collecting anything and without following links."""
    total = 0
    try:
        it = os.scandir(path)
    except OSError:
        return 0
    with it:
        for e in it:
            try:
                if e.is_dir(follow_symlinks=False):
                    st = e.stat(follow_symlinks=False)
                    if e.is_symlink() or (st.st_file_attributes & REPARSE):
                        continue
                    total += dir_size(e.path)
                elif e.is_file(follow_symlinks=False):
                    total += e.stat(follow_symlinks=False).st_size
            except OSError:
                pass
    return total


def recycle_bin(root):
    """Return (on-disk size, item count, [(size, deleted at, original path)])."""
    rb = os.path.join(root, '$Recycle.Bin')
    if not os.path.isdir(rb):
        return 0, 0, []
    total = 0
    count = 0
    items = []
    for sid in os.listdir(rb):
        folder = os.path.join(rb, sid)
        try:
            names = os.listdir(folder)
        except OSError:            # another user's bin, needs admin
            continue
        for name in names:
            full = os.path.join(folder, name)
            if name.startswith('$I'):
                try:
                    with open(full, 'rb') as f:
                        meta = parse_recycle_i(f.read())
                except OSError:
                    meta = None
                if meta:
                    items.append((meta[0], meta[1], meta[2]))
            elif name.startswith('$R'):
                count += 1
                if os.path.isdir(full):
                    total += dir_size(full)
                else:
                    try:
                        total += os.stat(full).st_size
                    except OSError:
                        pass
    return total, count, items


def gb(n):
    return n / GB


def self_check():
    assert version_key('12.1.0.28043') > version_key('12.1.0.20784')
    assert version_key('app-1.13.0.5561') > version_key('app-1.9.0.1')
    assert version_key('tools') is None
    assert version_key('6-11(0.7-1498662)_split_result') is None
    assert JUNK_NAME.search('Cache') and JUNK_NAME.search('logs')
    assert not JUNK_NAME.search('Documents')
    raw = (b'\x02' * 8 + struct.pack('<Q', 4096) + struct.pack('<Q', 0) +
           struct.pack('<I', 0) + 'D:\\Download\\a.zip'.encode('utf-16-le'))
    size, _, path = parse_recycle_i(raw)
    assert size == 4096 and path == 'D:\\Download\\a.zip', parse_recycle_i(raw)
    print('self-check OK')
    return 0


def main(argv):
    global MIN
    if '--self-check' in argv:
        return self_check()
    args = [a for a in argv if not a.startswith('-') and a not in ('', '.')]
    root = (args[0] if args else 'D:').rstrip('\\/') + '\\'
    if not os.path.isdir(root):
        print('not a drive/folder: ' + root)
        return 2
    if '--min-mb' in argv:
        MIN = int(argv[argv.index('--min-mb') + 1]) * 1024 ** 2

    try:
        sys.stdout.reconfigure(errors='replace')
    except Exception:
        pass

    print('Scanning ' + root + ' (read-only) ...')
    for e in os.scandir(root):
        try:
            if e.is_file(follow_symlinks=False):
                size = e.stat(follow_symlinks=False).st_size
                if size >= MIN:
                    ROOTFILES.append((size, e.path))
            elif e.is_dir(follow_symlinks=False):
                if e.is_symlink() or (e.stat(follow_symlinks=False).st_file_attributes & REPARSE):
                    LINKS.append(e.path)
                    continue
                walk(e.path, 1, False)
        except OSError:
            pass

    free = 0
    try:
        free = shutil.disk_usage(root).free
    except OSError:
        pass
    print('Free on ' + root + ': ' + format(gb(free), '.1f') + ' GB')

    print('\n== top-level folders ==')
    for size, path in sorted(TOPS, reverse=True):
        print(format(gb(size), '9.2f') + ' GB  ' + path)

    print('\n== junk-named folders >= ' + str(MIN // 1024 ** 2) + ' MB (review, then decide) ==')
    for size, path in sorted(JUNK, reverse=True):
        if size >= MIN:
            print(format(gb(size), '9.2f') + ' GB  ' + path)

    print('\n== outdated version folders (newest of each set is kept) ==')
    print('   hint only: user data and game instance folders often look like')
    print('   versions - confirm the app really keeps every version around')
    for old_total, parent, keep, old in sorted(VERGROUPS, reverse=True):
        print(format(gb(old_total), '9.2f') + ' GB  ' + parent + '   keep ' + keep)
        for _, name, size in sorted(old, key=lambda x: -x[2]):
            print('           ' + format(gb(size), '9.2f') + ' GB  ' + name)

    print('\n== loose files in the drive root >= ' + str(MIN // 1024 ** 2) + ' MB ==')
    for size, path in sorted(ROOTFILES, reverse=True):
        print(format(gb(size), '9.2f') + ' GB  ' + path)

    total, count, items = recycle_bin(root)
    print('\n== recycle bin ==')
    print(format(gb(total), '9.2f') + ' GB in ' + str(count) + ' items (other users\' bins need admin)')
    for size, when, path in sorted(items, reverse=True)[:15]:
        stamp = when.strftime('%Y-%m-%d') if when else '?'
        print('   ' + format(gb(size), '8.3f') + ' GB  ' + stamp + '  ' + path)

    if LINKS:
        print('\n== junctions/symlinks skipped (not followed, not counted) ==')
        for path in LINKS[:20]:
            print('   ' + path)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
