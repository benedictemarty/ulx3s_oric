#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_pcb.py — Berceau « LOCI-Bridge » : l'ULX3S s'enfiche (JB1/JB2, positions
relevées sur emard/ulx3s ulx3s.kicad_pcb), la LOCI arrive par nappe IDC 34.
Schéma électrique = ../loci_lvc/SPEC_NETLIST.md (5x LVCC3245A + BSS138).

Reproductible : python3 gen_pcb.py [sortie.kicad_pcb]
- contour 150 x 58 mm
- 5x SN74LVCC3245APW (TSSOP-24, brochage vérifié TI SCAS585R)
- peigne J_EXP 34 doigts hérité de phaseA (pas 2,54, doigts 1,6 x 6 mm,
  F.Cu = pairs / B.Cu = impairs, masque ouvert, bord droit)
- BSS138 pour /RESET, pull-ups/downs, découplage
- zones GND sur F.Cu et B.Cu
- netclasses : Default 0,25 mm / Power 0,5 mm, via 0,6/0,3

NE MODIFIE PAS LA NETLIST : toute la connectivité vient de SPEC_NETLIST.md.
"""

import sys
import pcbnew
from pcbnew import VECTOR2I, FromMM

FP_LIB = "/usr/share/kicad/footprints"

MM = FromMM


def V(x, y):
    return VECTOR2I(MM(x), MM(y))


# ---------------------------------------------------------------------------
# Nets (STRICTEMENT d'après SPEC_NETLIST.md)
# ---------------------------------------------------------------------------

CTRL_3V3 = ["RW", "PHI2", "IO_n", "RST_n", "IRQ_n", "ROMDIS_n", "MAP_n", "IOCTL_n"]
CTRL_5V = ["RW5", "PHI2_5", "IO5_n", "RST5_n", "IRQ5_n", "ROMDIS5_n", "MAP5_n", "IOCTL5_n"]

NET_NAMES = (
    ["GND", "+5V", "+3V3", "XCVR_DIR", "XCVR_OE_n"]
    + ["A%d" % i for i in range(16)]
    + ["D%d" % i for i in range(8)]
    + CTRL_3V3
    + ["A5V%d" % i for i in range(16)]
    + ["D5V%d" % i for i in range(8)]
    + CTRL_5V
)

# J_EXP : doigt -> net (numérotation officielle Atmos, annexe 11 — phaseA)
JEXP_NETS = {
    1: "MAP5_n", 2: "ROMDIS5_n", 3: "PHI2_5", 4: "RST5_n",
    5: "IO5_n", 6: "IOCTL5_n", 7: "RW5", 8: "IRQ5_n",
    9: "D5V2", 10: "D5V0", 11: "A5V3", 12: "D5V1",
    13: "A5V0", 14: "D5V6", 15: "A5V1", 16: "D5V3",
    17: "A5V2", 18: "D5V4", 19: "D5V5", 20: "A5V4",
    21: "A5V5", 22: "D5V7", 23: "A5V6", 24: "A5V15",
    25: "A5V7", 26: "A5V14", 27: "A5V8", 28: "A5V13",
    29: "A5V9", 30: "A5V12", 31: "A5V10", 32: "A5V11",
    33: "+5V", 34: "GND",
}

# SN74LVCC3245A (PW TSSOP-24) : brochage VÉRIFIÉ TI SCAS585R
# 1=VCCA 2=DIR 3..10=A1..A8 11/12/13=GND 14..21=B8..B1 22=/OE 23=NC 24=VCCB
LVCC_A_PINS = [str(p) for p in range(3, 11)]        # A1..A8
LVCC_B_PINS = [str(p) for p in range(21, 13, -1)]   # B1..B8


def lvcc_netmap(a_nets, b_nets, dir_net, oe_net):
    m = {"1": "+3V3", "24": "+5V", "2": dir_net, "22": oe_net,
         "11": "GND", "12": "GND", "13": "GND"}
    for p, n in zip(LVCC_A_PINS, a_nets):
        if n:
            m[p] = n
    for p, n in zip(LVCC_B_PINS, b_nets):
        if n:
            m[p] = n
    return m


# reference -> (lib, footprint, position mm, rot deg, valeur, netmap {pad: net})
def build_component_table():
    comps = []

    def add(ref, lib, fp, pos, rot, value, netmap):
        comps.append(dict(ref=ref, lib=lib, fp=fp, pos=pos, rot=rot,
                          value=value, nets=netmap))

    FP24 = "TSSOP-24_4.4x7.8mm_P0.65mm"
    UX = 116.0
    UYS = [8.0, 18.5, 29.0, 39.5, 50.0]

    # U1/U2 adresses (A->B figé), U3 données (piloté), U4 sorties de
    # contrôle (A->B figé, entrées A inutilisées à GND), U5 entrées
    # (B->A figé, entrées B inutilisées à GND).
    add("U1", "Package_SO", FP24, (UX, UYS[0]), 0, "SN74LVCC3245APW",
        lvcc_netmap(["A%d" % i for i in range(8)],
                    ["A5V%d" % i for i in range(8)], "+3V3", "GND"))
    add("U2", "Package_SO", FP24, (UX, UYS[1]), 0, "SN74LVCC3245APW",
        lvcc_netmap(["A%d" % i for i in range(8, 16)],
                    ["A5V%d" % i for i in range(8, 16)], "+3V3", "GND"))
    add("U3", "Package_SO", FP24, (UX, UYS[2]), 0, "SN74LVCC3245APW",
        lvcc_netmap(["D%d" % i for i in range(8)],
                    ["D5V%d" % i for i in range(8)], "XCVR_DIR", "XCVR_OE_n"))
    add("U4", "Package_SO", FP24, (UX, UYS[3]), 0, "SN74LVCC3245APW",
        lvcc_netmap(["RW", "PHI2", "IO_n", "GND", "GND", "GND", "GND", "GND"],
                    ["RW5", "PHI2_5", "IO5_n"] + [None] * 5, "+3V3", "GND"))
    add("U5", "Package_SO", FP24, (UX, UYS[4]), 0, "SN74LVCC3245APW",
        lvcc_netmap(["IRQ_n", "ROMDIS_n", "MAP_n", "IOCTL_n"] + [None] * 4,
                    ["IRQ5_n", "ROMDIS5_n", "MAP5_n", "IOCTL5_n",
                     "GND", "GND", "GND", "GND"], "GND", "GND"))

    # --- /RESET : BSS138 (SOT-23 : 1=G 2=S 3=D) --------------------------
    add("Q1", "Package_TO_SOT_SMD", "SOT-23", (106, 30), 0, "BSS138",
        {"1": "+3V3", "2": "RST_n", "3": "RST5_n"})

    # --- J_PWR jack 5,5/2,1 : 1=centre(+5V), 2=manchon(GND) --------------
    add("J_PWR", "Connector_BarrelJack", "BarrelJack_Horizontal",
        (130, 3.2), 90, "Jack_5.5x2.1", {"1": "+5V", "2": "GND"})

    # --- R / C -----------------------------------------------------------
    def r(ref, pos, rot, val, n1, n2):
        add(ref, "Resistor_SMD", "R_0603_1608Metric", pos, rot, val,
            {"1": n1, "2": n2})

    def c(ref, pos, rot, val, n1, n2, size="C_0603_1608Metric"):
        add(ref, "Capacitor_SMD", size, pos, rot, val, {"1": n1, "2": n2})

    r("R1", (106, 44), 90, "10k", "RST_n", "+3V3")
    r("R2", (106, 48), 90, "10k", "RST5_n", "+5V")
    r("R3", (106, 36), 90, "10k", "XCVR_OE_n", "+3V3")
    r("R4", (106, 40), 90, "10k", "XCVR_DIR", "GND")

    # Découplage : 2 x 100 nF par chip (VCCA près de la broche 1 côté
    # gauche, VCCB près de la broche 24 côté droit)
    idx = 1
    for uy in UYS:
        c("C%d" % idx, (UX - 5.2, uy - 1.3), 90, "100nF", "+3V3", "GND")
        idx += 1
        c("C%d" % idx, (UX + 5.2, uy - 1.3), 90, "100nF", "+5V", "GND")
        idx += 1
    c("C11", (110, 8), 90, "10uF", "+5V", "GND", "C_0805_2012Metric")
    c("C12", (110, 14), 90, "10uF", "+3V3", "GND", "C_0805_2012Metric")

    return comps


# ---------------------------------------------------------------------------
# Peigne J_EXP (hérité phaseA — seule la position du bord change)
# ---------------------------------------------------------------------------

def make_jb(board, nets):
    """JB1/JB2 : embases 2x20 THT aux positions RELATIVES des J1/J2 de
    l'ULX3S (relevé ulx3s.kicad_pcb : J1 colonnes x=95,37 (GP) / 97,91 (GN),
    y=62,69..110,95 pas 2,54 ; J2 colonnes x=184,27 (GN) / 186,81 (GP),
    y inversé). Nets affectés PAR POSITION -> pas de piège pairs/impairs.
    Origine berceau : J1_GP a (7,0 ; 4,0)."""
    # net par (connecteur, rangée 0..19, colonne 'gp'/'gn') — ordre ULX3S y croissant
    J1 = []   # (row, gp_net, gn_net)
    names_j1 = [("+3V3","+3V3"),("GND","GND")] +         [("GP%d"%i,"GN%d"%i) for i in range(7)] +         [("+3V3","+3V3"),("GND","GND")] +         [("GP%d"%i,"GN%d"%i) for i in range(7,14)] +         [("GND","GND"),("+3V3","+3V3")]
    names_j2 = [("+3V3","+3V3"),("GND","GND")] +         [("GP%d"%i,"GN%d"%i) for i in range(14,21)] +         [("+3V3","+3V3"),("GND","GND")] +         [("GP%d"%i,"GN%d"%i) for i in range(21,28)] +         [("GND","GND"),(None,None)]          # 39/40 = IN5V/OUT5V : NC
    GPN = {}
    for i in range(11):  GPN["GP%d"%i] = "A%d"%i
    for i,a in enumerate(range(11,16)): GPN["GP%d"%(18+i)] = "A%d"%a
    for i in range(8):   GPN["GN%d"%i] = "D%d"%i
    GPN.update({"GN8":"RW","GN9":"PHI2","GN10":"IO_n","GN18":"RST_n",
                "GN19":"IRQ_n","GN20":"ROMDIS_n","GN21":"MAP_n",
                "GN22":"IOCTL_n","GP16":"XCVR_DIR","GN16":"XCVR_OE_n"})
    def netof(nm):
        if nm is None: return None
        if nm in ("+3V3","GND"): return nets[nm]
        return nets[GPN[nm]] if nm in GPN else None
    for ref, x_gp, x_gn, ylist in (
            ("JB1", 7.0, 9.54, [4.0 + 2.54*k for k in range(20)]),
            ("JB2", 7.0 + 88.90 + 1.27, 7.0 + 88.90 - 1.27,
             [4.0 + 2.54*(19-k) for k in range(20)])):
        # JB2 : colonne GN interne (x plus petit), y inversé (relevé ULX3S)
        names = names_j1 if ref == "JB1" else names_j2
        fp = pcbnew.FOOTPRINT(board)
        fp.SetFPID(pcbnew.LIB_ID("berceau", ref))
        fp.SetReference(ref)
        fp.SetValue("ULX3S_" + ("J1" if ref == "JB1" else "J2"))
        fp.SetAttributes(pcbnew.FP_THROUGH_HOLE | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
        fp.SetPosition(V(0, 0))
        num = 1
        for k in range(20):
            gp_net, gn_net = names[k]
            for nm, x in ((gp_net, x_gp), (gn_net, x_gn)):
                pad = pcbnew.PAD(fp)
                pad.SetNumber(str(num)); num += 1
                pad.SetAttribute(pcbnew.PAD_ATTRIB_PTH)
                pad.SetShape(pcbnew.PAD_SHAPE_CIRCLE)
                pad.SetSize(V(1.7, 1.7))
                pad.SetDrillSize(V(1.0, 1.0))
                pad.SetLayerSet(pad.PTHMask())
                pad.SetPosition(V(x, ylist[k]))
                n = netof(nm)
                if n: pad.SetNet(n)
                fp.Add(pad)
        board.Add(fp)

def make_jloci(board, nets):
    """J_LOCI : IDC 2x17 (34) vers CN1 de la LOCI, nappe droite 1:1.
    Numérotation IDC standard : pin1 en haut-gauche, impairs colonne gauche.
    Nets = JEXP_NETS (numérotation officielle Atmos)."""
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("berceau", "J_LOCI_IDC34"))
    fp.SetReference("J_LOCI")
    fp.SetValue("IDC_2x17_detrompeur")
    fp.SetAttributes(pcbnew.FP_THROUGH_HOLE | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
    fp.SetPosition(V(0, 0))
    x0, y0 = 138.0, 7.0
    for k in range(17):
        for col in (0, 1):
            num = 2*k + 1 + col
            pad = pcbnew.PAD(fp)
            pad.SetNumber(str(num))
            pad.SetAttribute(pcbnew.PAD_ATTRIB_PTH)
            pad.SetShape(pcbnew.PAD_SHAPE_CIRCLE if num > 1 else pcbnew.PAD_SHAPE_RECT)
            pad.SetSize(V(1.7, 1.7))
            pad.SetDrillSize(V(1.0, 1.0))
            pad.SetLayerSet(pad.PTHMask())
            pad.SetPosition(V(x0 + col*2.54, y0 + k*2.54))
            pad.SetNet(nets[JEXP_NETS[num]])
            fp.Add(pad)
    board.Add(fp)

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

def build(out_path):
    board = pcbnew.CreateEmptyBoard()
    board.SetFileName(out_path)

    ds = board.GetDesignSettings()
    ds.m_CopperEdgeClearance = 0  # doigts affleurant le bord
    ns = ds.m_NetSettings
    dflt = ns.GetDefaultNetclass()
    dflt.SetTrackWidth(MM(0.25))
    dflt.SetClearance(MM(0.2))
    dflt.SetViaDiameter(MM(0.6))
    dflt.SetViaDrill(MM(0.3))
    power = pcbnew.NETCLASS("Power")
    power.SetTrackWidth(MM(0.5))
    power.SetClearance(MM(0.2))
    power.SetViaDiameter(MM(0.6))
    power.SetViaDrill(MM(0.3))
    ns.SetNetclass("Power", power)
    for pat in ("+5V", "+3V3", "GND"):
        ns.SetNetclassPatternAssignment(pat, "Power")

    nets = {}
    for name in NET_NAMES:
        ni = pcbnew.NETINFO_ITEM(board, name)
        board.Add(ni)
        nets[name] = ni

    # --- contour 120 x 50 ------------------------------------------------
    W, H = 150.0, 58.0
    corners = [(0, 0), (W, 0), (W, H), (0, H)]
    for i in range(4):
        seg = pcbnew.PCB_SHAPE(board)
        seg.SetShape(pcbnew.SHAPE_T_SEGMENT)
        seg.SetStart(V(*corners[i]))
        seg.SetEnd(V(*corners[(i + 1) % 4]))
        seg.SetLayer(pcbnew.Edge_Cuts)
        seg.SetWidth(MM(0.1))
        board.Add(seg)

    for comp in build_component_table():
        fp = pcbnew.FootprintLoad("%s/%s.pretty" % (FP_LIB, comp["lib"]), comp["fp"])
        if fp is None:
            raise RuntimeError("Empreinte introuvable : %s/%s" % (comp["lib"], comp["fp"]))
        fp.SetReference(comp["ref"])
        fp.SetValue(comp["value"])
        fp.SetOrientationDegrees(comp["rot"])
        fp.SetPosition(V(*comp["pos"]))
        for pad in fp.Pads():
            n = comp["nets"].get(pad.GetNumber())
            if n:
                pad.SetNet(nets[n])
        board.Add(fp)

    make_jb(board, nets)
    make_jloci(board, nets)

    # --- plans : F.Cu = GND ; B.Cu = +3V3 | +5V (split au milieu des chips)
    def add_zone(layer, netname, pts, name):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNetCode(nets[netname].GetNetCode())
        z.SetAssignedPriority(0)
        z.SetLocalClearance(MM(0.3))
        z.SetMinThickness(MM(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        z.AddPolygon(pcbnew.VECTOR_VECTOR2I([V(x, y) for x, y in pts]))
        z.SetZoneName(name)
        board.Add(z)
    SPLIT = 116.0
    add_zone(pcbnew.F_Cu, "GND",
             [(0.4, 0.4), (W - 0.4, 0.4), (W - 0.4, H - 0.4), (0.4, H - 0.4)],
             "GND_F")
    add_zone(pcbnew.B_Cu, "+3V3",
             [(0.4, 0.4), (SPLIT, 0.4), (SPLIT, H - 0.4), (0.4, H - 0.4)],
             "P3V3_B")
    add_zone(pcbnew.B_Cu, "+5V",
             [(SPLIT, 0.4), (W - 0.4, 0.4), (W - 0.4, H - 0.4), (SPLIT, H - 0.4)],
             "P5V_B")

    # Vias d'alimentation déterministes : chaque pad CMS +3V3/+5V reçoit un
    # via vers son plan B.Cu (décalé vers l'extérieur de l'empreinte).
    for fp in board.GetFootprints():
        c = fp.GetPosition()
        for p in fp.Pads():
            nname = p.GetNet().GetNetname()
            if nname not in ("+3V3", "+5V"):
                continue
            if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH:
                continue                     # traversant : deja sur B.Cu
            pos = p.GetPosition()
            dx = pos.x - c.x
            dy = pos.y - c.y
            import math as _m
            L = _m.hypot(dx, dy) or 1.0
            off = V(0, 0)
            vpos = pcbnew.VECTOR2I(int(pos.x + dx / L * MM(1.4)),
                                   int(pos.y + dy / L * MM(1.4)))
            v = pcbnew.PCB_VIA(board)
            v.SetPosition(vpos)
            v.SetDrill(MM(0.3))
            try:
                v.SetWidth(pcbnew.PADSTACK.ALL_LAYERS, MM(0.6))
            except TypeError:
                v.SetWidth(MM(0.6))
            v.SetViaType(pcbnew.VIATYPE_THROUGH)
            v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
            v.SetNet(nets[nname])
            t = pcbnew.PCB_TRACK(board)
            t.SetStart(pos)
            t.SetEnd(vpos)
            t.SetWidth(MM(0.4))
            t.SetLayer(pcbnew.F_Cu)
            t.SetNet(nets[nname])
            board.Add(v)
            board.Add(t)

    pcbnew.SaveBoard(out_path, board)
    board2 = pcbnew.LoadBoard(out_path)
    filler = pcbnew.ZONE_FILLER(board2)
    filler.Fill(board2.Zones())
    pcbnew.SaveBoard(out_path, board2)
    print("OK :", out_path)
    print("Empreintes :", len(board2.GetFootprints()))
    print("Nets :", board2.GetNetCount())


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "berceau.kicad_pcb")
