#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Routage du board 6 couches loci_lvc_6l2 (4 couches signal)."""
import os, subprocess, sys, pcbnew
BOARD = "loci_lvc_6l2.kicad_pcb"
JAR = "../phaseA/freerouting.jar"
DSN = "loci_lvc_6l2.dsn"
DSN_FR = "loci_lvc_6l2_fr.dsn"
SES = "loci_lvc_6l2.ses"

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
           "-de", DSN_FR, "-do", SES, "-mp", "100"]
    print("freerouting :", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True, timeout=7200)

def import_ses():
    s = open(SES).read()
    s = s.replace('(component \n      (place', '(component "CUSTOM_FP"\n      (place')
    s = s.replace('(component ::1\n      (place', '(component "CUSTOM_FP1"\n      (place')
    open(SES, "w").write(s)
    b = pcbnew.LoadBoard(BOARD)
    if not pcbnew.ImportSpecctraSES(b, SES):
        raise RuntimeError("import SES impossible")
    pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    pcbnew.SaveBoard(BOARD, b)
    b = pcbnew.LoadBoard(BOARD); b.BuildConnectivity()
    n = b.GetConnectivity().GetUnconnectedCount(True)
    print("liaisons non routees restantes :", n, flush=True)
    return n

if __name__ == "__main__":
    export_dsn()
    run_freerouting()
    n = import_ses()
    sys.exit(0 if n == 0 else 1)
