import sys, pcbnew
from pcbnew import VECTOR2I, FromMM, ToMM
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
    return True

def add_via(pos):
    v = pcbnew.PCB_VIA(b); v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); v.SetPosition(pos)
    v.SetDrill(int(VIA_DR)); v.SetWidth(int(VIA_D)); v.SetNetCode(gnd); b.Add(v)

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
        xs = [ol.CPoint(k).x for k in range(n)]; ys = [ol.CPoint(k).y for k in range(n)]
        area = abs(sum(ToMM(xs[k])*ToMM(ys[(k+1) % n]) - ToMM(xs[(k+1) % n])*ToMM(ys[k]) for k in range(n)))/2
        if area >= 150:   # gros polygone = plan principal, on saute
            continue
        # echantillonner des points a l'interieur du polygone
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        placed = False
        step = MM(0.25)
        y = y0
        while y <= y1 and not placed:
            x = x0
            while x <= x1:
                pt = VECTOR2I(x, y)
                if polys.Contains(pt) and via_ok(pt):
                    add_via(pt); added += 1; placed = True; break
                x += step
            y += step

pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(sys.argv[1], b)
print("vias ilot ajoutes:", added)
