#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Relie les fragments non connectes de nets donnes (positions issues du DRC) :
un via a chaque extremite (sur la piste existante) + piste In2/In3 entre les deux."""
import sys, json, re, heapq, pcbnew
from pcbnew import VECTOR2I, FromMM, ToMM
MM = FromMM
BOARD, DRC = sys.argv[1], sys.argv[2]
NETS = sys.argv[3].split(",")
b = pcbnew.LoadBoard(BOARD)

TW = MM(0.25); VIA_D, VIA_DR = MM(0.45), MM(0.2); CLR = MM(0.12)
STEP = 0.4; NX, NY = int(120/STEP)+1, int(50/STEP)+1
ITEMS = list(b.GetTracks()) + [p for fp in b.GetFootprints() for p in fp.Pads()]

def is_through(it):
    if isinstance(it, pcbnew.PCB_VIA): return True
    if isinstance(it, pcbnew.PAD): return it.GetDrillSize().x > 0
    return False
def on_layer(it, L):
    if is_through(it): return True
    try: return it.IsOnLayer(L)
    except Exception: return it.GetLayer()==L
def collide(shape, L, nc, m):
    for it in ITEMS:
        if it.GetNetCode()==nc: continue
        if L is not None and not on_layer(it, L): continue
        try: s=it.GetEffectiveShape()
        except Exception: continue
        if s.Collide(shape, m): return True
    return False
def via_ok(p, nc):
    if collide(pcbnew.SHAPE_CIRCLE(p, VIA_D//2), None, nc, int(CLR)): return False
    x,y=ToMM(p.x),ToMM(p.y); return 0.7<x<119.7 and 0.7<y<49.3
def seg_ok(a,c,L,nc): return not collide(pcbnew.SHAPE_SEGMENT(a,c,TW),L,nc,int(CLR))
def add_track(a,c,L,nc):
    t=pcbnew.PCB_TRACK(b);t.SetStart(a);t.SetEnd(c);t.SetLayer(L);t.SetWidth(int(TW));t.SetNetCode(nc);b.Add(t);ITEMS.append(t)
def add_via(p,nc):
    v=pcbnew.PCB_VIA(b);v.SetViaType(pcbnew.VIATYPE_THROUGH);v.SetLayerPair(pcbnew.F_Cu,pcbnew.B_Cu)
    v.SetPosition(p);v.SetDrill(int(VIA_DR));v.SetWidth(int(VIA_D));v.SetNetCode(nc);b.Add(v);ITEMS.append(v)
def cell(p): return (int(round(ToMM(p.x)/STEP)),int(round(ToMM(p.y)/STEP)))
def point(i,j): return VECTOR2I(MM(i*STEP),MM(j*STEP))
DIRS=[(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)]
def astar(a,c,nc,L):
    ca,cb=cell(a),cell(c)
    blk=set()
    for i in range(NX):
        for j in range(NY):
            if collide(pcbnew.SHAPE_CIRCLE(point(i,j),TW//2),L,nc,int(CLR)+int(MM(STEP*0.4))): blk.add((i,j))
    blk.discard(ca); blk.discard(cb)
    h=lambda q:abs(q[0]-cb[0])+abs(q[1]-cb[1])
    oq=[(h(ca),0,ca)];came={ca:None};g={ca:0};seen=set()
    while oq:
        _,gc,q=heapq.heappop(oq)
        if q==cb: break
        if q in seen: continue
        seen.add(q)
        for dx,dy in DIRS:
            n=(q[0]+dx,q[1]+dy)
            if not(0<=n[0]<NX and 0<=n[1]<NY) or n in blk: continue
            ng=gc+(1.4 if dx and dy else 1.0)
            if ng<g.get(n,1e9): g[n]=ng;came[n]=q;heapq.heappush(oq,(ng+h(n),ng,n))
    if cb not in came: return None
    path=[];q=cb
    while q is not None: path.append(q);q=came[q]
    return path[::-1]
def route(a,c,nc):
    for L in (pcbnew.In2_Cu, pcbnew.In3_Cu):
        if seg_ok(a,c,L,nc): add_track(a,c,L,nc); return True
        p=astar(a,c,nc,L)
        if p:
            pts=[a]+[point(i,j) for (i,j) in p[1:-1]]+[c]
            if all(seg_ok(pts[k],pts[k+1],L,nc) for k in range(len(pts)-1)):
                for k in range(len(pts)-1): add_track(pts[k],pts[k+1],L,nc)
                return True
    return False

d=json.load(open(DRC))
ok=[]
for x in d.get("unconnected_items",[]):
    ns=set(); pts=[]
    for it in x.get("items",[]):
        m=re.search(r"\[([^\]]+)\]",it.get("description",""))
        if m: ns.add(m.group(1))
        p=it.get("pos",{}); pts.append(VECTOR2I(MM(p["x"]),MM(p["y"])))
    net=list(ns)[0] if len(ns)==1 else None
    if net in NETS and len(pts)>=2:
        nc=b.FindNet(net).GetNetCode()
        if via_ok(pts[0],nc): add_via(pts[0],nc)
        if via_ok(pts[1],nc): add_via(pts[1],nc)
        if route(pts[0],pts[1],nc): ok.append(net)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())
pcbnew.SaveBoard(BOARD, b)
b2=pcbnew.LoadBoard(BOARD);b2.BuildConnectivity()
print("relies:",ok)
print("non connectees restantes:",b2.GetConnectivity().GetUnconnectedCount(True))
