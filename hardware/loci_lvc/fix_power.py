import sys, json, pcbnew
from pcbnew import VECTOR2I, FromMM, ToMM
MM = FromMM
b = pcbnew.LoadBoard(sys.argv[1]); DRC = sys.argv[2]
NETS = ["+5V", "+3V3"]
ITEMS = list(b.GetTracks()) + [p for fp in b.GetFootprints() for p in fp.Pads()]
VIA_D, VIA_DR, TW, CLR = MM(0.45), MM(0.2), MM(0.3), MM(0.1)

def add_via(pos, nc):
    v = pcbnew.PCB_VIA(b); v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetPosition(pos)
    v.SetDrill(int(VIA_DR)); v.SetWidth(int(VIA_D)); v.SetNetCode(nc); b.Add(v)
def add_track(a, c, nc):
    t = pcbnew.PCB_TRACK(b); t.SetStart(a); t.SetEnd(c); t.SetLayer(pcbnew.In2_Cu)
    t.SetWidth(int(TW)); t.SetNetCode(nc); b.Add(t)

import re
d = json.load(open(DRC))
done = []
for x in d.get("unconnected_items", []):
    ns = set(); pts = []
    for it in x.get("items", []):
        m = re.search(r"\[([^\]]+)\]", it.get("description", ""))
        if m: ns.add(m.group(1))
        p = it.get("pos", {}); pts.append(VECTOR2I(MM(p["x"]), MM(p["y"])))
    net = list(ns)[0] if len(ns) == 1 else None
    if net in NETS and len(pts) >= 2:
        nc = b.FindNet(net).GetNetCode()
        add_via(pts[0], nc); add_via(pts[1], nc)
        add_track(pts[0], pts[1], nc)
        done.append(net)

pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(sys.argv[1], b)
b2 = pcbnew.LoadBoard(sys.argv[1]); b2.BuildConnectivity()
print("alim reliees:", done)
print("non connectees restantes:", b2.GetConnectivity().GetUnconnectedCount(True))
