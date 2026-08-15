#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
route.py — routage de loci_lvc.kicad_pcb (pipeline hérité de phaseA).

1. export Specctra DSN (pcbnew) ;
2. patch DSN : doigts du peigne réduits à leurs 2 mm intérieurs pour le
   routeur + bord droit virtuel à 116,3 mm (partie réelle des doigts
   interdite aux pistes/vias) + alim 0,4 mm (accès pads TSSOP) ;
3. freerouting headless ;
4. import du .ses, re-remplissage zones, sauvegarde ;
5. critère : 0 liaison non routée (puis `kicad-cli pcb drc`).
"""
import os
import subprocess
import sys
import pcbnew

BOARD = "loci_lvc_simple.kicad_pcb"
JAR = "../phaseA/freerouting.jar"
DSN = "loci_lvc_simple.dsn"
DSN_FR = "loci_lvc_simple_fr.dsn"
SES = "loci_lvc_simple.ses"


def export_dsn():
    b = pcbnew.LoadBoard(BOARD)
    if not pcbnew.ExportSpecctraDSN(b, DSN):
        raise RuntimeError("export DSN impossible")
    s = open(DSN).read()
    s = s.replace("(shape (rect B.Cu -3000 -800 3000 800))",
                  "(shape (rect B.Cu -3000 -800 -1000 800))")
    s = s.replace("(shape (rect F.Cu -3000 -800 3000 800))",
                  "(shape (rect F.Cu -3000 -800 -1000 800))")
    s = s.replace(
        "(path pcb 0  120000 -50000  0 -50000  0 0  120000 0  120000 -50000)",
        "(path pcb 0  116300 -50000  0 -50000  0 0  116300 0  116300 -50000)")
    s = s.replace("(width 500)", "(width 400)")
    open(DSN_FR, "w").write(s)


def run_freerouting():
    cmd = ["java", "-Djava.awt.headless=true", "-jar", JAR,
           "-de", DSN_FR, "-do", SES, "-mp", "60"]
    print("freerouting :", " ".join(cmd))
    subprocess.run(cmd, check=True, timeout=3600)
    if not os.path.exists(SES):
        raise RuntimeError("pas de fichier .ses produit")


def import_ses():
    s = open(SES).read()
    s = s.replace('(component \n      (place', '(component "CUSTOM_FP"\n      (place')
    s = s.replace('(component ::1\n      (place', '(component "CUSTOM_FP1"\n      (place')
    open(SES, "w").write(s)
    b = pcbnew.LoadBoard(BOARD)
    if not pcbnew.ImportSpecctraSES(b, SES):
        raise RuntimeError("import SES impossible")
    filler = pcbnew.ZONE_FILLER(b)
    filler.Fill(b.Zones())
    pcbnew.SaveBoard(BOARD, b)
    b = pcbnew.LoadBoard(BOARD)
    b.BuildConnectivity()
    conn = b.GetConnectivity()
    n = conn.GetUnconnectedCount(True)
    print("liaisons non routées restantes :", n)
    return n


if __name__ == "__main__":
    export_dsn()
    run_freerouting()
    n = import_ses()
    sys.exit(0 if n == 0 else 1)
