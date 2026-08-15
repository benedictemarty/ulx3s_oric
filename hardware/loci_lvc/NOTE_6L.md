# Variante 6 couches — routage du bus complet (WIP)

**Date :** 2026-08-15 · **Auteur :** bmarty

## Pourquoi 6 couches
La carte 2 couches (routage `route.py` d'origine) **plafonne à ~12–17 signaux
non routés** : le faisceau côté 5 V (puces → peigne) est trop dense pour 2 (voire
4) couches. **Le passage en 6 couches (4 couches de signal + 2 plans GND internes)
débloque le routage** : freerouting ferme alors tout sauf ~11 liaisons.

## État de `loci_lvc_6l2.kicad_pcb`
- **6 couches** : F.Cu / **In1.Cu (plan GND)** / In2.Cu (signal) / In3.Cu (signal) /
  **In4.Cu (plan GND)** / B.Cu. Plans GND aussi sur F/B.
- **Routé à ~90 % par freerouting, PROPRE : 0 violation DRC.**
- **Reste 25 liaisons non connectées** :
  - **11 signaux** dont les pads côté puce sont **recouverts par le faisceau**
    (freerouting ne les ferme pas — limite de placement, pas de couches) ;
  - **14 masses** à coudre (vias pad → plans In1/In4).

## Reproduire le board propre
```sh
python3 gen_pcb.py loci_lvc_6l2.kicad_pcb      # board vierge (placement)
python3 convert_6layer.py loci_lvc_6l2.kicad_pcb  # 6 couches + plans GND In1/In4
python3 route_6l2.py                            # freerouting (mp 100) + import
# -> ~25 non connectees, 0 violation
```

## Finition (à faire dans KiCad, à la main)
Les 25 dernières liaisons se finissent **dans l'éditeur KiCad** :
- router les **11 signaux** sur In2/In3 (couches internes libres) ;
- **coudre les 14 masses** (poser un via GND près de chaque pad GND non connecté ;
  les plans In1/In4 sont continus → tout via GND legal connecte).

## ⚠️ Scripts de complétion automatique — NON fiables
`route_signals.py`, `fix_gnd2.py`, `finish_islands.py`, `route_pair.py`,
`fix_power.py`, `cleanup_vias.py`, `find_island2.py` : tentatives de complétion
**automatique** des 25 liaisons. **Elles connectent mais introduisent des
courts-circuits / violations DRC** (détection de collision insuffisante). À
utiliser seulement comme base ; **préférer la finition manuelle KiCad** pour un
board réellement fabricable.

## Règles / fabrication
- Réglé fabricable JLCPCB 6 couches (trace 0,15 / via 0,3-0,6 possible).
- Une fois les 25 liaisons finies et DRC propre : générer Gerbers + drill + BOM
  (BOM = `SPEC_NETLIST.md`) + placement, puis commander en PCBA.
