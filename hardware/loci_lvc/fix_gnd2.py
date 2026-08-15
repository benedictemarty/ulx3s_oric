#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Vias sous chaque pad GND (relie aux plans In1/In4) + retrait des ilots
isoles des zones GND (option KiCad), puis re-remplissage."""
import sys, pcbnew
from pcbnew import VECTOR2I, FromMM, ToMM
MM = FromMM
BOARD = sys.argv[1]
b = pcbnew.LoadBoard(BOARD)
gnd = b.GetNetsByName()["GND"].GetNetCode()

ITEMS = list(b.GetTracks()) + [p for fp in b.GetFootprints() for p in fp.Pads()]
VIA_D, VIA_DR, CLR = MM(0.6), MM(0.3), MM(0.2)

def via_ok(pos):
    sh = pcbnew.SHAPE_CIRCLE(pos, VIA_D//2)
    for it in ITEMS:
        if it.GetNetCode() == gnd: continue
        try: s = it.GetEffectiveShape()
        except Exception: continue
        if s.Collide(sh, int(CLR)): return False
    x, y = ToMM(pos.x), ToMM(pos.y)
    return 0.6 < x < 119.8 and 0.6 < y < 49.4

def add_via(pos):
    v = pcbnew.PCB_VIA(b); v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetPosition(pos)
    v.SetDrill(int(VIA_DR)); v.SetWidth(int(VIA_D)); v.SetNetCode(gnd); b.Add(v); ITEMS.append(v)

added = 0
for fp in b.GetFootprints():
    for p in fp.Pads():
        if p.GetNetCode() != gnd or p.GetDrillSize().x > 0: continue
        pos = p.GetPosition(); placed = False
        for d in (0.0, 0.6, 0.9, 1.2, 1.6, 2.0):
            for dx, dy in [(0,0),(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)]:
                vp = VECTOR2I(pos.x+MM(dx*d), pos.y+MM(dy*d))
                if via_ok(vp):
                    add_via(vp); added += 1; placed = True; break
            if placed: break

# retrait des ilots isoles des zones GND
mode = None
for nm in ("ISLAND_REMOVAL_MODE_ALWAYS", "ISLAND_REMOVAL_MODE_ALWAYS_REMOVE"):
    if hasattr(pcbnew, nm):
        mode = getattr(pcbnew, nm); break
for z in b.Zones():
    if z.GetNetCode() == gnd and mode is not None:
        try: z.SetIslandRemovalMode(mode)
        except Exception as e: print("warn island:", e)

pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(BOARD, b)
b2 = pcbnew.LoadBoard(BOARD); b2.BuildConnectivity()
print("vias GND pads ajoutes:", added, "| island mode:", mode)
print("non connectees restantes:", b2.GetConnectivity().GetUnconnectedCount(True))
