#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_pcb.py — Phase A « Bandeau LOCI » : génération complète du PCB
(phaseA.kicad_pcb) depuis la spécification SPEC_NETLIST.md.

Reproductible : python3 gen_pcb.py [sortie.kicad_pcb]
- contour 160 x 50 mm
- toutes les empreintes placées, tous les nets affectés
- peigne J_EXP 34 doigts custom (pas 2,54, doigts 1,6 x 6 mm,
  F.Cu = pairs / B.Cu = impairs, masque ouvert, bord droit)
- DIN-7 femelle 270° custom (pads THT en arc, base DIN 41524/45329)
- zones GND sur F.Cu et B.Cu
- netclasses : Default 0,25 mm / Power (+5V,+3V3,GND) 0,5 mm, via 0,6/0,3

NE MODIFIE PAS LA NETLIST : toute la connectivité vient de SPEC_NETLIST.md.
"""

import sys
import math
import pcbnew
from pcbnew import VECTOR2I, FromMM

FP_LIB = "/usr/share/kicad/footprints"

MM = FromMM


def V(x, y):
    return VECTOR2I(MM(x), MM(y))


# ---------------------------------------------------------------------------
# Nets (STRICTEMENT d'après SPEC_NETLIST.md)
# ---------------------------------------------------------------------------

NET_NAMES = (
    ["GND", "+5V", "+3V3", "OE_EN"]
    + ["A%d" % i for i in range(16)]
    + ["D%d" % i for i in range(8)]
    + ["RW", "PHI2", "IO_n", "RST_n", "IRQ_n", "ROMDIS_n", "MAP_n", "IOCTL_n"]
    + ["PA%d" % i for i in range(8)]
    + ["STROBE_n", "ACK", "TAPE_OUT_3V3", "MOTOR_3V3", "TAPE_IN_3V3"]
    + ["A5V%d" % i for i in range(16)]
    + ["D5V%d" % i for i in range(8)]
    + ["RW5", "PHI2_5", "IO5_n", "RST5_n", "IRQ5_n", "ROMDIS5_n", "MAP5_n", "IOCTL5_n"]
    + ["PRN_D%d" % i for i in range(8)]
    + ["PRN_STB_n", "PRN_ACK"]
    + ["TAPE_OUT_DIN", "TAPE_IN_DIN", "IN_PLUS", "IN_MINUS", "SOUND",
       "MOTOR_A", "MOTOR_B", "K1_LED_A"]
)

# J_EXP : doigt -> net (numérotation officielle Atmos, annexe 11)
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

# TXS0108E : brochage vérifié (TI SCES642H)
TXS_A_PINS = ["1", "3", "4", "5", "6", "7", "8", "9"]           # A1..A8
TXS_B_PINS = ["20", "18", "17", "16", "15", "14", "13", "12"]   # B1..B8
CTRL_3V3 = ["RW", "PHI2", "IO_n", "RST_n", "IRQ_n", "ROMDIS_n", "MAP_n", "IOCTL_n"]
CTRL_5V = ["RW5", "PHI2_5", "IO5_n", "RST5_n", "IRQ5_n", "ROMDIS5_n", "MAP5_n", "IOCTL5_n"]


def txs_netmap(a_nets, b_nets):
    m = {"2": "+3V3", "19": "+5V", "10": "OE_EN", "11": "GND"}
    for p, n in zip(TXS_A_PINS, a_nets):
        if n:
            m[p] = n
    for p, n in zip(TXS_B_PINS, b_nets):
        if n:
            m[p] = n
    return m


# reference -> (lib, footprint, position mm, rot deg, valeur, netmap {pad: net})
def build_component_table():
    comps = []

    def add(ref, lib, fp, pos, rot, value, netmap):
        comps.append(dict(ref=ref, lib=lib, fp=fp, pos=pos, rot=rot,
                          value=value, nets=netmap))

    # --- TXS0108E U1..U6 -------------------------------------------------
    add("U1", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (127, 28), 0,
        "TXS0108EPWR",
        txs_netmap(["A%d" % i for i in range(8)], ["A5V%d" % i for i in range(8)]))
    add("U2", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (127, 37), 0,
        "TXS0108EPWR",
        txs_netmap(["A%d" % i for i in range(8, 16)], ["A5V%d" % i for i in range(8, 16)]))
    add("U3", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (127, 19), 0,
        "TXS0108EPWR",
        txs_netmap(["D%d" % i for i in range(8)], ["D5V%d" % i for i in range(8)]))
    add("U4", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (127, 10), 0,
        "TXS0108EPWR", txs_netmap(CTRL_3V3, CTRL_5V))
    add("U5", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (97, 17), 0,
        "TXS0108EPWR",
        txs_netmap(["PA%d" % i for i in range(8)], ["PRN_D%d" % i for i in range(8)]))
    add("U6", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (110, 17), 0,
        "TXS0108EPWR",
        txs_netmap(["STROBE_n", "ACK"] + [None] * 6,
                   ["PRN_STB_n", "PRN_ACK"] + [None] * 6))

    # --- LM393 (U7) : 1=OUT1, 2=IN-, 3=IN+, 4=GND, 5/6=GND (comp. 2), 7=NC, 8=VCC
    add("U7", "Package_SO", "SOIC-8_3.9x4.9mm_P1.27mm", (52, 15), 0, "LM393",
        {"1": "TAPE_IN_3V3", "2": "IN_MINUS", "3": "IN_PLUS", "4": "GND",
         "5": "GND", "6": "GND", "8": "+3V3"})

    # --- PhotoMOS AQY212GH (K1) : 1=LED+, 2=LED-, 3/4=contacts
    add("K1", "Package_DIP", "DIP-4_W7.62mm", (21, 21), 0, "AQY212GH",
        {"1": "K1_LED_A", "2": "GND", "3": "MOTOR_A", "4": "MOTOR_B"})

    # --- J_ULX_A (2x20) --------------------------------------------------
    jua = {}
    for i in range(16):
        jua[str(i + 1)] = "A%d" % i
    for i in range(8):
        jua[str(i + 17)] = "D%d" % i
    for p, n in zip(range(25, 33), CTRL_3V3):
        jua[str(p)] = n
    jua["33"] = "OE_EN"
    for p in (34, 35, 36, 39, 40):
        jua[str(p)] = "GND"
    jua["37"] = "+3V3"
    jua["38"] = "+3V3"
    add("J_ULX_A", "Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical",
        (14, 46.54), 90, "Conn_02x20", jua)

    # --- J_ULX_B (2x10) --------------------------------------------------
    jub = {}
    for i in range(8):
        jub[str(i + 1)] = "PA%d" % i
    jub.update({"9": "STROBE_n", "10": "ACK", "11": "TAPE_OUT_3V3",
                "12": "MOTOR_3V3", "13": "TAPE_IN_3V3",
                "14": "GND", "15": "GND", "16": "GND",
                "17": "+3V3", "18": "+3V3", "19": "GND", "20": "GND"})
    add("J_ULX_B", "Connector_PinHeader_2.54mm", "PinHeader_2x10_P2.54mm_Vertical",
        (72, 46.54), 90, "Conn_02x10", jub)

    # --- J_PRN (2x10, brochage imprimante Atmos) -------------------------
    jprn = {}
    prn_odd = ["PRN_STB_n", "PRN_D0", "PRN_D1", "PRN_D2", "PRN_D3",
               "PRN_D4", "PRN_D5", "PRN_D6", "PRN_D7", "PRN_ACK"]
    for k, n in enumerate(prn_odd):
        jprn[str(2 * k + 1)] = n
    for p in range(2, 21, 2):
        jprn[str(p)] = "GND"
    add("J_PRN", "Connector_PinHeader_2.54mm", "PinHeader_2x10_P2.54mm_Vertical",
        (84, 7.04), 90, "Conn_02x10", jprn)

    # --- J_PWR jack 5,5/2,1 : 1=centre(+5V), 2=manchon(GND), 3=switch NC
    add("J_PWR", "Connector_BarrelJack", "BarrelJack_Horizontal",
        (10, 2.1), 90, "Jack_5.5x2.1", {"1": "+5V", "2": "GND"})

    # --- J_SND 1x02 ------------------------------------------------------
    add("J_SND", "Connector_PinHeader_2.54mm", "PinHeader_1x02_P2.54mm_Vertical",
        (48, 5), 90, "Conn_01x02", {"1": "SOUND", "2": "GND"})

    # --- R / C (0603 / 0805) --------------------------------------------
    def r(ref, pos, rot, val, n1, n2):
        add(ref, "Resistor_SMD", "R_0603_1608Metric", pos, rot, val,
            {"1": n1, "2": n2})

    def c(ref, pos, rot, val, n1, n2, size="C_0603_1608Metric"):
        add(ref, "Capacitor_SMD", size, pos, rot, val, {"1": n1, "2": n2})

    r("R_OE", (65, 41), 90, "10k", "OE_EN", "GND")
    r("R1", (33, 20), 90, "10k", "TAPE_OUT_3V3", "TAPE_OUT_DIN")
    r("R2", (36, 20), 90, "1k", "TAPE_OUT_DIN", "GND")
    r("R3", (44, 21), 90, "100k", "IN_PLUS", "+3V3")
    r("R4", (47, 21), 90, "100k", "IN_PLUS", "GND")
    r("R5", (50, 21), 90, "100k", "IN_PLUS", "IN_MINUS")
    r("R6", (56, 21), 90, "10k", "TAPE_IN_3V3", "+3V3")
    r("R7", (21, 27), 0, "470", "MOTOR_3V3", "K1_LED_A")
    c("C1", (42, 12), 0, "1uF", "TAPE_IN_DIN", "IN_PLUS")
    c("C2", (53, 21), 90, "100nF", "IN_MINUS", "GND")

    # Découplage : 2 x 100 nF par TXS (VCCA pin 2 côté gauche, VCCB pin 19 côté droit)
    idx = 3
    for uref, (ux, uy) in (("U1", (127, 28)), ("U2", (127, 37)), ("U3", (127, 19)),
                           ("U4", (127, 10)), ("U5", (97, 17)), ("U6", (110, 17))):
        c("C%d" % idx, (ux - 5.2, uy - 1.3), 90, "100nF", "+3V3", "GND")
        idx += 1
        c("C%d" % idx, (ux + 5.2, uy - 1.3), 90, "100nF", "+5V", "GND")
        idx += 1

    c("C15", (21, 13), 90, "10uF", "+5V", "GND", "C_0805_2012Metric")
    c("C16", (59, 40), 90, "10uF", "+3V3", "GND", "C_0805_2012Metric")

    return comps


# ---------------------------------------------------------------------------
# Empreintes custom
# ---------------------------------------------------------------------------

def make_jexp(board, nets):
    """Peigne 34 doigts : pas 2,54 mm, doigts 1,6 x 6 mm depuis le bord droit,
    F.Cu = pairs (2k), B.Cu = impairs (2k-1), position k = 1..17 du haut vers
    le bas, masque ouvert, pas de pâte."""
    fp = pcbnew.FOOTPRINT(board)
    fp.SetReference("J_EXP")
    fp.SetValue("EDGE_34_GOLDFINGERS")
    fp.SetAttributes(pcbnew.FP_SMD | pcbnew.FP_EXCLUDE_FROM_BOM
                     | pcbnew.FP_EXCLUDE_FROM_POS_FILES | pcbnew.FP_BOARD_ONLY)
    fp.SetPosition(V(0, 0))

    pitch = 2.54
    finger_w = 1.6
    finger_l = 6.0
    x_edge = 159.95  # retrait 0,05 mm = demi-largeur du trait Edge.Cuts
    y0 = 25.0 - 8 * pitch  # k=1 en haut, 17 positions centrées (4,68..45,32)

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
    ref.SetPosition(V(150, 2.5))
    board.Add(fp)
    return fp


def make_jcas(board, nets):
    """DIN-7 femelle 270° THT (base DIN 41524/45329) : 7 pads sur un arc de
    270°, cercle de broches Ø7,0 mm (DIN 45329 : rayon 3,5 mm), 45° entre
    broches, ordre physique 6-1-4-2-5-3-7, broche 2 au milieu (vers
    l'intérieur de la carte), ouverture vers le bord haut.
    Perçage 1,4 mm / pastille 2,6 mm.
    Brochage Atmos : 1=TAPE_OUT_DIN 2=GND 3=TAPE_IN_DIN 4=SOUND 5=NC
    6=MOTOR_A 7=MOTOR_B."""
    cx, cy = 34.0, 10.0
    pin_nets = {"1": "TAPE_OUT_DIN", "2": "GND", "3": "TAPE_IN_DIN",
                "4": "SOUND", "6": "MOTOR_A", "7": "MOTOR_B"}

    fp = pcbnew.FOOTPRINT(board)
    fp.SetReference("J_CAS")
    fp.SetValue("DIN41524_7pin_270deg_Female")
    fp.SetAttributes(pcbnew.FP_THROUGH_HOLE | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
    fp.SetPosition(V(0, 0))

    order = ["6", "1", "4", "2", "5", "3", "7"]
    r = 3.5
    for i, num in enumerate(order):
        ang = math.radians(90 + (i - 3) * 45)  # broche 2 vers +y (intérieur)
        x = cx + r * math.cos(ang)
        y = cy + r * math.sin(ang)
        pad = pcbnew.PAD(fp)
        pad.SetNumber(num)
        pad.SetAttribute(pcbnew.PAD_ATTRIB_PTH)
        pad.SetShape(pcbnew.PAD_SHAPE_CIRCLE)
        pad.SetSize(V(2.6, 2.6))
        pad.SetDrillSize(V(1.4, 1.4))
        pad.SetLayerSet(pad.PTHMask())
        pad.SetPosition(V(x, y))
        if num in pin_nets:
            pad.SetNet(nets[pin_nets[num]])
        fp.Add(pad)

    # cercle sérigraphie (corps ~14 mm)
    circ = pcbnew.PCB_SHAPE(fp)
    circ.SetShape(pcbnew.SHAPE_T_CIRCLE)
    circ.SetCenter(V(cx, cy))
    circ.SetEnd(V(cx + 7.0, cy))
    circ.SetLayer(pcbnew.F_SilkS)
    circ.SetWidth(MM(0.12))
    fp.Add(circ)

    ref = fp.Reference()
    ref.SetPosition(V(cx, cy + 9))
    board.Add(fp)
    return fp


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

def build(out_path):
    board = pcbnew.CreateEmptyBoard()
    board.SetFileName(out_path)

    # --- règles ----------------------------------------------------------
    ds = board.GetDesignSettings()
    ds.m_CopperEdgeClearance = 0  # nécessaire pour les doigts affleurant le bord
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

    # --- nets ------------------------------------------------------------
    nets = {}
    for name in NET_NAMES:
        ni = pcbnew.NETINFO_ITEM(board, name)
        board.Add(ni)
        nets[name] = ni

    # --- contour 160 x 50 ------------------------------------------------
    W, H = 160.0, 50.0
    corners = [(0, 0), (W, 0), (W, H), (0, H)]
    for i in range(4):
        seg = pcbnew.PCB_SHAPE(board)
        seg.SetShape(pcbnew.SHAPE_T_SEGMENT)
        seg.SetStart(V(*corners[i]))
        seg.SetEnd(V(*corners[(i + 1) % 4]))
        seg.SetLayer(pcbnew.Edge_Cuts)
        seg.SetWidth(MM(0.1))
        board.Add(seg)

    # --- empreintes bibliothèque ----------------------------------------
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

    # --- empreintes custom ----------------------------------------------
    make_jexp(board, nets)
    make_jcas(board, nets)

    # --- zones GND (2 faces) --------------------------------------------
    # Le pourtour évite la région du peigne (x > 152,5) pour laisser les
    # doigts dorés isolés, et reste à 0,4 mm des autres bords.
    zone_pts = [(0.4, 0.4), (152.5, 0.4), (152.5, 49.6), (0.4, 49.6)]
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(board)
        z.SetLayer(layer)
        z.SetNetCode(nets["GND"].GetNetCode())
        z.SetAssignedPriority(0)
        z.SetLocalClearance(MM(0.3))
        z.SetMinThickness(MM(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
        z.SetThermalReliefGap(MM(0.3))
        z.SetThermalReliefSpokeWidth(MM(0.4))
        z.AddPolygon(pcbnew.VECTOR_VECTOR2I([V(x, y) for x, y in zone_pts]))
        z.SetZoneName("GND_%s" % pcbnew.BOARD.GetStandardLayerName(layer))
        board.Add(z)

    # Sauvegarde puis rechargement (le remplissage de zones exige un
    # BOARD attaché à un projet, sinon segfault de ZONE_FILLER).
    pcbnew.SaveBoard(out_path, board)
    board2 = pcbnew.LoadBoard(out_path)
    filler = pcbnew.ZONE_FILLER(board2)
    filler.Fill(board2.Zones())
    pcbnew.SaveBoard(out_path, board2)
    print("OK :", out_path)
    print("Empreintes :", len(board2.GetFootprints()))
    print("Nets :", board2.GetNetCount())


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "phaseA.kicad_pcb")
