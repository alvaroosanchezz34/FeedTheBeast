#!/usr/bin/env python3
"""Previsualización APROXIMADA de criaturas y mapa a partir de la geometría exportada.

No es el renderizador de Roblox: es un rasterizador mínimo (sombreado plano, sin sombras,
sin partículas ni auras) que sirve para comprobar siluetas, proporciones, caras, colores de
mutación y la distribución del mapa sin abrir Studio.

    lune run tools/preview/run && python3 tools/preview/render.py
    -> build/preview/creatures.png, creatures_eat.png, world.png
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "build", "preview")
SS = 2  # supersampling


def font(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    ):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def cframe(c):
    pos = np.array(c[0:3], dtype=float)
    rot = np.array(c[3:12], dtype=float).reshape(3, 3)
    return pos, rot


def box_mesh(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    v = np.array([[x, y, z] for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)])
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    tris = []
    for a, b, c, d in quads:
        tris += [(a, b, c), (a, c, d)]
    return v, tris


def wedge_mesh(sx, sy, sz):
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    # Base completa, pared trasera (+Z) completa, rampa de abajo-delante a arriba-detrás.
    v = np.array([
        [-hx, -hy, -hz], [hx, -hy, -hz], [-hx, -hy, hz], [hx, -hy, hz], [-hx, hy, hz], [hx, hy, hz],
    ])
    tris = [(0, 1, 3), (0, 3, 2), (2, 3, 5), (2, 5, 4), (0, 4, 5), (0, 5, 1), (0, 2, 4), (1, 5, 3)]
    return v, tris


def cylinder_mesh(length, diameter, n=18):
    r, h = diameter / 2, length / 2
    v = []
    for x in (-h, h):
        for i in range(n):
            a = 2 * math.pi * i / n
            v.append([x, math.cos(a) * r, math.sin(a) * r])
    v += [[-h, 0, 0], [h, 0, 0]]
    tris = []
    for i in range(n):
        j = (i + 1) % n
        tris += [(i, j, n + j), (i, n + j, n + i), (2 * n, j, i), (2 * n + 1, n + i, n + j)]
    return np.array(v), tris


def sphere_mesh(diameter, rings=9, segs=16):
    r = diameter / 2
    v = [[0, r, 0]]
    for i in range(1, rings):
        phi = math.pi * i / rings
        for j in range(segs):
            th = 2 * math.pi * j / segs
            v.append([r * math.sin(phi) * math.cos(th), r * math.cos(phi), r * math.sin(phi) * math.sin(th)])
    v.append([0, -r, 0])
    tris = []
    for j in range(segs):
        tris.append((0, 1 + j, 1 + (j + 1) % segs))
    for i in range(rings - 2):
        for j in range(segs):
            a = 1 + i * segs + j
            b = 1 + i * segs + (j + 1) % segs
            c = a + segs
            d = b + segs
            tris += [(a, c, d), (a, d, b)]
    last = len(v) - 1
    base = 1 + (rings - 2) * segs
    for j in range(segs):
        tris.append((last, base + (j + 1) % segs, base + j))
    return np.array(v), tris


def part_mesh(part):
    sx, sy, sz = part["size"]
    shape = part["shape"]
    if shape == "Ball":
        return sphere_mesh(min(sx, sy, sz))
    if shape == "Cylinder":
        return cylinder_mesh(sx, min(sy, sz))
    if shape == "Wedge":
        return wedge_mesh(sx, sy, sz)
    return box_mesh(sx, sy, sz)


def look_at(eye, target):
    forward = target - eye
    forward /= np.linalg.norm(forward)
    right = np.cross(forward, np.array([0.0, 1.0, 0.0]))
    if np.linalg.norm(right) < 1e-6:
        right = np.array([1.0, 0.0, 0.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    return right, up, forward


def render(parts, eye, target, span, size, background, light=(-0.45, 0.8, -0.4)):
    """Proyección ortográfica; `span` = unidades del mundo que caben a lo alto/ancho."""
    w = h = size * SS
    image = Image.new("RGBA", (w, h), background)
    right, up, forward = look_at(np.array(eye, float), np.array(target, float))
    light = np.array(light, float)
    light /= np.linalg.norm(light)
    scale = w / span
    polys = []
    for part in parts:
        pos, rot = cframe(part["cf"])
        verts, tris = part_mesh(part)
        world = verts @ rot.T + pos
        rel = world - np.array(target, float)
        px = rel @ right
        py = rel @ up
        pz = rel @ forward
        base = np.array(part["color"], float)
        neon = part["material"] == "Neon"
        alpha = 1.0 - min(0.9, part.get("transparency", 0))
        for a, b, c in tris:
            n = np.cross(world[b] - world[a], world[c] - world[a])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                continue
            n /= ln
            if np.dot(n, forward) > 0:
                continue  # cara trasera
            if neon:
                shade = 1.08
            else:
                shade = 0.52 + 0.5 * max(0.0, float(np.dot(n, light)))
            col = np.clip(base * shade, 0, 1)
            depth = (pz[a] + pz[b] + pz[c]) / 3
            pts = [(w / 2 + px[i] * scale, h / 2 - py[i] * scale) for i in (a, b, c)]
            polys.append((depth, pts, (int(col[0] * 255), int(col[1] * 255), int(col[2] * 255), int(alpha * 255))))
    polys.sort(key=lambda p: -p[0])
    draw = ImageDraw.Draw(image, "RGBA")
    for _, pts, col in polys:
        draw.polygon(pts, fill=col)
    return image.resize((size, size), Image.LANCZOS)


RARITY = {
    "Common": (190, 196, 204), "Uncommon": (96, 214, 110), "Rare": (72, 150, 255),
    "Epic": (184, 92, 255), "Legendary": (255, 176, 46), "Secret": (255, 70, 140),
}
MUTATION = {"NORMAL": (255, 255, 255), "GOLDEN": (255, 200, 50), "ELECTRIC": (70, 220, 255), "COSMIC": (190, 110, 255)}


def creature_view(c, size):
    h = c["height"]
    r = c["radius"]
    center = (0, h * 0.5, 0)
    direction = np.array([-0.42, 0.22, -1.0])
    direction /= np.linalg.norm(direction)
    eye = np.array(center) + direction * 30
    span = max(h, r * 2.4) * 1.25
    return render(c["parts"], eye, center, span, size, (33, 38, 64, 255))


def creature_sheet(creatures, pose, path, cell=250):
    species = []
    for c in creatures:
        if c["species"] not in species:
            species.append(c["species"])
    mutations = ["NORMAL", "GOLDEN", "ELECTRIC", "COSMIC"] if pose == "idle" else ["NORMAL"]
    views = [c for c in creatures if c["pose"] == pose]
    cols, rows = len(species), len(mutations)
    pad, head, left = 8, 46, 96
    sheet = Image.new("RGB", (left + cols * (cell + pad) + pad, head + rows * (cell + pad) + pad + 22), (23, 26, 43))
    draw = ImageDraw.Draw(sheet)
    f_big, f_small = font(18), font(12)
    for ci, sid in enumerate(species):
        info = next(c for c in views if c["species"] == sid)
        x = left + pad + ci * (cell + pad)
        draw.text((x + cell / 2, 14), info["name"].upper(), font=f_big, fill=RARITY[info["rarity"]], anchor="mm")
        draw.text((x + cell / 2, 34), info["rarity"], font=f_small, fill=(176, 184, 224), anchor="mm")
        for ri, mid in enumerate(mutations):
            c = next((v for v in views if v["species"] == sid and v["mutation"] == mid), None)
            if not c:
                continue
            y = head + ri * (cell + pad)
            sheet.paste(creature_view(c, cell).convert("RGB"), (x, y))
    for ri, mid in enumerate(mutations):
        y = head + ri * (cell + pad) + cell / 2
        label = mid if pose == "idle" else "EATING"
        draw.text((left / 2 + 4, y), label, font=f_small, fill=MUTATION[mid], anchor="mm")
    draw.text((pad, sheet.height - 18), "Approximate offline preview (flat shading, no auras/particles) — not the Roblox renderer.", font=f_small, fill=(120, 128, 160))
    sheet.save(path)
    return path


def world_view(parts, path, size=1100):
    top = render(parts, (0, 400, 0.01), (0, 0, 0), 440, size, (16, 18, 30, 255), light=(0.3, 1, 0.4))
    angled = render(parts, (-230, 190, -330), (0, 0, 20), 470, size, (16, 18, 30, 255))
    sheet = Image.new("RGB", (size * 2 + 12, size + 26), (23, 26, 43))
    sheet.paste(top.convert("RGB"), (0, 0))
    sheet.paste(angled.convert("RGB"), (size + 12, 0))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, size + 6), "Map preview (top-down and 3/4 view, 3 players joined). Approximate offline render — not the Roblox renderer.", font=font(12), fill=(120, 128, 160))
    sheet.save(path)
    return path


def main():
    with open(os.path.join(ROOT, "creatures.json")) as fh:
        creatures = json.load(fh)
    with open(os.path.join(ROOT, "world.json")) as fh:
        world = json.load(fh)
    print(creature_sheet(creatures, "idle", os.path.join(ROOT, "creatures.png")))
    print(creature_sheet(creatures, "eat", os.path.join(ROOT, "creatures_eat.png")))
    print(world_view(world, os.path.join(ROOT, "world.png")))


if __name__ == "__main__":
    sys.exit(main())
