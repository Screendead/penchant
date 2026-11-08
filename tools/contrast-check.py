#!/usr/bin/env python3
"""Check the Day Dial colour pairs against WCAG 2.2 contrast minimums.

    tools/contrast-check.py [--tokens PATH] [--pairs PATH] [--report | --failures] [--was]

Reads a design-system tokens.json (color.themes and color.tokens, each value a
#RRGGBB or #RRGGBBAA per theme) and a pair file, and checks every pair in
every theme. Exits 1 if any pair is under its minimum.

A pair file is {"pairs": [{"fg", "bg", "min", "kind", "purpose"}, ...]}. Each
of fg and bg is a layer or a list of layers, topmost first. A layer is a token
name, optionally with an opacity multiplier ("spoke@0.45"), or
"mix(token,percent)" for CSS color-mix(in srgb, token percent%, <next layer>).
The fg layers are painted over the bg layers; the bottom bg layer must be
opaque. A pair may name "themes" to limit it to some of them. A pair with
"per_habit": true stands for five, with {n} in its layers read as 1 to 5. A
pair's optional "was" ({"fg", "bg"}) is what it painted before a change;
--was checks those instead, for a before-and-after report. A pair of kind
"decoration" has no "min": its ratio is reported and never fails.

Compositing is source-over in gamma-encoded sRGB, the way browsers and Flutter
paint. Each pair is scored at the worse of the exact blend and the blend
rounded to 8 bits, so a pair can't pass on a value no screen shows. Luminance
and ratio follow WCAG 2.2 (relative luminance, (L1 + 0.05) / (L2 + 0.05)),
unrounded: 2.99 fails a 3:1 minimum.
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIR = ROOT / "docs" / "design-system" / "day-dial" / "project"


def parse_hex(value):
    digits = value.lstrip("#")
    if not re.fullmatch(r"[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", digits):
        raise ValueError(f"not a #RRGGBB or #RRGGBBAA colour: {value}")
    rgb = tuple(int(digits[i : i + 2], 16) for i in (0, 2, 4))
    alpha = int(digits[6:8], 16) / 255 if len(digits) == 8 else 1.0
    return rgb, alpha


def load_tokens(path):
    color = json.loads(Path(path).read_text())["color"]
    themes = [t["id"] for t in color["themes"]]
    tokens = {}
    for token in color["tokens"]:
        tokens[token["name"]] = {t: parse_hex(token["value"][t]) for t in themes}
    return themes, tokens


LAYER = re.compile(r"^(?:mix\((?P<mix>\w+),\s*(?P<pct>[\d.]+)\)|(?P<name>\w+)(?:@(?P<op>[\d.]+))?)$")


def layer_colour(layer, tokens, theme):
    match = LAYER.match(layer.strip())
    if not match:
        raise ValueError(f"bad layer: {layer}")
    if match["mix"]:
        rgb, alpha = tokens[match["mix"]][theme]
        return rgb, alpha * float(match["pct"]) / 100
    rgb, alpha = tokens[match["name"]][theme]
    return rgb, alpha * (float(match["op"]) if match["op"] else 1.0)


def as_layers(side):
    return [side] if isinstance(side, str) else list(side)


def flatten(layers, tokens, theme, rounded):
    """Composites layers (topmost first) and returns an opaque sRGB triple."""
    stack = [layer_colour(l, tokens, theme) for l in layers]
    base_rgb, base_alpha = stack[-1]
    if base_alpha < 1:
        raise ValueError(f"bottom layer is not opaque in {theme}: {layers[-1]}")
    out = [float(c) for c in base_rgb]
    for rgb, alpha in reversed(stack[:-1]):
        out = [alpha * f + (1 - alpha) * b for f, b in zip(rgb, out)]
        if rounded:
            out = [math.floor(c + 0.5) for c in out]
    return out


def luminance(rgb):
    def linear(c):
        c = c / 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (linear(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def contrast(pair, tokens, theme):
    fg, bg = as_layers(pair["fg"]), as_layers(pair["bg"])
    worst = None
    for rounded in (False, True):
        r = ratio(flatten(fg + bg, tokens, theme, rounded), flatten(bg, tokens, theme, rounded))
        worst = r if worst is None else min(worst, r)
    return worst


def expand(pairs, was):
    for pair in pairs:
        if was and "was" in pair:
            pair = {**pair, **pair["was"]}
        for n in range(1, 6) if pair.get("per_habit") else [None]:
            def sub(side):
                return [l.replace("{n}", str(n)) if n else l for l in as_layers(side)]

            yield {**pair, "fg": sub(pair["fg"]), "bg": sub(pair["bg"]),
                   "purpose": pair.get("purpose", "").replace("{n}", str(n) if n else "N")}


def label(side):
    return " over ".join(as_layers(side))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--tokens", default=DEFAULT_DIR / "tokens.json")
    parser.add_argument("--pairs", default=DEFAULT_DIR / "contrast-pairs.json")
    parser.add_argument("--report", action="store_true", help="print every pair as a Markdown table")
    parser.add_argument("--failures", action="store_true", help="print only the failing pairs")
    parser.add_argument("--was", action="store_true", help="check what each pair painted before its last change")
    args = parser.parse_args()

    themes, tokens = load_tokens(args.tokens)
    pairs = list(expand(json.loads(Path(args.pairs).read_text())["pairs"], args.was))

    failures = 0
    rows = []
    for pair in pairs:
        for theme in pair.get("themes", themes):
            r = contrast(pair, tokens, theme)
            if pair.get("kind") == "decoration":
                if "min" in pair:
                    raise ValueError(f"a decoration pair has no minimum: {pair['purpose']}")
                ok = True
            else:
                ok = r >= pair["min"]
            failures += not ok
            rows.append((theme, pair, r, ok))

    if args.report or args.failures:
        print("| Theme | Foreground | Background | Ratio | Min | Kind | Purpose |")
        print("|---|---|---|---|---|---|---|")
        for theme, pair, r, ok in rows:
            if args.failures and ok:
                continue
            mark = "" if ok else " FAIL"
            print(
                f"| {theme} | {label(pair['fg'])} | {label(pair['bg'])} | {r:.2f}{mark} | {pair.get('min', '-')} "
                f"| {pair.get('kind', '')} | {pair.get('purpose', '')} |"
            )
    decorative = sum(pair.get("kind") == "decoration" for _, pair, _, _ in rows)
    print(f"{len(rows) - decorative} checks, {failures} under the minimum; {decorative} decoration, unchecked", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
