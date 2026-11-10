#!/usr/bin/env python3
"""Sets each tracked file's mtime from its blob hash.

A fresh checkout stamps every file with the clone time, so Xcode's restored build database saw all of ios/ as changed
and recompiled the asset catalogs, storyboards and Swift on every CI run. Same content, same mtime; changed content, a
different one. CI only: it rewrites mtimes in the working tree.
"""
import os
import subprocess

START = 946684800  # 2000-01-01, before any real edit, so tools comparing to now never see a future file.
SPAN = 20 * 365 * 86400

out = subprocess.run(['git', 'ls-files', '-s', '-z'], check=True, capture_output=True).stdout
for entry in out.split(b'\0'):
    if not entry:
        continue
    meta, path = entry.split(b'\t', 1)
    mode, sha, _ = meta.split(b' ')
    if mode == b'120000' or mode == b'160000':
        continue
    t = START + int(sha[:12], 16) % SPAN
    try:
        os.utime(path, (t, t))
    except FileNotFoundError:
        pass
