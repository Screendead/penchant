#!/usr/bin/env python3
"""Render component previews to PNG in each theme, the way the design-system host shows them.

    docs/design-system/day-dial/tools/render-previews.py <out-dir> [Component ...]

The host injects tokens.json as CSS custom properties; this does the same, then
screenshots each preview.html with headless Google Chrome. With no component
names it renders every one.
"""

import json
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent / "project"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


def root_vars(tokens, theme):
    lines = [f"--{t['name']}: {t['value'][theme]};" for t in tokens["color"]["tokens"]]
    for family, stack in tokens["type"]["families"].items():
        lines.append(f"--font-{family}: {stack};")
    for group in ("spacing", "radius", "size"):
        lines += [f"--{t['name']}: {t['value']};" for t in tokens[group]["tokens"]]
    for t in tokens["shadow"]["tokens"]:
        value = t["value"][theme] if isinstance(t["value"], dict) else t["value"]
        lines.append(f"--{t['name']}: {value};")
    return ":root { " + " ".join(lines) + " }"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    tokens = json.loads((PROJECT / "tokens.json").read_text())
    names = sys.argv[2:] or sorted(p.name for p in (PROJECT / "components").iterdir() if (p / "preview.html").exists())
    for name in names:
        html = (PROJECT / "components" / name / "preview.html").read_text()
        height = 400
        if 'height=' in html.split("\n", 1)[0]:
            height = int(html.split("height=", 1)[1].split()[0]) + 40
        for theme in ("light", "dark"):
            page = out / f"{name}-{theme}.html"
            page.write_text(html.replace("<style>", f"<style>{root_vars(tokens, theme)}\n", 1))
            subprocess.run(
                [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", f"--window-size=1000,{height}",
                 f"--screenshot={out / f'{name}-{theme}.png'}", page.as_uri()],
                check=True, capture_output=True,
            )
            print(out / f"{name}-{theme}.png")


if __name__ == "__main__":
    main()
