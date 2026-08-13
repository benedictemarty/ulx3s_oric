# Carte adaptateur LOCI (rév. LVC) — spécification électrique

Petite carte 2 couches (~110×50 mm) entre les nappes GPIO de l'ULX3S et le
connecteur carte-bord 34 points de la **LOCI**. Révision 2026-08-13 : les
TXS0108E du bandeau phaseA sont **proscrits** (auto-sens inadapté à un bus
parallèle push-pull, cf. `docs/PORT_EXTENSION.md`) → **5× SN74LVCC3245APW**
(dual-supply 3,3 V/5 V, DIR + /OE maîtrisés).

Hérite de phaseA : géométrie du peigne J_EXP (34 doigts, 2×17, pas 2,54 mm,
doigts 1,6×6 mm sans masque, F.Cu+B.Cu, biseau 45°, ENIG), numérotation
officielle Atmos (position k : avant = 2k, arrière = 2k−1).

## Différences avec phaseA

- Périmètre réduit : NI imprimante, NI cassette/DIN, NI LM393/PhotoMOS —
  uniquement le bus d'extension vers la LOCI.
- 5× 74LVCC3245A à direction figée ou pilotée, plus de TXS.
- /RESET par BSS138 (drain ouvert bidirectionnel), plus par transceiver.
- Deux nets de pilotage venant du FPGA : `XCVR_DIR` (gp[16]) et
  `/XCVR_OE` (gn[16]) — déjà câblés dans le bitstream (commit RTL
  2026-08-13).

## Affectation des transceivers

DIR haut = A→B (A = côté 3,3 V FPGA, B = côté 5 V LOCI).

| Chip | Canaux | DIR | /OE |
|---|---|---|---|
| U1 | A1..A8 = A0..A7 → A5V0..A5V7 | figé HAUT (A→B) | GND |
| U2 | A1..A8 = A8..A15 → A5V8..A5V15 | figé HAUT (A→B) | GND |
| U3 | A1..A8 = D0..D7 ↔ D5V0..D5V7 | **XCVR_DIR** (pull-down 10 k) | **/XCVR_OE** (pull-up 10 k → isolé par défaut) |
| U4 | A1..A3 = RW, PHI2, IO_n → RW5, PHI2_5, IO5_n (A4..A8 NC, entrées A à GND) | figé HAUT (A→B) | GND |
| U5 | B1..B4 = IRQ5_n, ROMDIS5_n, MAP5_n, IOCTL5_n → IRQ_n, ROMDIS_n, MAP_n, IOCTL_n (B5..B8 NC, entrées B à GND côté 5 V via 10 k) | figé BAS (B→A) | GND |

Sécurité par défaut (FPGA absent/non configuré) : U3 isolé (/OE tiré haut)
et en écoute (DIR tiré bas) ; les entrées de canaux inutilisés ne flottent
jamais (liées à la masse du côté émetteur).

⚠️ **Brochage SN74LVCC3245APW À VÉRIFIER sur le datasheet TI (SCDS010)
avant génération** — ne pas recopier le brochage du TXS ni supposer celui
du '245 DIP. Points à confirmer : positions VCCA/VCCB/DIR//OE, sens A/B,
et la contrainte VCCA ≤ VCCB.

## /RESET (bidirectionnel drain ouvert)

BSS138 : gate = +3V3 ; source = RST_n (côté FPGA) + R 10 k → 3V3 ;
drain = RST5_n (côté LOCI, doigt 4) + R 10 k → +5V. Schéma classique
« niveau I²C » : chaque côté peut tirer bas, aucun ne pousse du 5 V vers
le FPGA.

## J_ULX (2×20) — vers l'ULX3S (nappe/Dupont, 3,3 V)

Ordre fan-out monotone (hérité phaseA, + les 2 nets XCVR) :
1=RW, 2=PHI2, 3=IO_n, 4=RST_n, 5=IRQ_n, 6=ROMDIS_n, 7=MAP_n, 8=IOCTL_n,
9=XCVR_DIR, 10=XCVR_OE_n ; 11..18 = D0..D7 ; 19..26 = A0..A7 ;
27..34 = A8..A15 ; 35,36=GND ; 37,38=+3V3 (depuis l'ULX3S) ; 39,40=GND.

Correspondance côté ULX3S = table de `docs/PORT_EXTENSION.md`
(gp/gn J1-J2, dont XCVR_DIR=gp[16], /XCVR_OE=gn[16]).

## Alimentations

- +3V3 : depuis l'ULX3S (J_ULX 37,38) — alimente VCCA des 5 chips + pull-ups côté A.
- +5V : **jack 5,5/2,1 externe** (J_PWR) — alimente VCCB des 5 chips,
  pull-up RST5_n, et le doigt 33 (+5V LOCI). JAMAIS relié au 3V3/FPGA.
- Masse commune : J_ULX (35,36,39,40) + jack + doigt 34.
- Découplage : 100 nF ×2 par chip (un par VCC), 10 µF vrac sur +5V et +3V3.

## BOM (draft)

| Réf | Composant | Empreinte |
|---|---|---|
| U1..U5 | SN74LVCC3245APW | TSSOP-20_4.4x6.5mm_P0.65mm |
| Q1 | BSS138 | SOT-23 |
| J_EXP | Peigne 34 doigts (script phaseA) | custom |
| J_ULX | Header mâle 2×20 | PinHeader_2x20_P2.54mm_Vertical |
| J_PWR | Jack alim 5,5/2,1 | BarrelJack_Horizontal |
| R1,R2 | 10 k (pull-ups /RESET 3V3 et 5V) | R_0603 |
| R3 | 10 k (pull-up /XCVR_OE → 3V3) | R_0603 |
| R4 | 10 k (pull-down XCVR_DIR) | R_0603 |
| R5..R8 | 10 k (entrées B inutilisées U5 → GND) | R_0603 |
| C1..C10 | 100 nF | C_0603 |
| C11,C12 | 10 µF | C_0805 |
