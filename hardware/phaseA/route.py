#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
route.py — routage de phaseA.kicad_pcb.

Pipeline :
1. export Specctra DSN (pcbnew) ;
2. patch DSN : les doigts du peigne (6 mm jusqu'au bord) sont réduits à
   leurs 2 mm intérieurs pour le routeur (sinon freerouting les considère
   en violation avec le contour et refuse de router) — le .kicad_pcb
   garde les vrais doigts ;
3. freerouting headless (java -jar freerouting.jar -de x.dsn -do x.ses -mp 5) ;
4. import du .ses, largeurs par netclasses (Default 0,25 / Power 0,5) ;
5. re-remplissage des zones GND et sauvegarde.

Le critère d'acceptation (0 erreur DRC, 0 net non routé) est vérifié par
`make drc` ensuite.
"""
import os
import subprocess
import sys
import pcbnew

BOARD = sys.argv[1] if len(sys.argv) > 1 else "phaseA.kicad_pcb"
JAR = "freerouting.jar"
DSN = "phaseA.dsn"
DSN_FR = "phaseA_fr.dsn"
SES = "phaseA.ses"


def export_dsn():
    b = pcbnew.LoadBoard(BOARD)
    if not pcbnew.ExportSpecctraDSN(b, DSN):
        raise RuntimeError("export DSN impossible")
    s = open(DSN).read()
    s = s.replace("(shape (rect B.Cu -3000 -800 3000 800))",
                  "(shape (rect B.Cu -3000 -800 -1000 800))")
    s = s.replace("(shape (rect F.Cu -3000 -800 3000 800))",
                  "(shape (rect F.Cu -3000 -800 -1000 800))")
    open(DSN_FR, "w").write(s)


def run_freerouting():
    cmd = ["java", "-Djava.awt.headless=true", "-jar", JAR,
           "-de", DSN_FR, "-do", SES, "-mp", "5"]
    print("freerouting :", " ".join(cmd))
    subprocess.run(cmd, check=True, timeout=3600)
    if not os.path.exists(SES):
        raise RuntimeError("pas de fichier .ses produit")


def import_ses():
    b = pcbnew.LoadBoard(BOARD)
    if not pcbnew.ImportSpecctraSES(b, SES):
        raise RuntimeError("import SES impossible")
    filler = pcbnew.ZONE_FILLER(b)
    filler.Fill(b.Zones())
    pcbnew.SaveBoard(BOARD, b)
    # bilan connectivité
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
