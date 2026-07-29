# CHANGELOG — hardware/phaseA

## 2026-07-29 — Génération initiale des fichiers de fabrication JLCPCB
- `gen_pcb.py` : construction scriptée complète de `phaseA.kicad_pcb`
  depuis SPEC_NETLIST.md (contour 160×50 mm, 39 empreintes, 99 nets,
  peigne 34 doigts custom bord droit, DIN-7 270° custom, zones GND F/B,
  netclasses Default 0,25 mm / Power 0,5 mm, vias 0,6/0,3).
- `route.py` : pipeline de routage freerouting (export DSN pcbnew →
  patch DSN des doigts → freerouting 2.1.0 headless → import SES →
  re-remplissage zones). Freerouting 2.2.4 écarté (exige Java 25,
  Java 21 installé).
- `make_fab.py` : BOM.csv + CPL.csv au format JLCPCB (LCSC vérifiés :
  TXS0108EPWR=C17206, LM393DR=C67470, passifs basic parts).
- `Makefile` : cibles pcb / drc / gerbers / fab.
- `QUESTIONS.md` : ambiguïtés de la spec et interprétations retenues
  (sens du peigne, AQY212GH THT/CMS, DIN-7 mécanique, J_SND.2, jack pad 3).
- `COMMANDE.md` : options JLCPCB (2 couches, 1,6 mm, ENIG,
  gold fingers + biseau 45°, assemblage top).
- Corrections en cours de génération : orientation des headers 2×N
  (broches hors carte), jack alim affleurant le bord haut, géométrie
  DIN-7 (cercle Ø7 mm, pastilles 2,4/1,3), retrait 0,05 mm des doigts
  (DRC bord de cuivre).
- Gerbers + perçage Excellon exportés dans `gerbers/` (voir Makefile).
