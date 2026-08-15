import sys, json, re, pcbnew
from pcbnew import ToMM
b = pcbnew.LoadBoard(sys.argv[1]); DRC = sys.argv[2]
gnd = b.GetNetsByName()["GND"].GetNetCode()
d = json.load(open(DRC))
bad = []
for x in d.get("unconnected_items", []):
    for it in x.get("items", []):
        if it.get("description", "").startswith("Via"):
            p = it["pos"]; bad.append((round(p["x"], 2), round(p["y"], 2)))
# retirer les vias GND isoles aux positions signalees
removed = 0
for t in list(b.GetTracks()):
    if isinstance(t, pcbnew.PCB_VIA) and t.GetNetCode() == gnd:
        pos = (round(ToMM(t.GetPosition().x), 2), round(ToMM(t.GetPosition().y), 2))
        for bx, by in bad:
            if abs(pos[0]-bx) < 0.2 and abs(pos[1]-by) < 0.2:
                b.Remove(t); removed += 1; break
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(sys.argv[1], b)
b2 = pcbnew.LoadBoard(sys.argv[1]); b2.BuildConnectivity()
print("vias parasites retires:", removed)
print("non connectees restantes:", b2.GetConnectivity().GetUnconnectedCount(True))
