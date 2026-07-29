#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_fab.py — génère BOM.csv et CPL.csv (format JLCPCB) depuis phaseA.kicad_pcb.

- BOM.csv  : Comment,Designator,Footprint,LCSC Part # (parts groupées)
- CPL.csv  : Designator,Val,Package,Mid X,Mid Y,Rotation,Layer
  (uniquement les composants CMS assemblés côté top ; les THT — connecteurs,
  K1 DIP — sont listés dans la BOM avec LCSC=TBD et exclus du CPL)

Origine CPL : coin bas-gauche de la carte (0;50 mm en coords KiCad),
Y vers le haut, conformément aux attentes JLCPCB.
"""
import csv
import sys
import pcbnew

BOARD = sys.argv[1] if len(sys.argv) > 1 else "phaseA.kicad_pcb"

# Références LCSC (vérifiées 07/2026 — re-vérifier stock avant commande)
LCSC = {
    ("TXS0108EPWR", "TSSOP-20_4.4x6.5mm_P0.65mm"): "C17206",
    ("LM393", "SOIC-8_3.9x4.9mm_P1.27mm"): "C67470",
    ("10k", "R_0603_1608Metric"): "C25804",
    ("1k", "R_0603_1608Metric"): "C21190",
    ("100k", "R_0603_1608Metric"): "C25803",
    ("470", "R_0603_1608Metric"): "C23179",
    ("1M", "R_0603_1608Metric"): "C22935",
    ("100nF", "C_0603_1608Metric"): "C14663",
    ("1uF", "C_0603_1608Metric"): "C15849",
    ("10uF", "C_0805_2012Metric"): "C15850",
    ("AQY212GH", "DIP-4_W7.62mm"): "TBD",          # THT (cf. QUESTIONS.md §3/§8)
    ("Conn_02x20", "PinHeader_2x20_P2.54mm_Vertical"): "TBD",
    ("Conn_02x10", "PinHeader_2x10_P2.54mm_Vertical"): "TBD",
    ("Conn_01x02", "PinHeader_1x02_P2.54mm_Vertical"): "TBD",
    ("Jack_5.5x2.1", "BarrelJack_Horizontal"): "TBD",
    ("DIN41524_7pin_270deg_Female", ""): "TBD",
}

# CMS assemblés côté top (JLC assembly). Les autres : BOM seulement.
SMT_FOOTPRINTS = ("TSSOP-20", "SOIC-8", "R_0603", "C_0603", "C_0805")


def fpid_name(fp):
    fid = fp.GetFPID().GetLibItemName()
    return str(fid)


def main():
    board = pcbnew.LoadBoard(BOARD)
    h = pcbnew.ToMM(board.GetBoardEdgesBoundingBox().GetBottom())

    groups = {}   # (value, fpname) -> [refs]
    cpl_rows = []
    for fp in sorted(board.GetFootprints(), key=lambda f: f.GetReference()):
        ref = fp.GetReference()
        val = fp.GetValue()
        name = fpid_name(fp)
        if ref == "J_EXP":
            continue  # peigne = motif cuivre de la carte, pas un composant
        groups.setdefault((val, name), []).append(ref)
        if any(name.startswith(p) for p in SMT_FOOTPRINTS):
            pos = fp.GetPosition()
            cpl_rows.append([
                ref, val, name,
                "%.4fmm" % pcbnew.ToMM(pos.x),
                "%.4fmm" % (h - pcbnew.ToMM(pos.y)),   # Y vers le haut
                "%.1f" % fp.GetOrientationDegrees(),
                "Top" if fp.GetLayer() == pcbnew.F_Cu else "Bottom",
            ])

    with open("BOM.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
        for (val, name), refs in sorted(groups.items(), key=lambda kv: kv[1][0]):
            code = LCSC.get((val, name)) or LCSC.get((val, "")) or "TBD"
            w.writerow([val, ",".join(sorted(refs)), name, code])

    with open("CPL.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["Designator", "Val", "Package", "Mid X", "Mid Y",
                    "Rotation", "Layer"])
        for row in cpl_rows:
            w.writerow(row)

    print("BOM.csv : %d lignes ; CPL.csv : %d composants CMS top"
          % (len(groups), len(cpl_rows)))


if __name__ == "__main__":
    main()
