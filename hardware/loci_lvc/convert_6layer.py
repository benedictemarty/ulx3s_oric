#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Passe un board en 6 couches : F(sig) In1(GND) In2(sig) In3(sig) In4(GND) B(sig).
Ajoute les plans GND sur In1 et In4 (contour repris de la zone GND F.Cu)."""
import sys, pcbnew
BOARD = sys.argv[1]
b = pcbnew.LoadBoard(BOARD)
b.SetCopperLayerCount(6)
en = b.GetEnabledLayers()
for L in (pcbnew.In1_Cu, pcbnew.In2_Cu, pcbnew.In3_Cu, pcbnew.In4_Cu):
    en.AddLayer(L)
b.SetEnabledLayers(en)
# noms de couches standard conserves (import SES fiable)
gnd = b.GetNetsByName()["GND"].GetNetCode()
src = [z for z in b.Zones() if z.GetLayer() == pcbnew.F_Cu and z.GetNetCode() == gnd][0]
for L in (pcbnew.In1_Cu, pcbnew.In4_Cu):
    nz = src.Duplicate()
    try: nz = nz.Cast()
    except Exception: pass
    nz.SetLayer(L); nz.SetNetCode(gnd); b.Add(nz)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(BOARD, b)
b2 = pcbnew.LoadBoard(BOARD)
print("couches:", b2.GetCopperLayerCount())
print("plans GND:", [pcbnew.LayerName(z.GetLayer()) for z in b2.Zones() if z.GetNetname()=="GND"])
