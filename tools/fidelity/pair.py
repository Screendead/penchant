"""Puts each mock-up shot beside the app's render of the same state.

    python3 tools/fidelity/pair.py <root> [label] [out-subdir]

Reads <root>/mock/mock-<state>.png and <root>/app/app-<state>.png (both
390x844 at 3x) and writes <root>/<out-subdir>/<state>.png, mock-up left.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

root = sys.argv[1]
label = sys.argv[2] if len(sys.argv) > 2 else "App"
out_dir = os.path.join(root, sys.argv[3] if len(sys.argv) > 3 else "pairs")
os.makedirs(out_dir, exist_ok=True)
font = None
for f in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/System/Library/Fonts/Helvetica.ttc"]:
    if os.path.exists(f):
        font = ImageFont.truetype(f, 54)
        break
for m in sorted(glob.glob(f"{root}/mock/mock-*.png")):
    name = os.path.basename(m)[5:-4]
    a = os.path.join(root, "app", f"app-{name}.png")
    if not os.path.exists(a):
        continue
    A, B = Image.open(m).convert("RGBA"), Image.open(a).convert("RGBA")
    dark = name.endswith("dark")
    bg = (40, 40, 40, 255) if dark else (225, 222, 215, 255)
    fg = (240, 240, 240) if dark else (20, 20, 20)
    W, H, gap, top = A.width, A.height, 60, 110
    out = Image.new("RGBA", (W * 2 + gap * 3, H + top + gap), bg)
    out.alpha_composite(A, (gap, top))
    out.alpha_composite(B, (W + gap * 2, top))
    d = ImageDraw.Draw(out)
    d.text((gap, 30), f"Mock-up ({name})", fill=fg, font=font)
    d.text((W + gap * 2, 30), label, fill=fg, font=font)
    out.convert("RGB").save(os.path.join(out_dir, f"{name}.png"))
    print(name)
