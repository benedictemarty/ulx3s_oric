#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Finition r7 : 5 liaisons signal par recherche de couloir + couture GND.
Largeur 0,2 mm, marge 0,13 mm (règles carte 0,15). DRC ensuite."""
import math
import pcbnew

B = pcbnew.LoadBoard("phaseA.kicad_pcb")
mm = pcbnew.FromMM
CLR = 0.13
W = 0.2

def netcode(name):
    it = B.GetNetsByName().find(name)
    assert it != B.GetNetsByName().end(), name
    return it.value()[1].GetNetCode()

def seg_pt(x1, y1, x2, y2, px, py):
    dx, dy = x2 - x1, y2 - y1
    L2 = dx * dx + dy * dy
    if L2 == 0:
        return math.hypot(px - x1, py - y1)
    t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / L2))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

def seg_seg(a, b, c, d):
    def ccw(p, q, r):
        return (r[1]-p[1])*(q[0]-p[0]) - (q[1]-p[1])*(r[0]-p[0])
    if (ccw(a,b,c)*ccw(a,b,d) < 0) and (ccw(c,d,a)*ccw(c,d,b) < 0):
        return 0.0
    return min(seg_pt(*a, *b, *c), seg_pt(*a, *b, *d),
               seg_pt(*c, *d, *a), seg_pt(*c, *d, *b))

def collect():
    obs = {pcbnew.F_Cu: [], pcbnew.B_Cu: []}
    for t in B.GetTracks():
        if t.GetClass() == "PCB_TRACK":
            obs[t.GetLayer()].append(
                (pcbnew.ToMM(t.GetStart().x), pcbnew.ToMM(t.GetStart().y),
                 pcbnew.ToMM(t.GetEnd().x), pcbnew.ToMM(t.GetEnd().y),
                 pcbnew.ToMM(t.GetWidth())/2, t.GetNetCode()))
        else:
            x, y = pcbnew.ToMM(t.GetPosition().x), pcbnew.ToMM(t.GetPosition().y)
            for l in (pcbnew.F_Cu, pcbnew.B_Cu):
                obs[l].append((x, y, x, y, pcbnew.ToMM(t.GetWidth())/2, t.GetNetCode()))
    for fp in B.GetFootprints():
        for p in fp.Pads():
            sx, sy = pcbnew.ToMM(p.GetSizeX()), pcbnew.ToMM(p.GetSizeY())
            cx, cy = pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)
            r = min(sx, sy) / 2
            half = abs(sx - sy) / 2
            ang = math.radians(p.GetOrientation().AsDegrees())
            if sx >= sy:
                dx, dy = math.cos(ang)*half, -math.sin(ang)*half
            else:
                dx, dy = math.sin(ang)*half, math.cos(ang)*half
            layers = ([pcbnew.F_Cu, pcbnew.B_Cu]
                      if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH
                      else [p.GetLayer()])
            for l in layers:
                if l in obs:
                    obs[l].append((cx-dx, cy-dy, cx+dx, cy+dy, r, p.GetNetCode()))
    return obs

def free(obs, layer, x1, y1, x2, y2, halfw, net):
    for ox1, oy1, ox2, oy2, orad, onet in obs[layer]:
        if onet == net:
            continue
        if seg_seg((x1, y1), (x2, y2), (ox1, oy1), (ox2, oy2)) < halfw + orad + CLR:
            return False
    return True

def via_free(obs, x, y, net):
    return all(free(obs, l, x, y, x, y, 0.3, net)
               for l in (pcbnew.F_Cu, pcbnew.B_Cu))

def add_seg(x1, y1, x2, y2, layer, net):
    t = pcbnew.PCB_TRACK(B)
    t.SetStart(pcbnew.VECTOR2I(mm(x1), mm(y1)))
    t.SetEnd(pcbnew.VECTOR2I(mm(x2), mm(y2)))
    t.SetWidth(mm(W))
    t.SetLayer(layer)
    t.SetNet(B.FindNet(net))
    B.Add(t)

def add_via(x, y, net):
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

obs = collect()
F, Bc = pcbnew.F_Cu, pcbnew.B_Cu

# (net, depart(x,y,THT?), arrivee(x,y,couche))
jobs = [
    ("A9",    (24.16, 44.0, True),  (124.14, 35.38, F)),
    ("A12",   (29.24, 46.54, True), (124.14, 37.33, F)),
    ("D3",    (36.86, 44.0, True),  (124.14, 18.68, F)),
    ("IRQ_n", (49.56, 46.54, True), (124.14, 10.32, F)),
    ("D5V2",  (129.86, 18.02, False), (156.95, 14.84, Bc)),
]

for net, a, c in jobs:
    nc = netcode(net)
    ax, ay, a_tht = a
    cx, cy, c_layer = c
    routed = False
    for ystep in range(4, 99):
        ycorr = ystep / 2.0
        if a_tht and c_layer == F:
            # THT -> B.Cu vertical -> couloir B.Cu -> via -> F.Cu approche
            vx, vy = cx - 1.2, ycorr
            plan = [(Bc, ax, ay, ax, ycorr), (Bc, ax, ycorr, vx, vy),
                    (F, vx, vy, cx, cy)]
            vias = [(vx, vy)]
        elif not a_tht and c_layer == Bc:
            # F.Cu -> via -> B.Cu couloir -> arrivee B.Cu
            vx, vy = ax + 1.2, ycorr
            plan = [(F, ax, ay, vx, vy), (Bc, vx, vy, cx, ycorr),
                    (Bc, cx, ycorr, cx, cy)]
            vias = [(vx, vy)]
        else:
            continue
        if not all(free(obs, l, x1, y1, x2, y2, W/2, nc)
                   for l, x1, y1, x2, y2 in plan):
            continue
        if not all(via_free(obs, x, y, nc) for x, y in vias):
            continue
        for l, x1, y1, x2, y2 in plan:
            add_seg(x1, y1, x2, y2, l, nc)
            obs[l].append((x1, y1, x2, y2, W/2, nc))
        for x, y in vias:
            add_via(x, y, nc)
            for l in (F, Bc):
                obs[l].append((x, y, x, y, 0.3, nc))
        print(f"OK {net} couloir y={ycorr}")
        routed = True
        break
    if not routed:
        print("ECHEC", net)

pcbnew.SaveBoard("phaseA.kicad_pcb", B)
print("sauve")
