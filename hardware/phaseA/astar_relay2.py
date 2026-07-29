#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Routeur A* sur grille pour les dernières liaisons de la phase A.
Grille 0,25 mm, 2 couches, changement de couche par via (coût dédié).
Obstacles rastérisés avec gonflement = rayon obstacle + demi-piste + marge."""
import heapq
import math
import pcbnew

B = pcbnew.LoadBoard("phaseA.kicad_pcb")
mm = pcbnew.FromMM
GRID = 0.125
W = 0.2
CLR = 0.155
VIA_R = 0.3
X0, Y0, X1, Y1 = 10.0, 0.8, 157.5, 55.2
NX = int((X1 - X0) / GRID) + 1
NY = int((Y1 - Y0) / GRID) + 1
F, Bc = 0, 1
LAYERS = {F: pcbnew.F_Cu, Bc: pcbnew.B_Cu}

def netcode(name):
    it = B.GetNetsByName().find(name)
    assert it != B.GetNetsByName().end(), name
    return it.value()[1].GetNetCode()

# ---------------- rasterisation des obstacles ----------------
# blocked[layer] = bytearray NX*NY ; on stocke le netcode "proprietaire"
# 0 = libre, sinon net+1 du bloqueur (pour autoriser son propre net)
def raster():
    grids = {F: [0] * (NX * NY), Bc: [0] * (NX * NY)}
    def mark(layer, x1, y1, x2, y2, rad, net):
        infl = rad + W / 2 + CLR
        gx0 = max(0, int((min(x1, x2) - infl - X0) / GRID))
        gx1 = min(NX - 1, int((max(x1, x2) + infl - X0) / GRID) + 1)
        gy0 = max(0, int((min(y1, y2) - infl - Y0) / GRID))
        gy1 = min(NY - 1, int((max(y1, y2) + infl - Y0) / GRID) + 1)
        dx, dy = x2 - x1, y2 - y1
        L2 = dx * dx + dy * dy
        g = grids[layer]
        for gy in range(gy0, gy1 + 1):
            py = Y0 + gy * GRID
            for gx in range(gx0, gx1 + 1):
                px = X0 + gx * GRID
                if L2 == 0:
                    d = math.hypot(px - x1, py - y1)
                else:
                    t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / L2))
                    d = math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
                if d < infl:
                    idx = gy * NX + gx
                    cur = g[idx]
                    if cur == 0:
                        g[idx] = net + 1
                    elif cur != net + 1:
                        g[idx] = -1        # bloqué par plusieurs nets
    for t in B.GetTracks():
        if t.GetClass() == "PCB_TRACK":
            mark({pcbnew.F_Cu: F, pcbnew.B_Cu: Bc}[t.GetLayer()],
                 pcbnew.ToMM(t.GetStart().x), pcbnew.ToMM(t.GetStart().y),
                 pcbnew.ToMM(t.GetEnd().x), pcbnew.ToMM(t.GetEnd().y),
                 pcbnew.ToMM(t.GetWidth()) / 2, t.GetNetCode())
        else:
            x, y = pcbnew.ToMM(t.GetPosition().x), pcbnew.ToMM(t.GetPosition().y)
            for l in (F, Bc):
                mark(l, x, y, x, y, pcbnew.ToMM(t.GetWidth()) / 2, t.GetNetCode())
    for fp in B.GetFootprints():
        for p in fp.Pads():
            sx, sy = pcbnew.ToMM(p.GetSizeX()), pcbnew.ToMM(p.GetSizeY())
            cx, cy = pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)
            if max(sx, sy) < 2 * min(sx, sy):
                r = math.hypot(sx, sy) / 2   # quasi carre : cercle circonscrit
                half = 0.0
            else:
                r = min(sx, sy) / 2
                half = abs(sx - sy) / 2
            ang = math.radians(p.GetOrientation().AsDegrees())
            if sx >= sy:
                ddx, ddy = math.cos(ang) * half, -math.sin(ang) * half
            else:
                ddx, ddy = math.sin(ang) * half, math.cos(ang) * half
            layers = ([F, Bc] if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH
                      else [{pcbnew.F_Cu: F, pcbnew.B_Cu: Bc}.get(p.GetLayer())])
            for l in layers:
                if l is not None:
                    mark(l, cx - ddx, cy - ddy, cx + ddx, cy + ddy, r,
                         p.GetNetCode())
    return grids

def cell(x, y):
    return (max(0, min(NX - 1, round((x - X0) / GRID))),
            max(0, min(NY - 1, round((y - Y0) / GRID))))

def astar(grids, net, sx, sy, sl, tx, ty, tl):
    start = (sl, *cell(sx, sy))
    goal = (tl, *cell(tx, ty))
    NOVIA = 22
    def near_ends(gx, gy):
        return (abs(gx-start[1])+abs(gy-start[2]) < NOVIA or
                abs(gx-goal[1])+abs(gy-goal[2]) < NOVIA)
    def h(n):
        return (abs(n[1] - goal[1]) + abs(n[2] - goal[2])) + (0 if n[0] == goal[0] else 8)
    own = net + 1
    def ok(l, gx, gy):
        v = grids[l][gy * NX + gx]
        return v == 0 or v == own
    def via_ok(gx, gy):
        # via : les 2 couches libres sur un petit voisinage
        for l in (F, Bc):
            for oy in (-1, 0, 1):
                for ox in (-1, 0, 1):
                    x2, y2 = gx + ox, gy + oy
                    if 0 <= x2 < NX and 0 <= y2 < NY:
                        v = grids[l][y2 * NX + x2]
                        if v != 0 and v != own:
                            return False
        return True
    openq = [(h(start), 0, start)]
    came = {start: None}
    dist = {start: 0}
    while openq:
        _, d, n = heapq.heappop(openq)
        if n == goal:
            path = [n]
            while came[n] is not None:
                n = came[n]
                path.append(n)
            return path[::-1]
        if d > dist.get(n, 1e18):
            continue
        l, gx, gy = n
        for ddx, ddy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            x2, y2 = gx + ddx, gy + ddy
            if 0 <= x2 < NX and 0 <= y2 < NY and ok(l, x2, y2):
                n2 = (l, x2, y2)
                nd = d + 1
                if nd < dist.get(n2, 1e18):
                    dist[n2] = nd
                    came[n2] = n
                    heapq.heappush(openq, (nd + h(n2), nd, n2))
        l2 = 1 - l
        if via_ok(gx, gy) and not near_ends(gx, gy):
            n2 = (l2, gx, gy)
            nd = d + 10
            if nd < dist.get(n2, 1e18):
                dist[n2] = nd
                came[n2] = n
                heapq.heappush(openq, (nd + h(n2), nd, n2))
    return None

def emit(path, netname, sx, sy, tx, ty):
    # compresse en segments par couche + vias, raccorde les extremites exactes
    pts = [(l, X0 + gx * GRID, Y0 + gy * GRID) for l, gx, gy in path]
    segs = []
    vias = []
    cur = [pts[0]]
    for p in pts[1:]:
        if p[0] != cur[-1][0]:
            vias.append((cur[-1][1], cur[-1][2]))
            segs.append(cur)
            cur = [p]
        else:
            cur.append(p)
    segs.append(cur)
    def emit_polyline(layer, pl, head=None, tail=None):
        # simplification colinéaire
        simple = [pl[0]]
        for a, b, c in zip(pl, pl[1:], pl[2:]):
            if (b[1]-a[1])*(c[2]-b[2]) != (b[2]-a[2])*(c[1]-b[1]):
                simple.append(b)
        simple.append(pl[-1])
        coords = [(p[1], p[2]) for p in simple]
        if head:
            coords[0] = head
        if tail:
            coords[-1] = tail
        for a, c in zip(coords, coords[1:]):
            t = pcbnew.PCB_TRACK(B)
            t.SetStart(pcbnew.VECTOR2I(mm(a[0]), mm(a[1])))
            t.SetEnd(pcbnew.VECTOR2I(mm(c[0]), mm(c[1])))
            t.SetWidth(mm(W))
            t.SetLayer(LAYERS[layer])
            t.SetNet(B.FindNet(netname))
            B.Add(t)
    for i, s in enumerate(segs):
        emit_polyline(s[0][0], s,
                      head=(sx, sy) if i == 0 else None,
                      tail=(tx, ty) if i == len(segs) - 1 else None)
    for x, y in vias:
        v = pcbnew.PCB_VIA(B)
        v.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
        v.SetDrill(mm(0.3))
        try:
            v.SetWidth(pcbnew.PADSTACK.ALL_LAYERS, mm(0.6))
        except TypeError:
            v.SetWidth(mm(0.6))
        v.SetViaType(pcbnew.VIATYPE_THROUGH)
        v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
        v.SetNet(B.FindNet(netname))
        B.Add(v)


def remark_passives(grids, own):
    n = 0
    for fp in B.GetFootprints():
        if fp.GetReference()[:1] not in ("R", "C"):
            continue
        for p in fp.Pads():
            if p.GetNetCode() == own - 1:
                continue
            sx, sy = pcbnew.ToMM(p.GetSizeX()), pcbnew.ToMM(p.GetSizeY())
            cx, cy = pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)
            infl = W/2 + CLR
            gx0 = max(0, int((cx - sx/2 - infl - X0)/GRID))
            gx1 = min(NX-1, int((cx + sx/2 + infl - X0)/GRID)+1)
            gy0 = max(0, int((cy - sy/2 - infl - Y0)/GRID))
            gy1 = min(NY-1, int((cy + sy/2 + infl - Y0)/GRID)+1)
            l = {pcbnew.F_Cu: 0, pcbnew.B_Cu: 1}.get(p.GetLayer())
            if l is None:
                continue
            for gy in range(gy0, gy1+1):
                for gx in range(gx0, gx1+1):
                    idx = gy*NX+gx
                    if grids[l][idx] != -1 and grids[l][idx] != own:
                        pass
                    if grids[l][idx] == own:
                        grids[l][idx] = -1
                        n += 1
    return n

def clear_escape(grids, layer, x, y, direction, own, length=3.2):
    gx, gy = cell(x, y)
    steps = int(length / GRID)
    rng = [(gx+ox, gy+oy) for ox in (-1,0,1) for oy in (-1,0,1)]
    if direction is not None:
        dx, dy = direction
        for k in range(steps+1):
            rng.append((gx+dx*k, gy+dy*k))
    for x2, y2 in rng:
        if 0 <= x2 < NX and 0 <= y2 < NY:
            grids[layer][y2*NX+x2] = own

jobs = [
    ("RST5_n",  (129.8625, 9.675, F),  (150.0, 5.95, F),  (1, 0), None, 3.2),
    ("IRQ5_n",  (129.8625, 10.325, F), (150.0, 13.57, F), (1, 0), None, 3.2),
]

print(f"grille {NX}x{NY}, rasterisation...")
grids = raster()
for net, (sx, sy, sl), (tx, ty, tl), esc_s, esc_t, esc_len in jobs:
    nc = netcode(net)
    clear_escape(grids, sl, sx, sy, esc_s, nc + 1)
    clear_escape(grids, tl, tx, ty, esc_t, nc + 1, esc_len)
    nr = remark_passives(grids, nc + 1)
    print(f"{net}: remark_passives a rebloque {nr} cellules")
    path = astar(grids, nc, sx, sy, sl, tx, ty, tl)
    if path is None:
        print("ECHEC A*", net)
        continue
    emit(path, net, sx, sy, tx, ty)
    for l, gx, gy in path:
        for oy in (-1, 0, 1):
            for ox in (-1, 0, 1):
                x2, y2 = gx + ox, gy + oy
                if 0 <= x2 < NX and 0 <= y2 < NY:
                    idx = y2 * NX + x2
                    if grids[l][idx] == 0:
                        grids[l][idx] = nc + 1
                    elif grids[l][idx] != nc + 1:
                        grids[l][idx] = -1
    print("OK", net, "cases:", len(path))

filler = pcbnew.ZONE_FILLER(B)
filler.Fill(B.Zones())
pcbnew.SaveBoard("phaseA.kicad_pcb", B)
print("sauve + zones remplies")
