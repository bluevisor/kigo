"""Bakes 季 (ki, season) from the Yuji Boku brush font into Kigo's sources,
so every port draws the same calligraphy without the font installed.

    uv run --with fonttools python tools/mkki.py YujiBoku-Regular.ttf

Yuji Boku: https://fonts.google.com/specimen/Yuji+Boku (SIL OFL 1.1).
The outline lands in a unit square, y down, centered, as a flat list:
0 x y = move, 1 x y = line, 2 x1 y1 x2 y2 x y = cubic, 3 = close.
"""
import os
import sys

from fontTools.pens.basePen import BasePen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class Pen(BasePen):
    def __init__(self, glyphs):
        super().__init__(glyphs)
        self.ops = []

    def _moveTo(self, p):
        self.ops.append((0, p))

    def _lineTo(self, p):
        self.ops.append((1, p))

    def _curveToOne(self, a, b, c):
        self.ops.append((2, a, b, c))

    def _closePath(self):
        self.ops.append((3,))


font = TTFont(sys.argv[1])
glyphs = font.getGlyphSet()
name = font.getBestCmap()[ord("季")]
bounds = BoundsPen(glyphs)
glyphs[name].draw(bounds)
x0, y0, x1, y1 = bounds.bounds
size = max(x1 - x0, y1 - y0)
dx = (size - (x1 - x0)) / 2 - x0
dy = (size - (y1 - y0)) / 2 + y1
pen = Pen(glyphs)
glyphs[name].draw(pen)

flat = []
for op in pen.ops:
    flat.append(op[0])
    for x, y in op[1:]:
        flat += [round((x + dx) / size, 4), round((dy - y) / size, 4)]


def numbers(per_line, fmt):
    text = [fmt(v) for v in flat]
    return ",\n".join("\t" + ", ".join(text[i:i + per_line]) for i in range(0, len(text), per_line))


header = "季 (ki, season) in Yuji Boku (SIL OFL 1.1), from tools/mkki.py."
with open(os.path.join(ROOT, "src/KiGlyph.h"), "w") as f:
    f.write("// %s\n// 0 x y move, 1 x y line, 2 x1 y1 x2 y2 x y cubic, 3 close; unit square, y down.\n"
            "#ifndef KI_GLYPH_H\n#define KI_GLYPH_H\n\nstatic const float kKiGlyph[] = {\n%s\n};\n\n#endif\n"
            % (header, numbers(12, lambda v: "%gf" % v if isinstance(v, float) else str(v))))
with open(os.path.join(ROOT, "mac/Sources/Kigo/KiGlyph.swift"), "w") as f:
    f.write("// %s\n// 0 x y move, 1 x y line, 2 x1 y1 x2 y2 x y cubic, 3 close; unit square, y down.\n"
            "let kiGlyph: [Double] = [\n%s,\n]\n" % (header, numbers(12, str)))
with open(os.path.join(ROOT, "linux/kigo/ki_glyph.py"), "w") as f:
    f.write('"""%s\n\n0 x y move, 1 x y line, 2 x1 y1 x2 y2 x y cubic, 3 close; unit square, y down."""\n'
            "KI_GLYPH = (\n%s,\n)\n" % (header, numbers(12, str)))
print(len(pen.ops), "ops")
