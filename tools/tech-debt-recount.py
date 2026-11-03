#!/usr/bin/env python3
"""Rewrites tech-debt/README.md counts from its entry lines.

Resolves git conflict markers by keeping both sides' entries, drops entries
whose file is gone, recomputes the total and per-section counts, and exits
non-zero if a report file on disk has no entry.

    tools/tech-debt-recount.py            # rewrite in place
    tools/tech-debt-recount.py --check    # exit 1 if a rewrite would change it
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "tech-debt"
README = ROOT / "README.md"
ENTRY = re.compile(r"^- \*\*(critical|high|medium|low)\*\* — \[.*\]\(([^)]+\.md)\)$")
SECTION = re.compile(r"^## (.+) \((\d+)\)$")
TOTAL = re.compile(r"^\*\*\d+ issues: .*\*\*$")
SEVERITIES = ("critical", "high", "medium", "low")


def resolve_conflicts(lines):
    out, side, seen_in_block = [], None, set()
    for line in lines:
        if line.startswith("<<<<<<< "):
            side, seen_in_block = "ours", set()
        elif line.startswith("=======") and side:
            side = "theirs"
        elif line.startswith(">>>>>>> ") and side:
            side = None
        elif side is None:
            out.append(line)
        elif ENTRY.match(line):
            if line not in seen_in_block:
                seen_in_block.add(line)
                out.append(line)
        elif side == "ours" or not (SECTION.match(line) or TOTAL.match(line)):
            if line not in seen_in_block:
                seen_in_block.add(line)
                out.append(line)
    return out


def main():
    original = README.read_text()
    lines = resolve_conflicts(original.split("\n"))

    kept, listed, dropped = [], set(), []
    for line in lines:
        m = ENTRY.match(line)
        if m:
            if not (ROOT / m.group(2)).is_file():
                dropped.append(m.group(2))
                continue
            if m.group(2) in listed:
                continue
            listed.add(m.group(2))
        kept.append(line)

    totals = dict.fromkeys(SEVERITIES, 0)
    section_at, counts = None, {}
    for i, line in enumerate(kept):
        if SECTION.match(line):
            section_at = i
            counts[i] = 0
        m = ENTRY.match(line)
        if m:
            totals[m.group(1)] += 1
            counts[section_at] += 1
    empty = []
    for i, n in counts.items():
        name = SECTION.match(kept[i]).group(1)
        kept[i] = f"## {name} ({n})"
        if n == 0:
            empty.append(name)
    total = sum(totals.values())
    summary = ", ".join(f"{totals[s]} {s}" for s in SEVERITIES)
    kept = [f"**{total} issues: {summary}.**" if TOTAL.match(l) else l for l in kept]

    on_disk = {p.relative_to(ROOT).as_posix() for p in ROOT.rglob("*.md") if p != README}
    unlisted = sorted(on_disk - listed)

    result = "\n".join(kept)
    for path in dropped:
        print(f"dropped (file gone): {path}")
    for name in empty:
        print(f"empty section: {name}")
    for path in unlisted:
        print(f"unlisted report: {path}", file=sys.stderr)
    print(f"{total} issues: {summary}")

    if "--check" in sys.argv:
        sys.exit(1 if result != original or unlisted else 0)
    README.write_text(result)
    sys.exit(1 if unlisted else 0)


if __name__ == "__main__":
    main()
