#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prepare la copie 4 couches : plan GND In1, couture des pads GND vers In1,
puis rapport des nets encore non connectes (par net)."""
import sys, pcbnew
from pcbnew import VECTOR2I, FromMM
MM = FromMM
BOARD = sys.argv[1]

b = pcbnew.LoadBoard(BOARD)

# 1) 4 couches + plan GND In1 (si pas deja fait)
if b.GetCopperLayerCount() < 4:
    b.SetCopperLayerCount(4)
    en = b.GetEnabledLayers(); en.AddLayer(pcbnew.In1_Cu); en.AddLayer(pcbnew.In2_Cu)
    b.SetEnabledLayers(en)
    b.SetLayerName(pcbnew.In1_Cu, "GND"); b.SetLayerName(pcbnew.In2_Cu, "In2.Cu")
gnd = b.GetNetsByName()["GND"].GetNetCode()
if not any(z.GetLayer() == pcbnew.In1_Cu and z.GetNetCode() == gnd for z in b.Zones()):
    src = [z for z in b.Zones() if z.GetLayer() == pcbnew.F_Cu and z.GetNetCode() == gnd][0]
    nz = src.Duplicate()
    try: nz = nz.Cast()
    except Exception: pass
    nz.SetLayer(pcbnew.In1_Cu); nz.SetNetCode(gnd); b.Add(nz)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())

# 2) couture GND -> In1 : un via a chaque pad GND non couvert par une zone GND
VIA_DIA, VIA_DRILL = MM(0.6), MM(0.3)
CLR, HCLR = MM(0.25), MM(0.3)

def other_items(board, net):
    it = [t for t in board.GetTracks() if t.GetNetCode() != net]
    for fp in board.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() != net:
                it.append(p)
    return it

def via_ok(board, pos, items):
    pt = pcbnew.SEG(pos, pos)
    vm = int(CLR) + VIA_DIA // 2
    hm = int(HCLR) + VIA_DRILL // 2
    for it in items:
        try: s = it.GetEffectiveShape()
        except Exception: continue
        if s.Collide(pt, vm): return False
        if isinstance(it, pcbnew.PAD) and it.GetDrillSize().x > 0:
            if pcbnew.SHAPE_CIRCLE(it.GetPosition(), it.GetDrillSize().x // 2).Collide(pt, hm): return False
        if isinstance(it, pcbnew.PCB_VIA):
            if pcbnew.SHAPE_CIRCLE(it.GetPosition(), it.GetDrill() // 2).Collide(pt, hm): return False
    x, y = pcbnew.ToMM(pos.x), pcbnew.ToMM(pos.y)
    return 1.0 < x < 118.0 and 1.0 < y < 49.0

def add_via(board, pos, net):
    v = pcbnew.PCB_VIA(board); v.SetPosition(pos)
    v.SetWidth(int(VIA_DIA)); v.SetDrill(int(VIA_DRILL))
    v.SetViaType(pcbnew.VIATYPE_THROUGH); v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
    v.SetNetCode(net); board.Add(v)

items = other_items(b, gnd)
added = 0
for _ in range(6):
    b.BuildConnectivity()
    todo = []
    for fp in b.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() != gnd: continue
            cov = False
            for z in b.Zones():
                if z.GetNetCode() != gnd: continue
                zl = z.GetLayer()
                if p.IsOnLayer(zl) and z.HitTestFilledArea(zl, p.GetPosition(), 0):
                    cov = True; break
            if not cov: todo.append(p)
    n0 = 0
    for p in todo:
        base = p.GetPosition()
        cand = [base]
        for d in (0.8, 1.2, 1.6, 2.0):
            for dx, dy in ((d,0),(-d,0),(0,d),(0,-d),(d,d),(-d,d),(d,-d),(-d,-d)):
                cand.append(VECTOR2I(base.x + MM(dx), base.y + MM(dy)))
        for c in cand:
            if via_ok(b, c, items):
                add_via(b, c, gnd); added += 1; n0 += 1; break
    pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    if n0 == 0: break

pcbnew.SaveBoard(BOARD, b)

# 3) rapport
b2 = pcbnew.LoadBoard(BOARD); b2.BuildConnectivity()
conn = b2.GetConnectivity()
print("vias GND ajoutes:", added)
print("non connectees total:", conn.GetUnconnectedCount(True))
# nets encore incomplets (hors GND)
from collections import defaultdict
padnets = defaultdict(list)
for fp in b2.GetFootprints():
    for p in fp.Pads():
        nn = p.GetNetname()
        if nn and nn != "GND":
            padnets[nn].append(p)
# on liste les nets qui ont un ratsnest : approx via RatsnestForNet indisponible;
# on reporte tous les nets signaux (ceux a router seront filtres au routage)
print("nets signaux presents:", len(padnets))
