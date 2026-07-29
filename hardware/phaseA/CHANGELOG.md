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

## 2026-07-29 (b) — Intégration des révisions de spec du jour
- SPEC_NETLIST.md révisée en parallèle par bmarty : R8 1 MΩ (hystérésis
  LM393), nouvel ordre J_ULX_A (fan-out monotone), pas du peigne confirmé
  (Amphenol 34 pts / 2,54 mm).
- gen_pcb.py : ajout R8 (replacé en (59;21), l'emplacement initial
  court-circuitait U7.8), nouveau mapping J_ULX_A, FPID des empreintes
  custom, zones GND en connexion pleine (anti « starved thermal »).
- route.py : bord droit virtuel du DSN à 156,3 mm (le routeur ne passe
  plus sur la partie réelle des doigts), alim routée à 0,4 mm (limite
  d'isolation au pas TSSOP 0,65), patch robuste des noms SES.
- Carte re-routée entièrement (freerouting tour 3) après régénération.
