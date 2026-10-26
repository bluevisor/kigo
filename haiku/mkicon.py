"""Writes Kigo's Haiku vector icon (HVIF) from haiku/kigo.svg, and the resource
file around it.

usage: uv run --with shapely --with defusedxml python haiku/mkicon.py
       (rewrites haiku/Kigo.rdef and haiku/kigo.hvif)

kigo.svg is John's golden ginkgo leaf (2026-10-25). HVIF has paths, solid and
gradient fills, but no clipping, masks or strokes, so:
  - the outline, the silver edge (the outline moved down) and the stem end
    keep their exact cubic curves;
  - the folds and sheens, which the SVG clips to the outline, are flattened
    and intersected with the outline here (shapely);
  - linear and radial gradients carry over with their transforms and stop
    opacity;
  - strokes (sub-pixel bevel lines) and the stem's fade mask are dropped.
The SVG must stay in the subset this reads: absolute M/C/L/H/V/Z paths,
<use> of #leaf-outline, ellipses, userSpaceOnUse gradients.
"""
import math
import os
import re
import struct
import defusedxml.ElementTree as ET

from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

HERE = os.path.dirname(os.path.abspath(__file__))
SVG_NS = "{http://www.w3.org/2000/svg}"
XLINK = "{http://www.w3.org/1999/xlink}href"
SCALE = 64.0 / 1280.0   # SVG user space -> the 64-unit HVIF grid


# --- affine matrices: (a, b, c, d, e, f) maps x' = a x + c y + e, y' = b x + d y + f

def mul(m, n):
    a, b, c, d, e, f = m
    A, B, C, D, E, F = n
    return (a * A + c * B, b * A + d * B, a * C + c * D, b * C + d * D,
            a * E + c * F + e, b * E + d * F + f)


def translate(x, y):
    return (1, 0, 0, 1, x, y)


def scale(x, y=None):
    return (x, 0, 0, x if y is None else y, 0, 0)


def parse_transform(text):
    m = (1, 0, 0, 1, 0, 0)
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text or ""):
        v = [float(t) for t in re.split(r"[\s,]+", args.strip()) if t]
        if name == "translate":
            m = mul(m, translate(v[0], v[1] if len(v) > 1 else 0))
        elif name == "scale":
            m = mul(m, scale(v[0], v[1] if len(v) > 1 else v[0]))
        else:
            raise ValueError(f"unsupported transform {name}")
    return m


def apply(m, p):
    a, b, c, d, e, f = m
    return (a * p[0] + c * p[1] + e, b * p[0] + d * p[1] + f)


# --- paths: lists of closed subpaths, each [start, (c1, c2, end), ...]

def parse_path(d):
    tokens = re.findall(r"[MCLHVZmclhvz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    subpaths, current, pos, i, cmd = [], None, (0.0, 0.0), 0, None
    def num():
        nonlocal i
        i += 1
        return float(tokens[i - 1])
    while i < len(tokens):
        if tokens[i].isalpha():
            cmd = tokens[i]
            i += 1
            if cmd in "Zz":
                if current:
                    subpaths.append(current)
                current = None
                continue
        if cmd == "M":
            pos = (num(), num())
            current = [pos]
            cmd = "L"
        elif cmd == "C":
            c1 = (num(), num()); c2 = (num(), num()); pos = (num(), num())
            current.append((c1, c2, pos))
        elif cmd == "L":
            p = (num(), num())
            current.append((pos, p, p)); pos = p
        elif cmd == "H":
            p = (num(), pos[1]); current.append((pos, p, p)); pos = p
        elif cmd == "V":
            p = (pos[0], num()); current.append((pos, p, p)); pos = p
        else:
            raise ValueError(f"unsupported path command {cmd}")
    if current:
        subpaths.append(current)
    return subpaths


def transform_path(path, m):
    out = []
    for sub in path:
        new = [apply(m, sub[0])]
        for c1, c2, p in sub[1:]:
            new.append((apply(m, c1), apply(m, c2), apply(m, p)))
        out.append(new)
    return out


def flatten(path, steps=16):
    polys = []
    for sub in path:
        pts = [sub[0]]
        prev = sub[0]
        for c1, c2, p in sub[1:]:
            if c1 == prev and c2 == p:
                pts.append(p)
            else:
                for s in range(1, steps + 1):
                    t = s / steps
                    u = 1 - t
                    pts.append((u ** 3 * prev[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * p[0],
                                u ** 3 * prev[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * p[1]))
            prev = p
        polys.append(pts)
    return polys


def ellipse(cx, cy, rx, ry, steps=64):
    return [[(cx + rx * math.cos(2 * math.pi * k / steps), cy + ry * math.sin(2 * math.pi * k / steps))
             for k in range(steps)]]


# --- styles

def parse_color(text, opacity=1.0):
    text = text.strip()
    if text.startswith("#"):
        h = text[1:]
        if len(h) == 3:
            h = "".join(ch * 2 for ch in h)
        r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return (r, g, b, round(255 * opacity))
    raise ValueError(f"unsupported color {text}")


def gradient_style(el, extra_opacity=1.0):
    stops = []
    for stop in el.findall(SVG_NS + "stop"):
        offset = float(stop.get("offset", "0").rstrip("%") or 0)
        color = parse_color(stop.get("stop-color", "#000"),
                            float(stop.get("stop-opacity", "1")) * extra_opacity)
        stops.append((max(0, min(255, round(offset * 255))), color))
    g = parse_transform(el.get("gradientTransform"))
    if el.tag == SVG_NS + "linearGradient":
        p1 = (float(el.get("x1")), float(el.get("y1")))
        p2 = (float(el.get("x2")), float(el.get("y2")))
        p1, p2 = apply(g, p1), apply(g, p2)
        dx, dy = (p2[0] - p1[0]) * SCALE, (p2[1] - p1[1]) * SCALE
        mx, my = (p1[0] + p2[0]) / 2 * SCALE, (p1[1] + p2[1]) / 2 * SCALE
        # HVIF linear gradients run from x=-64 to x=64 in gradient space.
        matrix = (dx / 128, dy / 128, -dy / 128, dx / 128, mx, my)
        kind = 0
    else:
        cx, cy, r = float(el.get("cx")), float(el.get("cy")), float(el.get("r"))
        # HVIF circular gradients have radius 64 around the origin.
        matrix = mul(scale(SCALE), mul(g, mul(translate(cx, cy), scale(r / 64))))
        kind = 1
    return ("gradient", kind, matrix, stops)


def float24(value):
    if value == 0:
        return b"\0\0\0"
    bits = struct.unpack(">I", struct.pack(">f", value))[0]
    sign = bits >> 31
    exponent = ((bits >> 23) & 0xff) - 127
    mantissa = bits & 0x7fffff
    if exponent < -32 or exponent >= 32:
        return b"\0\0\0"
    short = (sign << 23) | ((exponent + 32) << 17) | (mantissa >> 6)
    return bytes([(short >> 16) & 0xff, (short >> 8) & 0xff, short & 0xff])


def encode_style(style):
    if style[0] == "solid":
        return bytes([0x01, *style[1]])
    _, kind, matrix, stops = style
    out = bytearray([0x02, kind, 0x02, len(stops)])   # flags: has transform
    for v in matrix:
        out += float24(v)
    for offset, color in stops:
        out += bytes([offset, *color])
    return bytes(out)


def coord(v):
    n = round((v + 128.0) * 102.0)
    assert 0 <= n < 0x8000, v
    return bytes([0x80 | (n >> 8), n & 0xff])


def encode_curve_path(sub):
    """A closed cubic path: per point x,y, in, out (HVIF's own curve form)."""
    start, segments = sub[0], sub[1:]
    if segments and segments[-1][2] == start:
        ends = [start] + [s[2] for s in segments[:-1]]
    else:
        segments = segments + [(segments[-1][2], start, start)]
        ends = [start] + [s[2] for s in segments[:-1]]
    n = len(ends)
    assert n < 256
    out = bytearray([0x02, n])   # closed, with curves
    for i, p in enumerate(ends):
        incoming = segments[i - 1][1]   # second control of the segment ending here
        outgoing = segments[i][0]       # first control of the segment leaving
        for x, y in (p, incoming, outgoing):
            out += coord(x * SCALE) + coord(y * SCALE)
    return bytes(out)


def encode_polygon(points):
    assert len(points) < 256, len(points)
    out = bytearray([0x0a, len(points)])   # closed, no curves
    for x, y in points:
        out += coord(x * SCALE) + coord(y * SCALE)
    return bytes(out)


def main():
    tree = ET.parse(os.path.join(HERE, "kigo.svg"))
    root = tree.getroot()
    defs = {el.get("id"): el for el in root.iter() if el.get("id")}
    outline_path = parse_path(defs["leaf-outline"].get("d"))
    outline_poly = Polygon(flatten(outline_path, 24)[0]).buffer(0)

    styles, paths, shapes = [], [], []

    def style_for(fill, opacity=1.0):
        if fill.startswith("url("):
            style = gradient_style(defs[fill[5:-1]], opacity)
        else:
            style = ("solid", parse_color(fill, opacity))
        styles.append(style)
        return len(styles) - 1

    def add_shape(style, encoded_paths):
        start = len(paths)
        paths.extend(encoded_paths)
        shapes.append((style, list(range(start, len(paths)))))

    def clipped(polys):
        geometry = Polygon(polys[0]).buffer(0).intersection(outline_poly)
        geometry = geometry.simplify(0.6, preserve_topology=True)
        pieces = getattr(geometry, "geoms", [geometry])
        encoded = []
        for piece in pieces:
            if piece.is_empty or piece.geom_type != "Polygon" or piece.area < 4:
                continue
            piece = orient(piece)
            for ring in [piece.exterior, *piece.interiors]:
                encoded.append(encode_polygon(list(ring.coords)[:-1]))
        return encoded

    def walk(el, transform, clip):
        tag = el.tag.replace(SVG_NS, "")
        m = mul(transform, parse_transform(el.get("transform")))
        clip = clip or bool(el.get("clip-path"))
        opacity = float(el.get("opacity", "1"))
        fill = el.get("fill")
        if tag == "g":
            for child in el:
                walk(child, m, clip)
            return
        if fill in (None, "none") or tag in ("title", "desc", "defs"):
            return
        if tag == "use":
            path = transform_path(outline_path, m)
            add_shape(style_for(fill, opacity), [encode_curve_path(path[0])])
        elif tag == "path":
            path = transform_path(parse_path(el.get("d")), m)
            if clip:
                encoded = clipped(flatten(path))
                if encoded:
                    add_shape(style_for(fill, opacity), encoded)
            else:
                add_shape(style_for(fill, opacity), [encode_curve_path(sub) for sub in path])
        elif tag == "ellipse":
            polys = ellipse(float(el.get("cx")), float(el.get("cy")), float(el.get("rx")), float(el.get("ry")))
            encoded = clipped(polys) if clip else [encode_polygon(polys[0])]
            if encoded:
                add_shape(style_for(fill, opacity), encoded)

    for child in root:
        if child.tag in (SVG_NS + "defs", SVG_NS + "title", SVG_NS + "desc"):
            continue
        walk(child, (1, 0, 0, 1, 0, 0), False)

    out = bytearray(b"ncif")
    out.append(len(styles))
    for style in styles:
        out += encode_style(style)
    out.append(len(paths))
    for path in paths:
        out += path
    out.append(len(shapes))
    for style, indices in shapes:
        out += bytes([0x0a, style, len(indices), *indices, 0x00])
    data = bytes(out)

    major, middle, minor = (open(os.path.join(HERE, "..", "VERSION")).read().strip().split(".") + ["0", "0"])[:3]
    hexdata = data.hex()
    lines = "\n".join(f'\t$"{hexdata[i:i + 64]}"' for i in range(0, len(hexdata), 64))
    rdef = f'''// Generated by haiku/mkicon.py from haiku/kigo.svg; edit those, not this.

resource app_signature "application/x-vnd.bluevisor-Kigo";

resource app_flags B_SINGLE_LAUNCH | B_BACKGROUND_APP;

resource app_version {{
	major  = {major},
	middle = {middle},
	minor  = {minor},
	variety = B_APPV_DEVELOPMENT,
	internal = 0,
	short_info = "Kigo",
	long_info = "A Spotlight and Raycast style launcher for Haiku"
}};

resource vector_icon array {{
{lines}
}};
'''
    open(os.path.join(HERE, "Kigo.rdef"), "w").write(rdef)
    open(os.path.join(HERE, "kigo.hvif"), "wb").write(data)
    print(f"{len(data)} bytes, {len(styles)} styles, {len(paths)} paths, {len(shapes)} shapes")


main()
