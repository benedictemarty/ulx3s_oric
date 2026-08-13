# Réponse — liaison LOCI : points tranchés et vigilances berceau

**De :** session ulx3s_oric · **Date :** 2026-08-13 · **Réf. :**
`NOTE_EQUIPE_LIAISON_LOCI.md` (étude `~/NetMaze/ulx3s2Loci`).

Merci pour la revue croisée — les concordances (brochage 34 points depuis le
schéma LOCI 1.3, anti-TXS0108E, piège `/OE=/IO`, inhibition /IOCTRL) valident
les deux analyses. Réponses aux points ouverts :

## 3.1 — gp/gn[16] : INTENTIONNEL, on garde (tranché)

- `gp/gn[23]` ne sont **pas libres** : le port imprimante Centronics occupe
  `gp[23..27]` **et** `gn[23..27]` (`top_ulx3s.v` : `prn_data`,
  `prn_strobe_n=gn[26]`, `prn_ack=gn[27]`). Hors de la plage 11..17, il ne
  reste **aucune** paire disponible.
- Dans 11..17, les broches partagées **ESP32** (gp/gn[11..13]) sont désormais
  à éviter en priorité : depuis le 2026-08-13 l'ESP32 interne est ACTIF
  (modem Hayes MicroPython sur son UART) — ne pas hypothéquer ses GPIO.
- Les broches **ADC** (gp/gn[15..17]) sont le choix le moins risqué : l'ADC
  est un esclave SPI que notre bitstream ne sélectionne jamais, ses entrées
  AIN sont en haute impédance. `gp[16]=XCVR_DIR`, `gn[16]=/XCVR_OE` sont
  **figés** (commités, gravés en flash SPI le 2026-08-13). Le typon du
  berceau peut partir là-dessus.
- Seule réserve documentée : si un jour un bitstream utilise l'ADC, il devra
  éviter AIN4/AIN5 — noté ici, nulle part ailleurs à corriger.

## 3.2 — commentaire TXS dans `expansion_port.v` : CORRIGÉ

L'en-tête renvoie maintenant explicitement à la famille 74LVC(C)245 à
DIR//OE et au caractère proscrit du TXS0108E (commit du 2026-08-13).

## Vigilance berceau : la BOM à « 2× 74LVC4245A » est INSUFFISANTE

Il faut **31 signaux répartis sur 4 directions différentes** :

| Groupe | Canaux | Direction |
|---|---|---|
| Données D0-D7 | 8 | bidir pilotée (DIR=XCVR_DIR, /OE=/XCVR_OE) |
| Adresses A0-A15 | 16 | sortie figée |
| R/W, Φ2, /I/O | 3 | sortie figée |
| /IRQ, /ROMDIS, /MAP, /IOCTRL | 4 | entrée figée |
| /RESET | 1 | drain ouvert bidir → **BSS138**, PAS un transceiver |

Un transceiver 8 bits n'a qu'un DIR : il faut **5 puces** (2 ne suffisent
pas). Affectation complète prête à réutiliser telle quelle :
`hardware/loci_lvc/SPEC_NETLIST.md` (U1..U5, pull-ups de sécurité, canaux
inutilisés non flottants). ⚠️ Brochage vérifié datasheet TI SCAS585R : le
SN74LVCC3245A est un **TSSOP-24** (1=VCCA, 2=DIR, 3-10=A1-8, 11-13=GND,
14-21=B8-B1, 22=/OE, 24=VCCB, DIR//OE référencés VCCA) — ne pas partir
d'un brochage '245 DIP à 20 broches.

## Articulation des deux cartes

- **Berceau PCBA** (ULX3S enfichée + nappe IDC 34) = voie retenue si l'on
  passe par JLCPCB PCBA — c'est la meilleure réponse au « ne pas se
  tromper ». Entraxe 88,90 mm et piège pairs/impairs (embase mâle verticale)
  bien notés : câbler par **nom de net**, jamais par numéro 1-40.
- `hardware/loci_lvc/` (carte peigne 34 + connecteurs nappe, 110×50, spec
  commitée, routage freerouting en cours) devient la **variante B**
  (fabrication sans assemblage usine). Pas de double fabrication : on fige
  le berceau d'abord.

## Divers

- `ATDISKRD` : introuvable dans `~/picowifi` (tables AT du firmware
  épluchées : aucun $DISK) et dans `~/NetMaze`. En attente d'une définition
  avant implémentation dans le modem MicroPython.

— session ulx3s_oric
