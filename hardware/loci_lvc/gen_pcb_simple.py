#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_pcb_simple.py — Carte adaptateur LOCI, VERSION SIMPLIFIEE (facon LOCI reelle).

Principe : les entrees des peripheriques Oric sont 5 V-tolerantes (seuil TTL ~2 V),
donc les SORTIES du FPGA (A0-A15, PHI2, R/W, /IO) pilotent le peigne EN DIRECT en
3,3 V — aucun transceiver. Seul le bus de donnees (bidirectionnel) a besoin d'un
transceiver, et les entrees de controle (venant du peripherique, 5 V) d'un petit
buffer abaisseur. Resultat : 1x 74LVC4245A + 1x 74LVC245 + 1x BSS138 -> board
peu dense, routable en 2 couches.
"""
import sys, pcbnew
from pcbnew import VECTOR2I, FromMM
FP_LIB = "/usr/share/kicad/footprints"
MM = FromMM

def V(x, y): return VECTOR2I(MM(x), MM(y))

# --- Nets ---
CTRL_FPGA = ["IRQ_n", "ROMDIS_n", "MAP_n", "IOCTL_n"]
CTRL_5V   = ["IRQ5_n", "ROMDIS5_n", "MAP5_n", "IOCTL5_n"]
NET_NAMES = (
    ["GND", "+5V", "+3V3", "XCVR_DIR", "XCVR_OE_n"]
    + ["A%d" % i for i in range(16)]          # adresses : DIRECT FPGA->peigne
    + ["PHI2", "RW", "IO_n"]                    # controle sortie : DIRECT
    + ["D%d" % i for i in range(8)]            # data cote FPGA
    + ["D5V%d" % i for i in range(8)]          # data cote peigne (via U1)
    + CTRL_FPGA + CTRL_5V                       # controle entree (via U2)
    + ["RST_n", "RST5_n"]                       # reset (via Q1)
)

# J_EXP : doigt -> net (numerotation Atmos ; adresses/PHI2/RW/IO = nets directs)
JEXP_NETS = {
    1: "MAP5_n", 2: "ROMDIS5_n", 3: "PHI2", 4: "RST5_n",
    5: "IO_n", 6: "IOCTL5_n", 7: "RW", 8: "IRQ5_n",
    9: "D5V2", 10: "D5V0", 11: "A3", 12: "D5V1",
    13: "A0", 14: "D5V6", 15: "A1", 16: "D5V3",
    17: "A2", 18: "D5V4", 19: "D5V5", 20: "A4",
    21: "A5", 22: "D5V7", 23: "A6", 24: "A15",
    25: "A7", 26: "A14", 27: "A8", 28: "A13",
    29: "A9", 30: "A12", 31: "A10", 32: "A11",
    33: "+5V", 34: "GND",
}

def build_components():
    comps = []
    def add(ref, lib, fp, pos, rot, val, nets):
        comps.append(dict(ref=ref, lib=lib, fp=fp, pos=pos, rot=rot, value=val, nets=nets))

    # U1 = 74LVC4245A (data D0-D7). 1=VCCA 2=DIR 3..10=A1..A8 11/12/13=GND
    # 14..21=B8..B1 22=/OE 24=VCCB. A=FPGA(3V3), B=peigne(5V).
    m1 = {"1": "+3V3", "24": "+5V", "2": "XCVR_DIR", "22": "XCVR_OE_n",
          "11": "GND", "12": "GND", "13": "GND"}
    for i in range(8):                      # A1..A8 = D0..D7
        m1[str(3 + i)] = "D%d" % i
    for i in range(8):                      # B1..B8 = D5V0..D5V7 (pins 21..14)
        m1[str(21 - i)] = "D5V%d" % i
    add("U1", "Package_SO", "TSSOP-24_4.4x7.8mm_P0.65mm", (72, 16), 0,
        "SN74LVCC3245APW", m1)

    # U2 = 74LVC245 (entrees controle, 5V->3V3). alim 3V3, DIR=H (A->B).
    # 1=DIR 2..9=A1..A8 10=GND 11..18=B8..B1 19=/OE 20=VCC.
    m2 = {"1": "+3V3", "20": "+3V3", "10": "GND", "19": "GND"}
    for i in range(4):                      # A1..A4 = IRQ5..IOCTL5 (peigne)
        m2[str(2 + i)] = CTRL_5V[i]
    for i in range(4, 8):                   # A5..A8 inutilises -> GND
        m2[str(2 + i)] = "GND"
    for i in range(4):                      # B1..B4 = IRQ_n..IOCTL_n (pins 18..15)
        m2[str(18 - i)] = CTRL_FPGA[i]
    for i in range(4, 8):                   # B5..B8 inutilises -> GND (pins 14..11)
        m2[str(18 - i)] = "GND"
    add("U2", "Package_SO", "TSSOP-20_4.4x6.5mm_P0.65mm", (72, 32), 0,
        "SN74LVC245APW", m2)

    # Q1 = BSS138 (/RESET drain ouvert) SOT-23 1=G 2=S 3=D
    add("Q1", "Package_TO_SOT_SMD", "SOT-23", (50, 40), 0, "BSS138",
        {"1": "+3V3", "2": "RST_n", "3": "RST5_n"})

    # J_ULX (2x20) cote FPGA
    jux = {}
    for p, n in zip(range(1, 9), ["RW", "PHI2", "IO_n", "RST_n"] + CTRL_FPGA):
        jux[str(p)] = n
    jux["9"] = "XCVR_DIR"; jux["10"] = "XCVR_OE_n"
    for i in range(8): jux[str(11 + i)] = "D%d" % i
    for i in range(16): jux[str(19 + i)] = "A%d" % i
    for p in (35, 36, 39, 40): jux[str(p)] = "GND"
    jux["37"] = "+3V3"; jux["38"] = "+3V3"
    add("J_ULX", "Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical",
        (14, 46.54), 90, "Conn_02x20", jux)

    # J_PWR jack 5V
    add("J_PWR", "Connector_BarrelJack", "BarrelJack_Horizontal", (10, 3), 90,
        "Jack_5.5x2.1", {"1": "+5V", "2": "GND"})

    def r(ref, pos, rot, n1, n2):
        add(ref, "Resistor_SMD", "R_0603_1608Metric", pos, rot, "10k", {"1": n1, "2": n2})
    def c(ref, pos, rot, n1, n2, sz="C_0603_1608Metric"):
        add(ref, "Capacitor_SMD", sz, pos, rot, "100nF", {"1": n1, "2": n2})
    r("R1", (46, 40), 90, "RST_n", "+3V3")
    r("R2", (54, 40), 90, "RST5_n", "+5V")
    r("R3", (60, 26), 90, "XCVR_OE_n", "+3V3")
    r("R4", (64, 26), 90, "XCVR_DIR", "GND")
    c("C1", (66, 14), 90, "+3V3", "GND")
    c("C2", (78, 14), 90, "+5V", "GND")
    c("C3", (66, 30), 90, "+3V3", "GND")
    c("C4", (30, 10), 90, "+5V", "GND", "C_0805_2012Metric")
    c("C5", (30, 40), 90, "+3V3", "GND", "C_0805_2012Metric")
    return comps

def make_jexp(board, nets, W):
    fp = pcbnew.FOOTPRINT(board)
    fp.SetFPID(pcbnew.LIB_ID("loci_lvc", "JEXP_34"))
    fp.SetReference("J_EXP"); fp.SetValue("EDGE_34")
    fp.SetAttributes(pcbnew.FP_SMD | pcbnew.FP_EXCLUDE_FROM_BOM
                     | pcbnew.FP_EXCLUDE_FROM_POS_FILES | pcbnew.FP_BOARD_ONLY)
    fp.SetPosition(V(0, 0))
    pitch, fw, fl = 2.54, 1.6, 6.0
    x_edge = W - 0.05; y0 = 25.0 - 8 * pitch
    for k in range(1, 18):
        y = y0 + (k - 1) * pitch
        for num, layer, mask in ((2*k, pcbnew.F_Cu, pcbnew.F_Mask),
                                 (2*k-1, pcbnew.B_Cu, pcbnew.B_Mask)):
            pad = pcbnew.PAD(fp); pad.SetNumber(str(num))
            pad.SetAttribute(pcbnew.PAD_ATTRIB_SMD); pad.SetShape(pcbnew.PAD_SHAPE_RECT)
            pad.SetSize(V(fl, fw)); ls = pcbnew.LSET(); ls.AddLayer(layer); ls.AddLayer(mask)
            pad.SetLayerSet(ls); pad.SetPosition(V(x_edge - fl/2.0, y))
            pad.SetNet(nets[JEXP_NETS[num]]); fp.Add(pad)
    board.Add(fp); return fp

def build(out):
    b = pcbnew.CreateEmptyBoard(); b.SetFileName(out)
    ds = b.GetDesignSettings(); ds.m_CopperEdgeClearance = 0
    ns = ds.m_NetSettings; d = ns.GetDefaultNetclass()
    d.SetTrackWidth(MM(0.25)); d.SetClearance(MM(0.2)); d.SetViaDiameter(MM(0.6)); d.SetViaDrill(MM(0.3))
    pw = pcbnew.NETCLASS("Power")
    pw.SetTrackWidth(MM(0.5)); pw.SetClearance(MM(0.2)); pw.SetViaDiameter(MM(0.6)); pw.SetViaDrill(MM(0.3))
    ns.SetNetclass("Power", pw)
    for p in ("+5V", "+3V3", "GND"): ns.SetNetclassPatternAssignment(p, "Power")
    nets = {}
    for n in NET_NAMES:
        ni = pcbnew.NETINFO_ITEM(b, n); b.Add(ni); nets[n] = ni
    W, H = 120.0, 50.0
    cor = [(0, 0), (W, 0), (W, H), (0, H)]
    for i in range(4):
        s = pcbnew.PCB_SHAPE(b); s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(V(*cor[i])); s.SetEnd(V(*cor[(i+1) % 4])); s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(MM(0.1)); b.Add(s)
    for comp in build_components():
        fp = pcbnew.FootprintLoad("%s/%s.pretty" % (FP_LIB, comp["lib"]), comp["fp"])
        if fp is None: raise RuntimeError("empreinte introuvable: " + comp["fp"])
        fp.SetReference(comp["ref"]); fp.SetValue(comp["value"])
        fp.SetOrientationDegrees(comp["rot"]); fp.SetPosition(V(*comp["pos"]))
        for pad in fp.Pads():
            n = comp["nets"].get(pad.GetNumber())
            if n: pad.SetNet(nets[n])
        b.Add(fp)
    make_jexp(b, nets, W)
    zpts = [(0.4, 0.4), (W-7.5, 0.4), (W-7.5, H-0.4), (0.4, H-0.4)]
    for layer in (pcbnew.F_Cu, pcbnew.B_Cu):
        z = pcbnew.ZONE(b); z.SetLayer(layer); z.SetNetCode(nets["GND"].GetNetCode())
        z.SetAssignedPriority(0); z.SetLocalClearance(MM(0.3)); z.SetMinThickness(MM(0.25))
        z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        z.AddPolygon(pcbnew.VECTOR_VECTOR2I([V(x, y) for x, y in zpts]))
        b.Add(z)
    pcbnew.SaveBoard(out, b)
    b2 = pcbnew.LoadBoard(out); pcbnew.ZONE_FILLER(b2).Fill(b2.Zones()); pcbnew.SaveBoard(out, b2)
    print("OK:", out, "| empreintes:", len(b2.GetFootprints()), "| nets:", b2.GetNetCount())

if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "loci_lvc_simple.kicad_pcb")
