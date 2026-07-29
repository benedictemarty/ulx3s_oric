#!/usr/bin/env python3
import subprocess, sys, glob
import pcbnew

BOARD = "phaseA.kicad_pcb"

# 1. purge
b = pcbnew.LoadBoard(BOARD)
for t in list(b.GetTracks()):
    b.Remove(t)
assert len(list(b.GetTracks())) == 0, "purge incomplete"
pcbnew.SaveBoard(BOARD, b)
print("purge OK", flush=True)

# 2. export DSN + patches (doigts 2mm + bord virtuel 156,3)
assert pcbnew.ExportSpecctraDSN(b, "phaseA_r4.dsn")
s = open("phaseA_r4.dsn").read()
s = s.replace("(shape (rect B.Cu -3000 -800 3000 800))",
              "(shape (rect B.Cu -3000 -800 -1000 800))")
s = s.replace("(shape (rect F.Cu -3000 -800 3000 800))",
              "(shape (rect F.Cu -3000 -800 -1000 800))")
patched = s.replace(
    "(path pcb 0  160000 -50000  0 -50000  0 0  160000 0  160000 -50000)",
    "(path pcb 0  156300 -50000  0 -50000  0 0  156300 0  156300 -50000)")
assert patched != s, "patch bord virtuel non applique (motif introuvable)"
open("phaseA_r4.dsn", "w").write(patched)
print("DSN r4 exporte et patche", flush=True)

# 3. freerouting 2.2.4
jdk = glob.glob("/tmp/jdk-25*")[0]
r = subprocess.run([f"{jdk}/bin/java", "-Djava.awt.headless=true",
                    "-jar", "freerouting-2.2.4.jar",
                    "-de", "phaseA_r4.dsn", "-do", "phaseA_r4.ses",
                    "-mp", "100", "-mt", "4"],
                   capture_output=True, text=True, timeout=480)
for line in r.stdout.splitlines():
    if "session completed" in line:
        print(line[-120:], flush=True)

# 4. import via le parseur
r = subprocess.run(["python3", "import_ses.py", "phaseA_r4.ses"],
                   capture_output=True, text=True)
for line in r.stdout.splitlines():
    if "pistes=" in line:
        print(line, flush=True)

# 5. verification finale
b2 = pcbnew.LoadBoard(BOARD)
tracks = [t for t in b2.GetTracks() if t.GetClass() == "PCB_TRACK"]
vias = [t for t in b2.GetTracks() if t.GetClass() == "PCB_VIA"]
print("board final:", len(tracks), "pistes,", len(vias), "vias", flush=True)
