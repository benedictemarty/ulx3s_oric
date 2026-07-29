#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Import manuel d'un fichier session Specctra (.ses) dans phaseA.kicad_pcb.

L'import natif pcbnew.ImportSpecctraSES échouant silencieusement, on parse
le .ses (s-expressions) et on crée les PCB_TRACK / PCB_VIA directement.
(resolution um 10) => 1 unité = 1/10 µm ; axe Y inversé vs KiCad.
"""
import sys
import pcbnew

BOARD = "phaseA.kicad_pcb"
SES = "phaseA.ses"


def tokenize(text):
    text = text.replace("(", " ( ").replace(")", " ) ")
    return text.split()


def parse(tokens):
    it = iter(tokens)
    def walk():
        out = []
        for tok in it:
            if tok == "(":
                out.append(walk())
            elif tok == ")":
                return out
            else:
                out.append(tok)
        return out
    return walk()


def find_all(tree, key):
    found = []
    if isinstance(tree, list):
        if tree and tree[0] == key:
            found.append(tree)
        for sub in tree:
            found.extend(find_all(sub, key))
    return found


text = open(SES).read()
tree = parse(tokenize(text))

res = find_all(tree, "resolution")[0]
assert res[1] == "um", res
per = int(res[2])
def to_iu(v):
    return pcbnew.FromMM(float(v) / per / 1000.0)

b = pcbnew.LoadBoard(BOARD)
layers = {"F.Cu": pcbnew.F_Cu, "B.Cu": pcbnew.B_Cu}
nets = b.GetNetsByName()

def net_of(name):
    item = nets.find(name.strip('"'))
    return None if item == nets.end() else item.value()[1]

added_t = added_v = 0
missing = []
for netsec in find_all(find_all(tree, "network_out")[0], "net"):
    name = netsec[1]
    net = net_of(name)
    if net is None:
        missing.append(name)
        continue
    for wire in find_all(netsec, "wire"):
        for path in find_all(wire, "path"):
            layer, width, coords = path[1], int(path[2]), path[3:]
            pts = [(to_iu(coords[i]), -to_iu(coords[i + 1]))
                   for i in range(0, len(coords), 2)]
            for a, c in zip(pts, pts[1:]):
                t = pcbnew.PCB_TRACK(b)
                t.SetStart(pcbnew.VECTOR2I(a[0], a[1]))
                t.SetEnd(pcbnew.VECTOR2I(c[0], c[1]))
                t.SetWidth(to_iu(width))
                t.SetLayer(layers[layer])
                t.SetNet(net)
                b.Add(t)
                added_t += 1
    for via in find_all(netsec, "via"):
        x, y = via[-2], via[-1]
        v = pcbnew.PCB_VIA(b)
        v.SetPosition(pcbnew.VECTOR2I(to_iu(x), -to_iu(y)))
        v.SetDrill(pcbnew.FromMM(0.3))
        v.SetWidth(pcbnew.FromMM(0.6))
        v.SetViaType(pcbnew.VIATYPE_THROUGH)
        v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu)
        v.SetNet(net)
        b.Add(v)
        added_v += 1

filler = pcbnew.ZONE_FILLER(b)
filler.Fill(b.Zones())
pcbnew.SaveBoard(BOARD, b)

b = pcbnew.LoadBoard(BOARD)
b.BuildConnectivity()
n = b.GetConnectivity().GetUnconnectedCount(True)
print(f"pistes={added_t} vias={added_v} nets_inconnus={missing} non_connectes={n}")
