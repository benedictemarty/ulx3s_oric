#!/bin/bash
# Boucle de routage : purge -> freerouting -> import -> DRC ;
# s'arrête quand seules des paires GND restent non connectées.
set -u
D=/home/bmarty/ulx3s_oric/hardware/phaseA
JDK=$(ls -d /tmp/jdk-25* | head -1)
cd "$D"
for i in 1 2 3 4 5 6; do
  echo "=== tentative $i ==="
  python3 - <<'PYEOF'
import re
src = open("phaseA.kicad_pcb").read()
out=[]; i=0
lines=src.splitlines(keepends=True); n=len(lines)
while i<n:
    l=lines[i]
    if re.match(r'\t\((segment|via)\b', l):
        depth=l.count("(")-l.count(")"); i+=1
        while depth>0 and i<n:
            depth+=lines[i].count("(")-lines[i].count(")"); i+=1
        continue
    out.append(l); i+=1
open("phaseA.kicad_pcb","w").write("".join(out))
PYEOF
  rm -f phaseA_loop.ses
  timeout 300 "$JDK/bin/java" -Djava.awt.headless=true -jar freerouting-2.2.4.jar \
    -de phaseA_r15.dsn -do phaseA_loop.ses -mp 120 -mt 4 2>&1 | grep -E "session completed" | tail -1
  [ -f phaseA_loop.ses ] || { echo "pas de ses"; continue; }
  python3 import_ses.py phaseA_loop.ses 2>/dev/null | grep "pistes="
  kicad-cli pcb drc --format json -o drc_loop.json phaseA.kicad_pcb >/dev/null 2>&1
  python3 - <<'PYEOF'
import json, sys
d = json.load(open("drc_loop.json"))
errs = [v for v in d["violations"] if v["severity"]=="error"]
uc = d.get("unconnected_items", [])
sig = set()
for u in uc:
    for it in u.get("items", [])[:1]:
        desc = it.get("description","")
        if "[" in desc:
            net = desc.split("[")[1].split("]")[0]
            if net != "GND":
                sig.add(net)
print(f"erreurs={len(errs)} nonconn={len(uc)} signaux_manquants={sorted(sig)}")
sys.exit(0 if (not sig and len(errs)==0) else 1)
PYEOF
  if [ $? -eq 0 ]; then
    echo "=== SUCCES tentative $i : routage signal complet, 0 erreur DRC ==="
    exit 0
  fi
done
echo "=== BOUCLE EPUISEE sans succès complet ==="
exit 1
