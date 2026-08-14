# Berceau « LOCI-Bridge » — état du projet

Carte berceau : l'ULX3S s'enfiche (JB1/JB2 aux positions exactes relevées sur
`emard/ulx3s ulx3s.kicad_pcb` — nets affectés PAR POSITION, le piège
pairs/impairs est éliminé par construction), la LOCI arrive par nappe IDC 34
(J_LOCI, numérotation Atmos = table JEXP). Schéma électrique =
`../loci_lvc/SPEC_NETLIST.md` (5× SN74LVCC3245A TSSOP-24 + BSS138, brochage
vérifié TI SCAS585R).

## État (2026-08-14)

- `gen_pcb.py` : génération complète reproductible (150×58, plans F.Cu=GND,
  B.Cu=+3V3|+5V split x=116, vias d'alim posés par `post_power.py`).
- `route.py` : freerouting — **tous les signaux routés** (~40 nets).
- `post_power.py` : raccords alim/masse post-routage (vias collision-vérifiés,
  raccords en L, idempotent).

**RESTE À FAIRE avant fabrication** (~30 min de KiCad interactif) :
1. ~15 liaisons d'alimentation : mes contrôles géométriques ignorent les
   îlots de plan isolés — certains vias +3V3/+5V tombent dans des poches de
   zone déconnectées. Ouvrir `berceau.kicad_pcb`, afficher le chevelu,
   tirer les liaisons d'alim restantes à la souris (large, 0,4 mm), DRC.
2. 3 courts-circuits résiduels + sérigraphie (silk_over_copper etc.) à
   corriger au même moment.
3. REVUE MÉCANIQUE avant commande : sens d'enfichage ULX3S (embases mâles
   verticales sous la carte vs femelles coudées d'origine), hauteur des
   composants sous l'ULX3S, position du détrompeur IDC.

Pipeline : `python3 gen_pcb.py && python3 route.py && python3 post_power.py`
puis `kicad-cli pcb drc berceau.kicad_pcb`.
