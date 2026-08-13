#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_pcb.py — Carte adaptateur LOCI (rév. LVC) : génération complète du PCB
(loci_lvc.kicad_pcb) depuis SPEC_NETLIST.md.

Reproductible : python3 gen_pcb.py [sortie.kicad_pcb]
- contour 110 x 50 mm
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
    UX = 80.0
    UYS = [6.5, 16.0, 25.5, 35.0, 44.0]

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
    add("Q1", "Package_TO_SOT_SMD", "SOT-23", (52, 40), 0, "BSS138",
        {"1": "+3V3", "2": "RST_n", "3": "RST5_n"})

    # --- J_ULX (2x20) — ordre fan-out (spec loci_lvc) --------------------
    jux = {}
    for p, n in zip(range(1, 9), CTRL_3V3):
        jux[str(p)] = n
    jux["9"] = "XCVR_DIR"
    jux["10"] = "XCVR_OE_n"
    for i in range(8):
        jux[str(i + 11)] = "D%d" % i
    for i in range(16):
        jux[str(i + 19)] = "A%d" % i
    for p in (35, 36, 39, 40):
        jux[str(p)] = "GND"
    jux["37"] = "+3V3"
    jux["38"] = "+3V3"
    add("J_ULX", "Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical",
        (14, 46.54), 90, "Conn_02x20", jux)

    # --- J_PWR jack 5,5/2,1 : 1=centre(+5V), 2=manchon(GND) --------------
    add("J_PWR", "Connector_BarrelJack", "BarrelJack_Horizontal",
        (10, 2.1), 90, "Jack_5.5x2.1", {"1": "+5V", "2": "GND"})

    # --- R / C -----------------------------------------------------------
    def r(ref, pos, rot, val, n1, n2):
        add(ref, "Resistor_SMD", "R_0603_1608Metric", pos, rot, val,
            {"1": n1, "2": n2})

    def c(ref, pos, rot, val, n1, n2, size="C_0603_1608Metric"):
        add(ref, "Capacitor_SMD", size, pos, rot, val, {"1": n1, "2": n2})

    r("R1", (47, 40), 90, "10k", "RST_n", "+3V3")
    r("R2", (57, 40), 90, "10k", "RST5_n", "+5V")
    r("R3", (47, 35), 90, "10k", "XCVR_OE_n", "+3V3")
    r("R4", (52, 35), 90, "10k", "XCVR_DIR", "GND")

    # Découplage : 2 x 100 nF par chip (VCCA près de la broche 1 côté
    # gauche, VCCB près de la broche 24 côté droit)
    idx = 1
    for uy in UYS:
        c("C%d" % idx, (UX - 5.2, uy - 1.3), 90, "100nF", "+3V3", "GND")
        idx += 1
        c("C%d" % idx, (UX + 5.2, uy - 1.3), 90, "100nF", "+5V", "GND")
        idx += 1
    c("C11", (24, 10), 90, "10uF", "+5V", "GND", "C_0805_2012Metric")
    c("C12", (30, 38), 90, "10uF", "+3V3", "GND", "C_0805_2012Metric")

    return comps


# ---------------------------------------------------------------------------
# Peigne J_EXP (hérité phaseA — seule la position du bord change)
# ---------------------------------------------------------------------------

def make_jexp(board, nets, board_w):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("loci_lvc", "JEXP_34_GOLDFINGERS"))
    fp.SetReference("J_EXP")
    fp.SetValue("EDGE_34_GOLDFINGERS")
    fp.SetAttributes(pcbnew.FP_SMD | pcbnew.FP_EXCLUDE_FROM_BOM
                     | pcbnew.FP_EXCLUDE_FROM_POS_FILES | pcbnew.FP_BOARD_ONLY)
    fp.SetPosition(V(0, 0))

    pitch = 2.54
    finger_w = 1.6
    finger_l = 6.0
    x_edge = board_w - 0.05  # retrait 0,05 mm = demi-largeur du trait Edge.Cuts
    y0 = 25.0 - 8 * pitch    # k=1 en haut, 17 positions centrées

    for k in range(1, 18):
        y = y0 + (k - 1) * pitch
        for num, layer, mask in ((2 * k, pcbnew.F_Cu, pcbnew.F_Mask),
                                 (2 * k - 1, pcbnew.B_Cu, pcbnew.B_Mask)):
            pad = pcbnew.PAD(fp)
            pad.SetNumber(str(num))
            pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD)
            pad.SetShape(pcbnew.PAD_SHAPE_RECT)
            pad.SetSize(V(finger_l, finger_w))
            ls = pcbnew.LSET()
            ls.AddLayer(layer)
            ls.AddLayer(mask)          # masque ouvert (pas de vernis)
            pad.SetLayerSet(ls)        # pas de pâte à braser
            pad.SetPosition(V(x_edge - finger_l / 2.0, y))
            pad.SetNet(nets[JEXP_NETS[num]])
            fp.Add(pad)

    ref = fp.Reference()
    ref.SetPosition(V(board_w - 10, 2.5))
    board.Add(fp)
    return fp


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

    # --- contour 110 x 50 ------------------------------------------------
    W, H = 110.0, 50.0
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

    make_jexp(board, nets, W)

    # --- zones GND (2 faces), en retrait du peigne -----------------------
    zone_pts = [(0.4, 0.4), (W - 7.5, 0.4), (W - 7.5, H - 0.4), (0.4, H - 0.4)]
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNetCode(nets["GND"].GetNetCode())
        z.SetAssignedPriority(0)
        z.SetLocalClearance(MM(0.3))
        z.SetMinThickness(MM(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        z.AddPolygon(pcbnew.VECTOR_VECTOR2I([V(x, y) for x, y in zone_pts]))
        z.SetZoneName("GND_%s" % pcbnew.BOARD.GetStandardLayerName(layer))
        board.Add(z)

    pcbnew.SaveBoard(out_path, board)
    board2 = pcbnew.LoadBoard(out_path)
    filler = pcbnew.ZONE_FILLER(board2)
    filler.Fill(board2.Zones())
    pcbnew.SaveBoard(out_path, board2)
    print("OK :", out_path)
    print("Empreintes :", len(board2.GetFootprints()))
    print("Nets :", board2.GetNetCount())


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "loci_lvc.kicad_pcb")
