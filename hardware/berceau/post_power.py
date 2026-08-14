#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
post_power.py — après le routage freerouting (qui efface tout pré-routage à
l'import SES), raccorde les alimentations et la masse :

1. pads CMS +3V3/+5V : via vers le plan B.Cu correspondant (position
   collision-vérifiée contre pistes/vias/pads d'autres nets, 8 directions
   x 5 rayons) + tronçon F.Cu pad→via ;
2. pads CMS GND coupés du plan F.Cu par les couloirs de pistes : petit
   tronçon F.Cu du pad vers le point rempli le plus proche du plan
   (recherche en spirale, trajet vérifié).

Usage : post_power.py [berceau.kicad_pcb]
"""
import math
import sys
import pcbnew

BOARD = sys.argv[1] if len(sys.argv) > 1 else "berceau.kicad_pcb"
B = pcbnew.LoadBoard(BOARD)
mm = pcbnew.FromMM

W_STUB = 0.4
CLEAR = 0.25


def refill():
    pcbnew.ZONE_FILLER(B).Fill(B.Zones())


def netcode(name):
    return B.FindNet(name).GetNetCode()


NC = {n: netcode(n) for n in ("GND", "+3V3", "+5V")}


def seg_free(a, b, net, layer, width):
    """Le segment a->b (largeur width) sur layer évite-t-il les autres nets ?"""
    seg = pcbnew.SEG(a, b)
    marg = mm(width / 2 + CLEAR)
    for t in B.GetTracks():
        if t.GetNetCode() == net:
            continue
        if t.GetClass() == "PCB_VIA":
            if seg.Distance(t.GetPosition()) < marg + t.GetWidth() // 2:
                return False
        elif t.GetLayer() == layer:
            if t.GetEffectiveShape().Collide(seg, marg):
                return False
    for fp in B.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() == net:
                continue
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH or p.GetLayer() == layer:
                if p.GetEffectiveShape(layer).Collide(seg, marg):
                    return False
    return True


def via_free(pos, net):
    """Un via 0,6/0,3 peut-il vivre ici (toutes couches) ?"""
    for l in (pcbnew.F_Cu, pcbnew.B_Cu):
        if not seg_free(pos, pos, net, l, 0.6 + CLEAR):
            return False
    # trous voisins
    for t in B.GetTracks():
        if t.GetClass() == "PCB_VIA":
            if (t.GetPosition() - pos).EuclideanNorm() < mm(0.8):
                return False
    for fp in B.GetFootprints():
        for p in fp.Pads():
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH:
                if (p.GetPosition() - pos).EuclideanNorm() < mm(1.1):
                    return False
    return True


def add_via(pos, net):
    v = pcbnew.PCB_VIA(B)
    v.SetPosition(pos)
    v.SetDrill(mm(0.3))
    try:
        v.SetWidth(pcbnew.PADSTACK.ALL_LAYERS, mm(0.6))
    except TypeError:
        v.SetWidth(mm(0.6))
    v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
    v.SetNet(B.FindNetByNetcode(net) if hasattr(B, "FindNetByNetcode")
             else B.GetNetInfo().GetNetItem(net))
    B.Add(v)


def add_track(a, b, net, layer=pcbnew.F_Cu, width=W_STUB):
    t = pcbnew.PCB_TRACK(B)
    t.SetStart(a)
    t.SetEnd(b)
    t.SetWidth(mm(width))
    t.SetLayer(layer)
    t.SetNet(B.FindNetByNetcode(net) if hasattr(B, "FindNetByNetcode")
             else B.GetNetInfo().GetNetItem(net))
    B.Add(t)


def in_plane_region(pos, netname):
    x = pcbnew.ToMM(pos.x)
    return (netname == "+3V3" and x < 115.0) or (netname == "+5V" and x > 117.0) \
        or netname == "GND"


def power_vias():
    fails = []
    for fp in B.GetFootprints():
        for p in fp.Pads():
            nn = p.GetNet().GetNetname()
            if nn not in ("+3V3", "+5V"):
                continue
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH:
                continue
            net = NC[nn]
            base = p.GetPosition()
            # idempotence : déjà raccordé (un tronçon du même net part du pad)
            if any(t.GetClass() == "PCB_TRACK" and t.GetNetCode() == net and
                   (t.GetStart() == base or t.GetEnd() == base)
                   for t in B.GetTracks()):
                continue
            ok = False
            for d in (1.1, 1.4, 1.7, 2.0, 2.4, 2.8, 3.2, 3.7, 4.2, 5.0):
                if ok:
                    break
                for ang in range(0, 360, 30):
                    dx = math.cos(math.radians(ang)) * d
                    dy = math.sin(math.radians(ang)) * d
                    pos = pcbnew.VECTOR2I(base.x + mm(dx), base.y + mm(dy))
                    if not in_plane_region(pos, nn):
                        continue
                    if not via_free(pos, net):
                        continue
                    if seg_free(base, pos, net, pcbnew.F_Cu, W_STUB):
                        add_via(pos, net)
                        add_track(base, pos, net)
                        ok = True
                        break
                    # raccord en L (deux coins possibles)
                    for corner in (pcbnew.VECTOR2I(base.x, pos.y),
                                   pcbnew.VECTOR2I(pos.x, base.y)):
                        if seg_free(base, corner, net, pcbnew.F_Cu, W_STUB) and \
                           seg_free(corner, pos, net, pcbnew.F_Cu, W_STUB):
                            add_via(pos, net)
                            add_track(base, corner, net)
                            add_track(corner, pos, net)
                            ok = True
                            break
                    if ok:
                        break
            if not ok:
                fails.append("%s %s.%s" % (nn, fp.GetReference(), p.GetNumber()))
    return fails


def gnd_pad_covered(p):
    for z in B.Zones():
        if z.GetNetCode() != NC["GND"]:
            continue
        zl = z.GetLayer()
        if p.IsOnLayer(zl) and z.HitTestFilledArea(zl, p.GetPosition(), 0):
            return True
    return False


def zone_filled_at(pos):
    for z in B.Zones():
        if z.GetNetCode() == NC["GND"] and z.GetLayer() == pcbnew.F_Cu:
            if z.HitTestFilledArea(pcbnew.F_Cu, pos, 0):
                return True
    return False


def gnd_links():
    fails = []
    refill()
    for fp in B.GetFootprints():
        for p in fp.Pads():
            if p.GetNetCode() != NC["GND"]:
                continue
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH:
                continue
            if gnd_pad_covered(p):
                continue
            base = p.GetPosition()
            ok = False
            for d in (0.8, 1.2, 1.7, 2.3, 3.0, 4.0):
                if ok:
                    break
                for ang in range(0, 360, 30):
                    pos = pcbnew.VECTOR2I(
                        base.x + mm(math.cos(math.radians(ang)) * d),
                        base.y + mm(math.sin(math.radians(ang)) * d))
                    if zone_filled_at(pos) and \
                       seg_free(base, pos, NC["GND"], pcbnew.F_Cu, W_STUB):
                        add_track(base, pos, NC["GND"])
                        ok = True
                        break
            if not ok:
                fails.append("GND %s.%s" % (fp.GetReference(), p.GetNumber()))
    return fails


if __name__ == "__main__":
    f1 = power_vias()
    f2 = gnd_links()
    refill()
    pcbnew.SaveBoard(BOARD, B)
    print("échecs alim :", f1 if f1 else "aucun")
    print("échecs GND  :", f2 if f2 else "aucun")
    B2 = pcbnew.LoadBoard(BOARD)
    B2.BuildConnectivity()
    print("liaisons restantes :", B2.GetConnectivity().GetUnconnectedCount(True))
