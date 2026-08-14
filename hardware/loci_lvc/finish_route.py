#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
finish_route.py — dernier kilomètre du routage loci_lvc (hérité phaseA) :

1. vias GND déterministes : un via près de chaque pad GND non couvert par la
   zone de sa face (UN SEUL passage, collisions vérifiées contre TOUT, y
   compris les vias qu'on vient d'ajouter — pas d'empilement) ;
2. re-remplissage des zones ;
3. routage A* sur grille des liaisons signal restantes (paires de pads du
   même net non connectées, détectées par la connectivité pcbnew) ;
4. sauvegarde + bilan.

Usage : finish_route.py [loci_lvc.kicad_pcb]
"""
import heapq
import math
import sys
import pcbnew

BOARD = sys.argv[1] if len(sys.argv) > 1 else "loci_lvc.kicad_pcb"
B = pcbnew.LoadBoard(BOARD)
mm = pcbnew.FromMM

GRID = 0.125
W = 0.2
CLR = 0.21
X0, Y0, X1, Y1 = 1.0, 0.8, 115.5, 49.2   # carte 120x50, doigts interdits
NX = int((X1 - X0) / GRID) + 1
NY = int((Y1 - Y0) / GRID) + 1
F, Bc = 0, 1
LAYERS = {F: pcbnew.F_Cu, Bc: pcbnew.B_Cu}
L2I = {pcbnew.F_Cu: F, pcbnew.B_Cu: Bc}

gnd = B.FindNet("GND").GetNetCode()


def refill():
    filler = pcbnew.ZONE_FILLER(B)
    filler.Fill(B.Zones())


# ---------------------------------------------------------------------------
# 1. vias GND déterministes
# ---------------------------------------------------------------------------

def gnd_pad_covered(p):
    for z in B.Zones():
        if z.GetNetCode() != gnd:
            continue
        zl = z.GetLayer()
        if p.IsOnLayer(zl) and z.HitTestFilledArea(zl, p.GetPosition(), 0):
            return True
    return False


def spot_free(pos, extra):
    """Aucun objet (tous nets, vias ajoutés compris) à moins de extra mm."""
    r = mm(extra)
    for t in B.GetTracks():
        if t.GetClass() == "PCB_VIA":
            if (t.GetPosition() - pos).EuclideanNorm() < r + t.GetWidth() // 2:
                return False
        else:
            s = t.GetEffectiveShape()
            if s.Collide(pcbnew.SEG(pos, pos), r):
                return False
    for fp in B.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() == gnd:
                continue
            if p.GetEffectiveShape(p.GetLayer()).Collide(pcbnew.SEG(pos, pos), r):
                return False
    x, y = pcbnew.ToMM(pos.x), pcbnew.ToMM(pos.y)
    return X0 + 0.5 < x < X1 - 0.5 and Y0 + 0.5 < y < Y1 - 0.5


def add_gnd_vias():
    refill()
    added = 0
    for fp in B.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() != gnd or gnd_pad_covered(p):
                continue
            base = p.GetPosition()
            done = False
            for d in (0.9, 1.2, 1.6, 2.0, 2.6):
                if done:
                    break
                for dx, dy in ((d, 0), (-d, 0), (0, d), (0, -d),
                               (d, d), (-d, d), (d, -d), (-d, -d)):
                    pos = pcbnew.VECTOR2I(base.x + mm(dx), base.y + mm(dy))
                    if spot_free(pos, 0.5):
                        v = pcbnew.PCB_VIA(B)
                        v.SetPosition(pos)
                        v.SetDrill(mm(0.3))
                        try:
                            v.SetWidth(pcbnew.PADSTACK.ALL_LAYERS, mm(0.6))
                        except TypeError:
                            v.SetWidth(mm(0.6))
                        v.SetViaType(pcbnew.VIATYPE_THROUGH)
                        v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
                        v.SetNet(B.FindNet("GND"))
                        # petit tronçon pad->via pour garantir la liaison
                        t = pcbnew.PCB_TRACK(B)
                        t.SetStart(base)
                        t.SetEnd(pos)
                        t.SetWidth(mm(0.3))
                        t.SetLayer(p.GetLayer() if p.GetLayer() in
                                   (pcbnew.F_Cu, pcbnew.B_Cu) else pcbnew.F_Cu)
                        t.SetNet(B.FindNet("GND"))
                        B.Add(v)
                        B.Add(t)
                        added += 1
                        done = True
                        break
            if not done:
                print("  via GND impossible près de", fp.GetReference(),
                      p.GetNumber())
    print("vias GND ajoutés :", added)
    refill()


# ---------------------------------------------------------------------------
# 3. A* pour les liaisons signal restantes (repris de phaseA/astar_route.py)
# ---------------------------------------------------------------------------

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
                    dd = math.hypot(px - x1, py - y1)
                else:
                    t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / L2))
                    dd = math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))
                if dd < infl:
                    idx = gy * NX + gx
                    cur = g[idx]
                    if cur == 0:
                        g[idx] = net + 1
                    elif cur != net + 1:
                        g[idx] = -1

    for t in B.GetTracks():
        if t.GetClass() == "PCB_TRACK":
            if t.GetLayer() in L2I:
                mark(L2I[t.GetLayer()],
                     pcbnew.ToMM(t.GetStart().x), pcbnew.ToMM(t.GetStart().y),
                     pcbnew.ToMM(t.GetEnd().x), pcbnew.ToMM(t.GetEnd().y),
                     pcbnew.ToMM(t.GetWidth()) / 2, t.GetNetCode())
        else:
            x, y = pcbnew.ToMM(t.GetPosition().x), pcbnew.ToMM(t.GetPosition().y)
            for l in (F, Bc):
                mark(l, x, y, x, y, pcbnew.ToMM(t.GetWidth()) / 2,
                     t.GetNetCode())
    for fp in B.GetFootprints():
        for p in fp.Pads():
            sx, sy = pcbnew.ToMM(p.GetSizeX()), pcbnew.ToMM(p.GetSizeY())
            cx, cy = pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)
            r = min(sx, sy) / 2
            half = abs(sx - sy) / 2
            ang = math.radians(p.GetOrientation().AsDegrees())
            if sx >= sy:
                ddx, ddy = math.cos(ang) * half, -math.sin(ang) * half
            else:
                ddx, ddy = math.sin(ang) * half, math.cos(ang) * half
            layers = ([F, Bc] if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH
                      else [L2I.get(p.GetLayer())])
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

    def h(n):
        return (abs(n[1] - goal[1]) + abs(n[2] - goal[2])) \
            + (0 if n[0] == goal[0] else 8)
    own = net + 1

    def ok(l, gx, gy):
        v = grids[l][gy * NX + gx]
        return v == 0 or v == own

    def via_ok(gx, gy):
        for l in (F, Bc):
            for oy in (-2, -1, 0, 1, 2):
                for ox in (-2, -1, 0, 1, 2):
                    x2, y2 = gx + ox, gy + oy
                    if 0 <= x2 < NX and 0 <= y2 < NY:
                        v = grids[l][y2 * NX + x2]
                        if v != 0 and v != own:
                            return False
        return True
    openq = [(h(start), 0, start)]
    came = {start: None}
    dist = {start: 0}
    expand = 0
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
        expand += 1
        if expand > 2_000_000:
            return None
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
        if via_ok(gx, gy):
            n2 = (l2, gx, gy)
            nd = d + 10
            if nd < dist.get(n2, 1e18):
                dist[n2] = nd
                came[n2] = n
                heapq.heappush(openq, (nd + h(n2), nd, n2))
    return None


def emit(path, net, sx, sy, tx, ty):
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
        simple = [pl[0]]
        for a, b, c in zip(pl, pl[1:], pl[2:]):
            if (b[1] - a[1]) * (c[2] - b[2]) != (b[2] - a[2]) * (c[1] - b[1]):
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
            t.SetNet(B.FindNet(net))
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
        v.SetNet(B.FindNet(net))
        B.Add(v)


def pending_signal_pairs():
    """Paires (net, pad_a, pad_b) non connectées (hors GND/alims — zones)."""
    B.BuildConnectivity()
    conn = B.GetConnectivity()
    pairs = []
    seen = set()
    for u in range(conn.GetUnconnectedCount(True)):
        pass  # l'API des « edges » du ratsnest n'est pas exposée : approche par nets
    # approche par net : clusters de pads reliés par pistes/vias existantes
    from collections import defaultdict
    for ni in B.GetNetsByNetcode().values() if False else []:
        pass
    # plus simple : pour chaque net signal, prendre ses pads ; si le net a
    # >=2 pads et que la connectivité les met dans des clusters différents,
    # router pad le plus proche entre clusters.
    net_pads = {}
    for fp in B.GetFootprints():
        for p in fp.Pads():
            nc = p.GetNetCode()
            if nc in (0, gnd):
                continue
            name = p.GetNet().GetNetname()
            if name in ("+5V", "+3V3"):
                continue
            net_pads.setdefault(name, []).append(p)
    for name, pads in net_pads.items():
        if len(pads) < 2:
            continue
        # clusters par inondation sur les items connectés du board
        clusters = []
        assigned = {}
        for p in pads:
            placed = False
            for ci, cl in enumerate(clusters):
                q = cl[0]
                if conn.TestTrackEndpointDangling if False else False:
                    pass
            clusters.append([p])
        # la vraie séparation : utiliser GetConnectedPads du premier pad
        # (liste des pads atteignables par le cuivre)
        reach = set()
        try:
            import collections
            lst = conn.GetConnectedPads(pads[0])
            reach = {(pp.GetParentFootprint().GetReference(), pp.GetNumber())
                     for pp in lst}
        except Exception:
            pass
        reach.add((pads[0].GetParentFootprint().GetReference(),
                   pads[0].GetNumber()))
        far = [p for p in pads
               if (p.GetParentFootprint().GetReference(), p.GetNumber())
               not in reach]
        if far:
            # relier le pad isolé le plus proche du groupe atteint
            for p in far:
                best = min(
                    (q for q in pads if q not in far),
                    key=lambda q: (q.GetPosition() - p.GetPosition())
                    .EuclideanNorm())
                pairs.append((name, best, p))
    return pairs


def pad_xy_layer(p):
    x, y = pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)
    l = L2I.get(p.GetLayer(), F)
    return x, y, l


def route_signals():
    pairs = pending_signal_pairs()
    print("liaisons signal à finir :", [n for n, _, _ in pairs])
    if not pairs:
        return
    grids = raster()
    for name, pa, pb in pairs:
        nc = B.FindNet(name).GetNetCode()
        sx, sy, sl = pad_xy_layer(pa)
        tx, ty, tl = pad_xy_layer(pb)
        # libère les abords immédiats des deux pastilles pour son propre net
        for (px, py, pl) in ((sx, sy, sl), (tx, ty, tl)):
            gx, gy = cell(px, py)
            for oy in (-2, -1, 0, 1, 2):
                for ox in (-2, -1, 0, 1, 2):
                    x2, y2 = gx + ox, gy + oy
                    if 0 <= x2 < NX and 0 <= y2 < NY:
                        grids[pl][y2 * NX + x2] = nc + 1
        path = astar(grids, nc, sx, sy, sl, tx, ty, tl)
        if path is None:
            print("  ECHEC A*", name)
            continue
        emit(path, nc, sx, sy, tx, ty)
        # marque le chemin comme occupé pour les suivants (dilatation 3
        # cellules = 0,375 mm : garantit 0,2 mm d'isolement entre pistes A*)
        for l, gx, gy in path:
            for oy in (-3, -2, -1, 0, 1, 2, 3):
                for ox in (-3, -2, -1, 0, 1, 2, 3):
                    x2, y2 = gx + ox, gy + oy
                    if 0 <= x2 < NX and 0 <= y2 < NY:
                        if grids[l][y2 * NX + x2] == 0:
                            grids[l][y2 * NX + x2] = nc + 1
        print("  routé :", name, len(path), "pas")


if __name__ == "__main__":
    add_gnd_vias()
    route_signals()
    refill()
    pcbnew.SaveBoard(BOARD, B)
    B2 = pcbnew.LoadBoard(BOARD)
    B2.BuildConnectivity()
    print("liaisons restantes :",
          B2.GetConnectivity().GetUnconnectedCount(True))
