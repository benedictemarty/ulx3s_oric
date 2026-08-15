import sys, pcbnew
from pcbnew import VECTOR2I, ToMM, FromMM
MM = FromMM
b = pcbnew.LoadBoard(sys.argv[1])
gnd = b.GetNetsByName()["GND"].GetNetCode()
ITEMS = list(b.GetTracks()) + [p for fp in b.GetFootprints() for p in fp.Pads()]
VIA_D, VIA_DR, CLR = MM(0.4), MM(0.2), MM(0.1)

def via_ok(pos):
    sh = pcbnew.SHAPE_CIRCLE(pos, VIA_D//2)
    for it in ITEMS:
        if it.GetNetCode() == gnd: continue
        try: s = it.GetEffectiveShape()
        except Exception: continue
        if s.Collide(sh, int(CLR)): return False
    x, y = ToMM(pos.x), ToMM(pos.y)
    return 0.6 < x < 119.8 and 0.6 < y < 49.4

def add_via(pos):
    v = pcbnew.PCB_VIA(b); v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetPosition(pos)
    v.SetDrill(int(VIA_DR)); v.SetWidth(int(VIA_D)); v.SetNetCode(gnd); b.Add(v); ITEMS.append(v)

added = 0
for z in b.Zones():
    if z.GetNetCode() != gnd or z.GetLayer() not in (pcbnew.F_Cu, pcbnew.B_Cu):
        continue
    L = z.GetLayer()
    polys = z.GetFilledPolysList(L)
    for oi in range(polys.OutlineCount()):
        ol = polys.Outline(oi)
        n = ol.PointCount()
        if n < 3: continue
        xs = [ol.CPoint(k).x for k in range(n)]
        ys = [ol.CPoint(k).y for k in range(n)]
        # aire approx (shoelace) en mm2
        area = abs(sum(ToMM(xs[k])*ToMM(ys[(k+1) % n]) - ToMM(xs[(k+1) % n])*ToMM(ys[k]) for k in range(n)))/2
        cx, cy = sum(xs)//n, sum(ys)//n
        if area < 300:   # ilot : petit polygone -> le coudre au plan
            placed = False
            base = VECTOR2I(cx, cy)
            for dx in range(-12, 13):
                for dy in range(-12, 13):
                    vp = VECTOR2I(cx+MM(dx*0.3), cy+MM(dy*0.3))
                    if via_ok(vp):
                        add_via(vp); added += 1; placed = True; break
                if placed: break

pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(sys.argv[1], b)
b2 = pcbnew.LoadBoard(sys.argv[1]); b2.BuildConnectivity()
print("vias ilots ajoutes:", added)
print("non connectees restantes:", b2.GetConnectivity().GetUnconnectedCount(True))
