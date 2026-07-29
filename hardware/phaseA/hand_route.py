#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Finition manuelle du routage phase A (état r5 conservé) :
 - 6 liaisons courtes en segments directs ;
 - D0/D1/IO_n par recherche de couloir libre (horizontal B.Cu, verticaux F.Cu) ;
 - vias de couture pour les îlots GND ;
 - re-remplissage des zones. DRC à lancer ensuite (make drc)."""
import math
import pcbnew

B = pcbnew.LoadBoard("phaseA.kicad_pcb")
mm = pcbnew.FromMM
CLR = 0.18          # marge (mm) autour des obstacles (règle carte : 0,2 net à net)
W_SIG = 0.25
W_PWR = 0.5

def netcode(name):
    nets = B.GetNetsByName()
    it = nets.find(name)
    assert it != nets.end(), name
    return it.value()[1]

# ------------------------------------------------------------------
# Obstacles existants par couche (segments + vias + pads), en mm
# ------------------------------------------------------------------
def collect_obstacles():
    obs = {pcbnew.F_Cu: [], pcbnew.B_Cu: []}
    for t in B.GetTracks():
        if t.GetClass() == "PCB_TRACK":
            l = t.GetLayer()
            obs[l].append(("seg",
                           pcbnew.ToMM(t.GetStart().x), pcbnew.ToMM(t.GetStart().y),
                           pcbnew.ToMM(t.GetEnd().x), pcbnew.ToMM(t.GetEnd().y),
                           pcbnew.ToMM(t.GetWidth()) / 2, t.GetNetCode()))
        else:
            for l in (pcbnew.F_Cu, pcbnew.B_Cu):
                obs[l].append(("dot",
                               pcbnew.ToMM(t.GetPosition().x), pcbnew.ToMM(t.GetPosition().y),
                               0, 0, pcbnew.ToMM(t.GetWidth()) / 2, t.GetNetCode()))
    for fp in B.GetFootprints():
        for p in fp.Pads():
            # modèle « stade » : segment selon l'axe long, rayon = petite dim/2
            sx, sy = pcbnew.ToMM(p.GetSizeX()), pcbnew.ToMM(p.GetSizeY())
            cx, cy = pcbnew.ToMM(p.GetPosition().x), pcbnew.ToMM(p.GetPosition().y)
            r = min(sx, sy) / 2
            half = abs(sx - sy) / 2
            ang = math.radians(p.GetOrientation().AsDegrees())
            if sx >= sy:
                dx, dy = math.cos(ang) * half, -math.sin(ang) * half
            else:
                dx, dy = math.sin(ang) * half, math.cos(ang) * half
            layers = ([pcbnew.F_Cu, pcbnew.B_Cu]
                      if p.GetAttribute() == pcbnew.PAD_ATTRIB_PTH
                      else [p.GetLayer()])
            for l in layers:
                if l in obs:
                    obs[l].append(("seg", cx - dx, cy - dy, cx + dx, cy + dy,
                                   r, p.GetNetCode()))
    return obs

def seg_pt_dist(x1, y1, x2, y2, px, py):
    dx, dy = x2 - x1, y2 - y1
    L2 = dx * dx + dy * dy
    if L2 == 0:
        return math.hypot(px - x1, py - y1)
    t = max(0, min(1, ((px - x1) * dx + (py - y1) * dy) / L2))
    return math.hypot(px - (x1 + t * dx), py - (y1 + t * dy))

def seg_seg_dist(a, b_, c, d):
    (x1, y1), (x2, y2) = a, b_
    (x3, y3), (x4, y4) = c, d
    def ccw(p, q, r):
        return (r[1]-p[1])*(q[0]-p[0]) - (q[1]-p[1])*(r[0]-p[0])
    if (ccw(a,b_,c)*ccw(a,b_,d) < 0) and (ccw(c,d,a)*ccw(c,d,b_) < 0):
        return 0.0
    return min(seg_pt_dist(x1,y1,x2,y2,x3,y3), seg_pt_dist(x1,y1,x2,y2,x4,y4),
               seg_pt_dist(x3,y3,x4,y4,x1,y1), seg_pt_dist(x3,y3,x4,y4,x2,y2))

def free(obs, layer, x1, y1, x2, y2, halfw, net):
    for o in obs[layer]:
        kind, ox1, oy1, ox2, oy2, orad, onet = o
        if onet == net:
            continue
        if kind == "seg":
            d = seg_seg_dist((x1, y1), (x2, y2), (ox1, oy1), (ox2, oy2))
        else:
            d = seg_pt_dist(x1, y1, x2, y2, ox1, oy1)
        if d < halfw + orad + CLR:
            return False
    return True

def add_seg(x1, y1, x2, y2, layer, width, net):
    t = pcbnew.PCB_TRACK(B)
    t.SetStart(pcbnew.VECTOR2I(mm(x1), mm(y1)))
    t.SetEnd(pcbnew.VECTOR2I(mm(x2), mm(y2)))
    t.SetWidth(mm(width))
    t.SetLayer(layer)
    t.SetNet(B.FindNet(net))
    B.Add(t)

def add_via(x, y, net):
    v = pcbnew.PCB_VIA(B)
    v.SetPosition(pcbnew.VECTOR2I(mm(x), mm(y)))
    v.SetDrill(mm(0.3))
    v.SetWidth(pcbnew.PADSTACK.ALL_LAYERS, mm(0.6)) if hasattr(pcbnew, "PADSTACK") else v.SetWidth(mm(0.6))
    v.SetViaType(pcbnew.VIATYPE_THROUGH)
    v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
    v.SetNet(B.FindNet(net))
    B.Add(v)

# ------------------------------------------------------------------
# 1. Liaisons courtes (segments directs, F.Cu)
# ------------------------------------------------------------------
obs = collect_obstacles()
shorts = [
    ("+5V",  (129.86, 7.72),  (132.2, 9.47),  W_PWR),
    ("+5V",  (99.86, 14.72),  (102.2, 16.48), W_PWR),
    ("+3V3", (124.14, 16.73), (121.8, 18.48), W_PWR),
    ("+3V3", (124.14, 25.73), (121.8, 27.48), W_PWR),
    ("+3V3", (124.14, 7.72),  (121.8, 9.47),  W_PWR),
    ("OE_EN", (124.14, 12.93), (126.75, 24.54), W_SIG),
]
for net, a, c, w in shorts:
    nc = netcode(net)
    if free(obs, pcbnew.F_Cu, a[0], a[1], c[0], c[1], w/2, nc):
        add_seg(a[0], a[1], c[0], c[1], pcbnew.F_Cu, w, nc)
        obs[pcbnew.F_Cu].append(("seg", a[0], a[1], c[0], c[1], w/2, nc))
        print("court OK direct:", net, a, c)
    else:
        # L en deux segments via un coude, essai des deux coudes
        done = False
        for k in ((a[0], c[1]), (c[0], a[1])):
            if (free(obs, pcbnew.F_Cu, a[0], a[1], k[0], k[1], w/2, nc) and
                    free(obs, pcbnew.F_Cu, k[0], k[1], c[0], c[1], w/2, nc)):
                add_seg(a[0], a[1], k[0], k[1], pcbnew.F_Cu, w, nc)
                add_seg(k[0], k[1], c[0], c[1], pcbnew.F_Cu, w, nc)
                obs[pcbnew.F_Cu] += [("seg", a[0], a[1], k[0], k[1], w/2, nc),
                                     ("seg", k[0], k[1], c[0], c[1], w/2, nc)]
                print("court OK en L:", net)
                done = True
                break
        if not done:
            print("court ECHEC:", net, a, c)

# ------------------------------------------------------------------
# 2. Traversées D0 / D1 / IO_n : via près du départ, couloir B.Cu,
#    via près de l'arrivée, approche F.Cu
# ------------------------------------------------------------------
longs = [
    ("D0",   (34.32, 46.54), (124.14, 16.07)),
    ("D1",   (34.32, 44.0),  (124.14, 17.38)),
    ("IO_n", (47.02, 46.54), (124.14, 9.03)),
]
for net, a, c in longs:
    nc = netcode(net)
    routed = False
    for ycorr in [y / 2.0 for y in range(4, 100)]:   # couloirs y=2..49,5
        # via depart (proche de a), via arrivee (proche de c)
        vax, vay = a[0] + 1.0, ycorr
        vcx, vcy = c[0] - 1.2, ycorr
        segs = [
            (pcbnew.F_Cu, a[0], a[1], vax, vay),      # descente F.Cu
            (pcbnew.B_Cu, vax, vay, vcx, vcy),        # couloir B.Cu
            (pcbnew.F_Cu, vcx, vcy, c[0], c[1]),      # approche F.Cu
        ]
        if all(free(obs, l, x1, y1, x2, y2, W_SIG/2, nc) for l, x1, y1, x2, y2 in segs):
            ok_vias = all(
                free(obs, l, vx, vy, vx, vy, 0.3, nc)
                for vx, vy in ((vax, vay), (vcx, vcy))
                for l in (pcbnew.F_Cu, pcbnew.B_Cu))
            if not ok_vias:
                continue
            for l, x1, y1, x2, y2 in segs:
                add_seg(x1, y1, x2, y2, l, W_SIG, nc)
                obs[l].append(("seg", x1, y1, x2, y2, W_SIG/2, nc))
            for vx, vy in ((vax, vay), (vcx, vcy)):
                add_via(vx, vy, nc)
                for l in (pcbnew.F_Cu, pcbnew.B_Cu):
                    obs[l].append(("dot", vx, vy, 0, 0, 0.3, nc))
            print(f"traversee OK: {net} couloir y={ycorr}")
            routed = True
            break
    if not routed:
        print("traversee ECHEC:", net)

filler = pcbnew.ZONE_FILLER(B)
filler.Fill(B.Zones())
pcbnew.SaveBoard("phaseA.kicad_pcb", B)
print("sauve")
