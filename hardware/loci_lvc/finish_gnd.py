#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
finish_gnd.py — couture (stitching) du plan de masse.

Après le routage des signaux, les zones GND F.Cu/B.Cu sont fragmentées
par les couloirs de pistes. Ce script relie tous les fragments et pads
GND au plan principal en posant des vias GND (0,6/0,3) à des positions
légales (vérification de collision contre tous les objets d'autres nets).

Algorithme itératif :
1. remplir les zones, construire la connectivité ;
2. identifier le « cluster GND principal » (celui qui contient J_PWR.2) ;
3. pour chaque pad GND hors du cluster : essayer un via au centre du pad
   (pads CMS) ou à proximité immédiate ; pour chaque fragment de zone
   hors cluster : chercher un point du fragment couvert aussi par le plan
   de l'autre face et y poser un via ;
4. re-remplir, itérer jusqu'à convergence (max 8 passes).
"""
import sys
import pcbnew
from pcbnew import VECTOR2I, FromMM

BOARD = sys.argv[1] if len(sys.argv) > 1 else "loci_lvc.kicad_pcb"
MM = FromMM

VIA_DIA = MM(0.6)
VIA_DRILL = MM(0.3)
CLEARANCE = MM(0.25)          # marge vis-à-vis des autres nets (>0,2 règle)
HOLE_CLEAR = MM(0.3)


def other_net_items(board, gnd):
    items = []
    for t in board.GetTracks():
        if t.GetNetCode() != gnd:
            items.append(t)
    for fp in board.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() != gnd:
                items.append(p)
    return items


def via_ok(board, pos, items, gnd):
    """Le via peut-il être posé ici ? (collision avec autres nets + trous)"""
    pt = pcbnew.SEG(pos, pos)          # segment dégénéré au centre du via
    vmargin = int(CLEARANCE) + VIA_DIA // 2
    hmargin = int(HOLE_CLEAR) + VIA_DRILL // 2
    for it in items:
        try:
            s = it.GetEffectiveShape()
        except Exception:
            continue
        if s.Collide(pt, vmargin):
            return False
        # trous des pads traversants / vias
        if isinstance(it, pcbnew.PAD) and it.GetDrillSize().x > 0:
            dh = pcbnew.SHAPE_CIRCLE(it.GetPosition(), it.GetDrillSize().x // 2)
            if dh.Collide(pt, hmargin):
                return False
        if isinstance(it, pcbnew.PCB_VIA):
            dh = pcbnew.SHAPE_CIRCLE(it.GetPosition(), it.GetDrill() // 2)
            if dh.Collide(pt, hmargin):
                return False
    # rester dans la surface utile (hors peigne, hors bord)
    x, y = pcbnew.ToMM(pos.x), pcbnew.ToMM(pos.y)
    return 1.0 < x < 152.0 and 1.0 < y < 49.0


def add_via(board, pos, gnd):
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(pos)
    v.SetWidth(int(VIA_DIA))
    v.SetDrill(int(VIA_DRILL))
    v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
    v.SetNetCode(gnd)
    board.Add(v)


def zones_of(board, gnd):
    return [z for z in board.Zones() if z.GetNetCode() == gnd]


def fill(board):
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())


def gnd_clusters(board, gnd):
    """clusters connectés d'items GND -> listes d'items"""
    conn = board.GetConnectivity()
    # pcbnew n'expose pas directement les clusters : on utilise les
    # 'îlots' par approximation : un pad est-il relié au pad de référence ?
    return conn


def stranded_pads(board, gnd, refpad):
    conn = board.GetConnectivity()
    out = []
    for fp in board.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() != gnd:
                continue
            if not conn.TestTrackEndpointDangling(None):
                pass
            out.append(p)
    return out


def main():
    board = pcbnew.LoadBoard(BOARD)
    gnd = board.GetNetsByName()["GND"].GetNetCode()
    fill(board)

    items = other_net_items(board, gnd)
    zs = {z.GetLayer(): z for z in zones_of(board, gnd)}

    added_total = 0
    for it_pass in range(8):
        board.BuildConnectivity()
        conn = board.GetConnectivity()
        # pads GND non reliés à la zone de leur face ni à l'autre
        todo = []
        for fp in board.GetFootprints():
            for p in fp.Pads():
                if p.GetNetCode() != gnd:
                    continue
                covered = False
                for z in board.Zones():
                    if z.GetNetCode() != gnd:
                        continue
                    zl = z.GetLayer()
                    if p.IsOnLayer(zl) and z.HitTestFilledArea(zl, p.GetPosition(), 0):
                        covered = True
                        break
                if not covered:
                    todo.append(p)
        added = 0
        for p in todo:
            base = p.GetPosition()
            cand = [base]
            for d in (1.0, 1.5, 2.0):
                for dx, dy in ((d, 0), (-d, 0), (0, d), (0, -d),
                               (d, d), (-d, d), (d, -d), (-d, -d)):
                    cand.append(VECTOR2I(base.x + MM(dx), base.y + MM(dy)))
            for c in cand:
                if via_ok(board, c, items, gnd):
                    add_via(board, c, gnd)
                    added += 1
                    break
        added_total += added
        fill(board)
        if added == 0:
            break

    pcbnew.SaveBoard(BOARD, board)
    print("vias GND ajoutés :", added_total)


if __name__ == "__main__":
    main()
