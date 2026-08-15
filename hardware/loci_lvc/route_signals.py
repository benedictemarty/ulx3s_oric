#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Routage des signaux residuels sur In2.Cu : via-in-pad + A* sur grille."""
import sys, heapq, pcbnew
from pcbnew import VECTOR2I, FromMM, ToMM
MM = FromMM
BOARD = sys.argv[1]
b = pcbnew.LoadBoard(BOARD)

TW = MM(0.15)
VIA_D, VIA_DR = MM(0.3), MM(0.15)
CLR = MM(0.1)
STEP = 0.4                      # grille mm
NX, NY = int(120/STEP)+1, int(50/STEP)+1

SIGNALS = ["D6","A5V12"]

ITEMS = list(b.GetTracks()) + [p for fp in b.GetFootprints() for p in fp.Pads()]

def is_through(it):
    if isinstance(it, pcbnew.PCB_VIA): return True
    if isinstance(it, pcbnew.PAD): return it.GetDrillSize().x > 0
    return False

def on_layer(it, layer):
    if is_through(it): return True
    try: return it.IsOnLayer(layer)
    except Exception:
        try: return it.GetLayer() == layer
        except Exception: return False

def collide(shape, layer, nc, margin):
    for it in ITEMS:
        if it.GetNetCode() == nc: continue
        if layer is not None and not on_layer(it, layer): continue
        try: s = it.GetEffectiveShape()
        except Exception: continue
        if s.Collide(shape, margin): return True
    return False

def via_ok(pos, nc):
    if collide(pcbnew.SHAPE_CIRCLE(pos, VIA_D//2), None, nc, int(CLR)): return False
    x, y = ToMM(pos.x), ToMM(pos.y)
    return 0.8 < x < 119.6 and 0.8 < y < 49.2

def seg_ok(a, bpt, layer, nc):
    return not collide(pcbnew.SHAPE_SEGMENT(a, bpt, TW), layer, nc, int(CLR))

def add_track(a, bpt, layer, nc):
    t = pcbnew.PCB_TRACK(b); t.SetStart(a); t.SetEnd(bpt); t.SetLayer(layer)
    t.SetWidth(int(TW)); t.SetNetCode(nc); b.Add(t); ITEMS.append(t)

def add_via(pos, nc):
    v = pcbnew.PCB_VIA(b); v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetPosition(pos)
    v.SetDrill(int(VIA_DR)); v.SetWidth(int(VIA_D)); v.SetNetCode(nc); b.Add(v); ITEMS.append(v)

DIRS = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)]
DISTS = [0.7,1.0,1.4,1.8,2.3,3.0,4.0,5.0,6.0]

def entry(pad, nc):
    pos = pad.GetPosition()
    if is_through(pad): return pos
    lay = pcbnew.F_Cu if pad.IsOnLayer(pcbnew.F_Cu) else pcbnew.B_Cu
    if via_ok(pos, nc):
        add_via(pos, nc); return pos
    for dist in DISTS:
        for dx, dy in DIRS:
            vp = VECTOR2I(pos.x+MM(dx*dist), pos.y+MM(dy*dist))
            if via_ok(vp, nc) and seg_ok(pos, vp, lay, nc):
                add_track(pos, vp, lay, nc); add_via(vp, nc); return vp
    return None

# --- grille d'obstacles In2 (through-items) ---
def cell(pos): return (int(round(ToMM(pos.x)/STEP)), int(round(ToMM(pos.y)/STEP)))
def point(i, j): return VECTOR2I(MM(i*STEP), MM(j*STEP))

def build_blocked(nc, layer):
    blk = set()
    for i in range(NX):
        for j in range(NY):
            p = point(i, j)
            if collide(pcbnew.SHAPE_CIRCLE(p, TW//2), layer, nc, int(CLR)+int(MM(STEP*0.4))):
                blk.add((i, j))
    return blk

def astar(a, bpt, nc, layer):
    ca, cb = cell(a), cell(b_clip(bpt))
    blk = build_blocked(nc, layer)
    blk.discard(ca); blk.discard(cb)
    def h(c): return abs(c[0]-cb[0]) + abs(c[1]-cb[1])
    openq = [(h(ca), 0, ca)]; came = {ca: None}; g = {ca: 0}
    seen = set()
    while openq:
        _, gc, c = heapq.heappop(openq)
        if c == cb: break
        if c in seen: continue
        seen.add(c)
        for dx, dy in DIRS:
            n = (c[0]+dx, c[1]+dy)
            if not (0 <= n[0] < NX and 0 <= n[1] < NY): continue
            if n in blk: continue
            step = 1.4 if dx and dy else 1.0
            ng = gc + step
            if ng < g.get(n, 1e9):
                g[n] = ng; came[n] = c
                heapq.heappush(openq, (ng + h(n), ng, n))
    if cb not in came: return None
    path = []; c = cb
    while c is not None: path.append(c); c = came[c]
    path.reverse()
    return path

def b_clip(p): return p

def simplify(path):
    if len(path) < 3: return path
    out = [path[0]]
    for k in range(1, len(path)-1):
        dx1 = path[k][0]-out[-1][0]; dy1 = path[k][1]-out[-1][1]
        dx2 = path[k+1][0]-path[k][0]; dy2 = path[k+1][1]-path[k][1]
        if (dx1, dy1) != (dx2, dy2): out.append(path[k])
    out.append(path[-1])
    return out

def route_lay(a, bpt, nc, L):
    if seg_ok(a, bpt, L, nc):
        add_track(a, bpt, L, nc); return True
    path = astar(a, bpt, nc, L)
    if not path: return False
    pts = [a] + [point(i, j) for (i, j) in simplify(path)[1:-1]] + [bpt]
    for k in range(len(pts)-1):
        if not seg_ok(pts[k], pts[k+1], L, nc):
            return False
    for k in range(len(pts)-1):
        add_track(pts[k], pts[k+1], L, nc)
    return True

ok, ko = [], []
for name in SIGNALS:
    nc = b.FindNet(name).GetNetCode()
    pads = [p for fp in b.GetFootprints() for p in fp.Pads() if p.GetNetCode()==nc]
    ents, fail = [], False
    for p in pads:
        e = entry(p, nc)
        if e is None: fail = True; break
        ents.append(e)
    if fail: ko.append(name+"(no via)"); continue
    def link(x, y):
        for L in (pcbnew.In2_Cu, pcbnew.In3_Cu, pcbnew.F_Cu, pcbnew.B_Cu):
            if route_lay(x, y, nc, L): return True
        return False
    good = all(link(ents[i], ents[i+1]) for i in range(len(ents)-1))
    (ok if good else ko).append(name if good else name+"(no path)")

pcbnew.SaveBoard(BOARD, b)
b2 = pcbnew.LoadBoard(BOARD); b2.BuildConnectivity()
print("routes OK (%d):" % len(ok), ok)
print("echecs (%d):" % len(ko), ko)
print("non connectees restantes:", b2.GetConnectivity().GetUnconnectedCount(True))
