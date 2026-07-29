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
    # 1) Doigts vus par le routeur : seulement leurs 2 mm intérieurs
    #    (le .kicad_pcb garde les vrais doigts 6 mm jusqu'au bord).
    s = s.replace("(shape (rect B.Cu -3000 -800 3000 800))",
                  "(shape (rect B.Cu -3000 -800 -1000 800))")
    s = s.replace("(shape (rect F.Cu -3000 -800 3000 800))",
                  "(shape (rect F.Cu -3000 -800 -1000 800))")
    # 2) Bord droit virtuel à 156,3 mm : interdit au routeur de poser
    #    pistes/vias au-dessus de la partie réelle des doigts.
    s = s.replace(
        "(path pcb 0  160000 -50000  0 -50000  0 0  160000 0  160000 -50000)",
        "(path pcb 0  156300 -50000  0 -50000  0 0  156300 0  156300 -50000)")
    # 3) Alim routée en 0,4 mm par le routeur : une piste 0,5 mm ne peut
    #    pas atteindre un pad TSSOP (pas 0,65 mm) en respectant 0,2 mm
    #    d'isolation (0,65-0,25-0,2 = 0,2 limite). 0,4 mm laisse la marge.
    s = s.replace("(width 500)", "(width 400)")
    open(DSN_FR, "w").write(s)


def run_freerouting():
    cmd = ["java", "-Djava.awt.headless=true", "-jar", JAR,
           "-de", DSN_FR, "-do", SES, "-mp", "5"]
    print("freerouting :", " ".join(cmd))
    subprocess.run(cmd, check=True, timeout=3600)
    if not os.path.exists(SES):
        raise RuntimeError("pas de fichier .ses produit")


def import_ses():
    # Répare les noms de composants vides (empreintes custom sans FPID
    # dans d'anciennes révisions du board) qui cassent le parseur SES.
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
