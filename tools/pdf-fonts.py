#!/usr/bin/env python3
# Cuts the static weights the report PDF embeds from the bundled variable
# fonts: the pdf package reads only a variable font's default instance.
# Needs fontTools: python3 -m pip install fonttools
import pathlib

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

FONTS = pathlib.Path(__file__).resolve().parent.parent / 'assets' / 'fonts'
CUTS = [
    ('RedHatDisplay', 700, 'Bold'),
    ('RedHatText', 400, 'Regular'),
    ('RedHatText', 600, 'SemiBold'),
    ('RedHatMono', 400, 'Regular'),
    ('RedHatMono', 600, 'SemiBold'),
]

(FONTS / 'pdf').mkdir(exist_ok=True)
for family, weight, style in CUTS:
    font = TTFont(FONTS / f'{family}-Variable.ttf')
    static = instancer.instantiateVariableFont(
        font, {'wght': weight}, updateFontNames=True
    )
    static.save(FONTS / 'pdf' / f'{family}-{style}.ttf')
