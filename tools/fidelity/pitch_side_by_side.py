# Builds the round-8 pitch images from the mock-up stills (docs/pitch/mockups/ui-overhaul/day-dial) and test/today_render_test.dart renders.
# Usage: python3 -I tools/fidelity/pitch_side_by_side.py <dir with stills-light.png, stills-dark.png and render/> [label for the built side]
import sys
from PIL import Image, ImageDraw, ImageFont
S = sys.argv[1]
BUILT = sys.argv[2] if len(sys.argv) > 2 else 'Built (master)'
def panel(src, i):
    x0 = [50, 494, 938][i]
    return Image.open(f'{S}/{src}').convert('RGB').crop((x0, 340, x0 + 410, 1200))
def side(left, right, out, labels):
    h = 860
    r = right.convert('RGB'); r = r.resize((round(r.width * h / r.height), h), Image.LANCZOS)
    l = left.resize((round(left.width * h / left.height), h), Image.LANCZOS)
    pad, top = 24, 44
    W = l.width + r.width + pad * 3
    c = Image.new('RGB', (W, h + top + pad), (226, 223, 216))
    c.paste(l, (pad, top)); c.paste(r, (pad * 2 + l.width, top))
    d = ImageDraw.Draw(c)
    try: f = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 22)
    except Exception: f = ImageFont.load_default()
    d.text((pad, 12), labels[0], fill=(20, 20, 20), font=f)
    d.text((pad * 2 + l.width, 12), labels[1], fill=(20, 20, 20), font=f)
    c.save(f'{S}/{out}', optimize=True)
side(panel('stills-dark.png', 1), Image.open(f'{S}/render/today-clear-dark.png'), 'r8-clear-dark.png', ('Mock-up: clear day', BUILT))
side(panel('stills-light.png', 1), Image.open(f'{S}/render/today-sparse-light.png'), 'r8-sparse-light.png', ('Mock-up: sparse day', BUILT))
panel('stills-light.png', 2).save(f'{S}/r8-coach.png', optimize=True)
s = Image.open(f'{S}/render/today-split-1200-light.png').convert('RGB'); s.resize((1200, 800), Image.LANCZOS).save(f'{S}/r8-split-1200.png', optimize=True)
c = Image.open(f'{S}/render/today-clear-light.png').convert('RGB'); c.resize((390, 844), Image.LANCZOS).save(f'{S}/r8-clear-light.png', optimize=True)
