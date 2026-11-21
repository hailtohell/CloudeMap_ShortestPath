#!/usr/bin/env python3
"""Sea lanes for the ship and zeppelin paths, so their drawn lines stay off the land.

The recorded paths jump at loading screens (Kalimdor <-> Eastern Kingdoms) and at the zeppelins'
mid-air hand-overs (Grom'gol -> Tirisfal). Each jump is routed round the land with Shortest Path's
own walking grid (Nav/Nav0*.lua, Nav1*.lua: ground, water or blocked per 8-yard cell) as the land
mask. A jump between the two continents is routed on each side to the strait between them (east of
all Kalimdor, west of all the Eastern Kingdoms); on CloudeMap's map that strait is open sea, so the
two ends join with a straight line.

Run from inside an unpacked Shortest Path Forever folder:
    python3 -I gen_lanes.py . ../path/to/Transit.lua ../path/to/Lanes.lua 1.43.11 [preview-dir]
Needs: pip install lupa numpy scikit-image (pillow for the preview).
"""
import base64, glob, math, os, re, sys, zlib

import lupa.lua51 as lua
import numpy as np
from skimage.graph import MCP_Geometric

SPF, TRANSIT, OUT, VERSION = sys.argv[1:5]
PREVIEW = sys.argv[5] if len(sys.argv) > 5 else None

R = 64.0            # yards per mask cell
PAD = 90            # sea cells round the walking grid (5760 yd)
CLEAR = 3           # cells kept between a lane and the shore
GATE = (CLEAR + 3) * R   # yards beyond the outermost land where the strait begins
JUMP = 1500         # a gap this long within one continent is a hand-over, not a step
LAND_COST = 60      # a lane may cross land only to leave or reach an inland end (zeppelins)
EAST = {1: True, 0: False}   # Kalimdor's strait side is its east (low y), the Eastern Kingdoms' its west

L = lua.LuaRuntime()
L.execute("ShortestPathForeverPathData = {}")


def load(path):
    L.execute("local f = assert(loadstring(...)); f(nil, ns)", open(path, encoding="utf-8").read())


L.execute("ns = {}")
load(TRANSIT)
G = L.globals()
ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
B64 = {c: i for i, c in enumerate(ALPHA)}
T = 1600 / 3


def mask(cont):
    files = sorted(glob.glob(os.path.join(SPF, "Nav", f"Nav{cont}_*.lua")),
                   key=lambda f: int(re.findall(r"_(\d+)\.lua$", f)[0]))
    for f in [os.path.join(SPF, "Nav", f"Nav{cont}.lua")] + files:
        load(f)
    D = G.ShortestPathForeverPathData[cont]
    cx0, cy0, nx, ny, C, steep = D.cx0, D.cy0, D.nx, D.ny, D.cells, D.steep
    cs = T / C
    x0, y0 = cx0 * T - PAD * R, cy0 * T - PAD * R
    W, H = int(nx * T / R) + 2 * PAD + 1, int(ny * T / R) + 2 * PAD + 1
    hit, cnt = np.zeros((W, H)), np.zeros((W, H))
    for k in range(nx * ny):
        blocks = D.packed.grid[k + 1]
        if not blocks:
            continue
        raw = b"".join(zlib.decompress(base64.b64decode(blocks[i + 1])) for i in range(len(blocks))).decode()
        vals, v = [], 0
        for ch in raw:
            s = B64[ch]
            if s < 48:
                v = s // 16
                vals.append(v)
            else:
                vals.extend([v] * (s - 47))
        a = np.array(vals[: C * C]).reshape(C, C)          # [cell along x, cell along y]
        bx, by = (cx0 + k // ny) * T, (cy0 + k % ny) * T
        ix = ((bx + (np.arange(C) + 0.5) * cs - x0) / R).astype(int)
        iy = ((by + (np.arange(C) + 0.5) * cs - y0) / R).astype(int)
        IX, IY = np.meshgrid(ix, iy, indexing="ij")
        np.add.at(hit, (IX, IY), (a != 2).astype(float))  # ground, steep or blocked: not sea
        np.add.at(cnt, (IX, IY), 1)
    land = (cnt > 0) & (hit > 0.35 * np.maximum(cnt, 1))
    near = land.copy()                                       # the shore kept clear
    for _ in range(CLEAR):
        g = near.copy()
        g[1:, :] |= near[:-1, :]; g[:-1, :] |= near[1:, :]; g[:, 1:] |= near[:, :-1]; g[:, :-1] |= near[:, 1:]
        near = g
    cost = np.where(near, LAND_COST, 1.0)
    # the strait: beyond every walkable cell of the continent (and its shore margin)
    ys = np.where(land.any(axis=0))[0] * R + y0
    gate = ys.min() - GATE if EAST[cont] else ys.max() + R + GATE
    return dict(x0=x0, y0=y0, W=W, H=H, land=land, cost=cost, gate=gate)


M = {c: mask(c) for c in (0, 1)}


def cell(m, x, y):
    return (min(max(int((x - m["x0"]) / R), 0), m["W"] - 1), min(max(int((y - m["y0"]) / R), 0), m["H"] - 1))


def world(m, i, j):
    return m["x0"] + (i + 0.5) * R, m["y0"] + (j + 0.5) * R


def gate_cells(cont):
    m = M[cont]
    j = int((m["gate"] - m["y0"]) / R)
    js = range(0, j + 1) if EAST[cont] else range(j, m["H"])
    return [(i, jj) for i in range(m["W"]) for jj in js if m["cost"][i, jj] == 1.0]


def field(m, starts):
    # the cost from the nearest of starts to every cell, and a way to trace back from a cell
    mcp = MCP_Geometric(m["cost"], fully_connected=True)
    costs, _ = mcp.find_costs(starts)
    return costs, mcp


def clear(m, a, b, allow_land):
    # every cell on a -> b is sea (or the lane is still leaving land, where land is allowed)
    n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2) + 1
    for t in range(n + 1):
        i = round(a[0] + (b[0] - a[0]) * t / n); j = round(a[1] + (b[1] - a[1]) * t / n)
        if m["cost"][i, j] != 1.0 and not allow_land:
            return False
    return True


def simplify(m, path):
    # string-pulling: keep a cell only where the straight line past it would touch the shore; the
    # stretch over land at either end (an inland zeppelin tower) is kept as it was searched
    sea = [m["cost"][p] == 1.0 for p in path]
    first = next((k for k, s in enumerate(sea) if s), 0)
    last = len(path) - 1 - next((k for k, s in enumerate(reversed(sea)) if s), 0)
    out = [path[0]] + ([path[first]] if first else [])
    k = first
    while k < last:
        far = k + 1
        for q in range(last, k, -1):
            if clear(m, path[k], path[q], False):
                far = q
                break
        out.append(path[far]); k = far
    if last < len(path) - 1:
        out.append(path[-1])
    return out


def smooth(m, pts, rounds=3):
    # Chaikin corner cutting, kept only where the cut stays at sea
    for _ in range(rounds):
        new = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            q = (0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1])
            r = (0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1])
            new += [q, r]
        new.append(pts[-1])
        ok = all(clear(m, cellf(p), cellf(q2), m["cost"][cellf(p)] != 1.0 or m["cost"][cellf(q2)] != 1.0)
                 for p, q2 in zip(new, new[1:]))
        if not ok:
            break
        pts = new
    return pts


def cellf(p):
    return (int(round(p[0])), int(round(p[1])))


def tidy(m, path):
    pts = smooth(m, [tuple(map(float, q)) for q in simplify(m, path)])
    return [world(m, i, j) for i, j in pts]


GATES = {}


def to_gate(cont, cands):
    # of the candidate path points (index, x, y), the one nearest the strait, and its way there
    m = M[cont]
    if cont not in GATES:
        GATES[cont] = field(m, gate_cells(cont))
    costs, mcp = GATES[cont]
    k, x, y = min(cands, key=lambda c: costs[cell(m, c[1], c[2])])
    return k, tidy(m, mcp.traceback(cell(m, x, y)))[::-1]       # from the strait to the point


def between(cont, out, back):
    # of the leaving and arriving candidates, the pair joined at least cost, and the way between
    m = M[cont]
    costs, _ = field(m, [cell(m, back[-1][1], back[-1][2])])
    a = min(out, key=lambda c: costs[cell(m, c[1], c[2])])
    costs, mcp = field(m, [cell(m, a[1], a[2])])
    b = min(back, key=lambda c: costs[cell(m, c[1], c[2])])
    return a[0], b[0], tidy(m, mcp.traceback(cell(m, b[1], b[2])))


def thin(points, step=180.0):
    out = []
    for p in points:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) >= step:
            out.append(p)
    return out


def calls(r, pts):
    times = {r[4][q + 1] for q in range(1, len(r[4]) + 1, 3)}
    return {k for k, q in enumerate(pts) if q[3] in times}


lanes = {}
for rid, r in sorted(G.ns.TRANSIT.routes.items()):
    if r[1] not in ("boat", "zeppelin"):
        continue
    p = list(r[5].values())
    pts = [(p[i], p[i + 1], p[i + 2], p[i + 3]) for i in range(0, len(p), 4)]
    n, stops = len(pts), calls(r, pts)
    for k in range(n):
        a, b = pts[k], pts[(k + 1) % n]
        cross = a[0] in M and b[0] in M and a[0] != b[0]
        hand = a[0] == b[0] and a[0] in M and math.hypot(a[1] - b[1], a[2] - b[2]) > JUMP
        if not (cross or hand):
            continue
        # the path points the lane may leave from: back from the jump to the last call (or the
        # continent's first point), and those it may rejoin at: on to the next call
        out, q = [], k
        while True:
            out.append((q, pts[q][1], pts[q][2]))
            if q in stops or pts[(q - 1) % n][0] != a[0] or len(out) >= n:
                break
            q = (q - 1) % n
        back, q = [], (k + 1) % n
        while True:
            back.append((q, pts[q][1], pts[q][2]))
            if q in stops or pts[(q + 1) % n][0] != b[0] or len(back) >= n:
                break
            q = (q + 1) % n
        if cross:
            fa, way_a = to_gate(a[0], out)
            fb, way_b = to_gate(b[0], back)
            # (each way runs from its path point to the strait)
            lane = [(a[0], x, y) for x, y in thin(way_a[1:])] + [(b[0], x, y) for x, y in thin(way_b[1:])][::-1]
        else:
            fa, fb, way = between(a[0], out, back)
            lane = [(a[0], x, y) for x, y in thin(way[1:-1])]
        lanes.setdefault(rid, []).append((fa + 1, fb + 1, lane))
        print(f"route {rid} {r[1]}: jump {k + 1} -> {(k + 1) % n + 1}, lane from {fa + 1} to {fb + 1}, "
              f"{len(lane)} points", file=sys.stderr)

# check: no drawn stretch crosses land, apart from an inland end's own way out to sea
bad = 0
for rid, per in lanes.items():
    r = G.ns.TRANSIT.routes[rid]
    p = list(r[5].values())
    pts = [(p[i], p[i + 1], p[i + 2]) for i in range(0, len(p), 4)]
    for fa, fb, lane in per:
        chain = [pts[fa - 1]] + lane + [pts[fb - 1]]
        for q1, q2 in zip(chain, chain[1:]):
            if q1[0] != q2[0]:
                continue
            m = M[q1[0]]
            a, b = cell(m, q1[1], q1[2]), cell(m, q2[1], q2[2])
            n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1])) * 2) + 1
            hits = sum(m["land"][round(a[0] + (b[0] - a[0]) * t / n), round(a[1] + (b[1] - a[1]) * t / n)]
                       for t in range(n + 1))
            if hits and not (m["land"][a] or m["land"][b]):
                bad += 1
                print(f"  LAND route {rid} lane {fa}->{fb}: {q1} -> {q2}, {hits} samples", file=sys.stderr)
print(f"land crossings: {bad}", file=sys.stderr)

with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("-- CloudeMap_ShortestPath: sea lanes for the ship and zeppelin paths' jumps, so the drawn lines\n")
    f.write(f"-- go round the land. Generated by tools/gen_lanes.py from Shortest Path Forever {VERSION}'s walking\n")
    f.write("-- grid (cjber, github.com/cjber/shortest-path-forever, GPL-3.0-or-later). Do not edit by hand.\n")
    f.write("-- [route] = { { from, to, continent, x, y, ... }, ... }: drawn from path point from to path point to\n")
    f.write("-- in place of the path points between them (the stretch heading away from the lane).\n")
    f.write("local _, ns = ...\nns.LANES = {\n")
    for rid in sorted(lanes):
        f.write(f"    [{rid}] = {{\n")
        for fa, fb, lane in lanes[rid]:
            body = ", ".join(f"{c}, {x:.0f}, {y:.0f}" for c, x, y in lane)
            f.write(f"        {{ {fa}, {fb}, {body} }},\n")
        f.write("    },\n")
    f.write("}\n")

if PREVIEW:
    from PIL import Image, ImageDraw
    for cont, m in M.items():
        img = np.full((m["W"], m["H"], 3), (40, 70, 120), np.uint8)
        img[m["cost"] != 1.0] = (90, 110, 120)
        img[m["land"]] = (150, 130, 90)
        im = Image.fromarray(img[::-1, ::-1]); d = ImageDraw.Draw(im)
        P = lambda x, y: (m["H"] - 1 - (y - m["y0"]) / R, m["W"] - 1 - (x - m["x0"]) / R)
        gx = P(0, m["gate"])[0]
        d.line([(gx, 0), (gx, m["W"])], fill=(255, 0, 255), width=1)
        for rid, r in G.ns.TRANSIT.routes.items():
            if r[1] not in ("boat", "zeppelin"):
                continue
            p = list(r[5].values())
            pts = [(p[i], p[i + 1], p[i + 2]) for i in range(0, len(p), 4)]
            col = (255, 255, 255) if r[1] == "boat" else (255, 140, 60)
            n = len(pts)
            skip = set()
            for fa, fb, lane in lanes.get(rid, []):
                q = fa % n
                while q != fb - 1:
                    skip.add(q); q = (q + 1) % n
                chain = [pts[fa - 1]] + lane + [pts[fb - 1]]
                d.line([P(x, y) for c, x, y in chain if c == cont], fill=(0, 255, 0), width=3)
            for k, (a, b) in enumerate(zip(pts, pts[1:] + pts[:1])):
                if k in skip or (k + 1) % n in skip or any(k == fa - 1 for fa, _, _ in lanes.get(rid, [])):
                    continue
                if a[0] == b[0] == cont:
                    d.line([P(a[1], a[2]), P(b[1], b[2])], fill=col, width=2)
            d.text(P(pts[0][1], pts[0][2]), str(rid), fill=(255, 255, 0)) if pts[0][0] == cont else None
        im.save(os.path.join(PREVIEW, f"lanes{cont}.png"))
