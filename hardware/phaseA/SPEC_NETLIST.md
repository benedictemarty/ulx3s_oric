# Phase A — Bandeau LOCI : spécification électrique complète

Carte 2 couches ~160×50 mm. Peigne doré 34 contacts (2×17, pas 2,54 mm,
doigts des deux faces) au bord DROIT. Assemblage JLCPCB (SMD top).
Épaisseur 1,6 mm, finition ENIG + biseau 45° sur le peigne.

## Composants

| Réf | Composant | Empreinte KiCad |
|-----|-----------|-----------------|
| J_EXP | Peigne 34 doigts (custom, voir géométrie) | générée par script |
| U1..U6 | TXS0108E (TSSOP-20) | Package_SO:TSSOP-20_4.4x6.5mm_P0.65mm |
| U7 | LM393 (SOIC-8) | Package_SO:SOIC-8_3.9x4.9mm_P1.27mm |
| K1 | PhotoMOS AQY212GH (DIP-4 CMS) | Package_DIP:DIP-4_W7.62mm (ou SOP-4) |
| J_ULX_A | Header mâle 2×20 | Connector_PinHeader_2.54mm:PinHeader_2x20_P2.54mm_Vertical |
| J_ULX_B | Header mâle 2×10 | Connector_PinHeader_2.54mm:PinHeader_2x10_P2.54mm_Vertical |
| J_PRN | Header mâle 2×10 (Centronics Atmos) | idem 2x10 |
| J_CAS | DIN-7 femelle 270° THT | Connector_DIN:DIN41524_7pin_... (ou pads THT custom) |
| J_PWR | Jack alim 5,5/2,1 | Connector_BarrelJack:BarrelJack_Horizontal |
| J_SND | Header 1×2 (audio vers DIN4) | PinHeader_1x02 |
| R_OE | 10 kΩ 0603 (pull-down OE) | R_0603 |
| R1 | 10 kΩ 0603 (div. TAPE OUT série) | R_0603 |
| R2 | 1 kΩ 0603 (div. TAPE OUT masse) | R_0603 |
| R3,R4 | 100 kΩ 0603 (polarisation IN+ LM393) | R_0603 |
| R5 | 100 kΩ 0603 (seuil auto IN-) | R_0603 |
| R6 | 10 kΩ 0603 (pull-up sortie LM393) | R_0603 |
| R7 | 470 Ω 0603 (LED PhotoMOS) | R_0603 |
| C1 | 1 µF 0603 (couplage TAPE IN) | C_0603 |
| C2 | 100 nF 0603 (moyenne IN-) | C_0603 |
| C3..C14 | 100 nF 0603 (découplage : 2/TXS) | C_0603 |
| C15,C16 | 10 µF 0805 (vrac 5V, 3V3) | C_0805 |

## TXS0108E — brochage VÉRIFIÉ (TI SCES642H)

1=A1, 2=VCCA(3V3), 3=A2, 4=A3, 5=A4, 6=A5, 7=A6, 8=A7, 9=A8, 10=OE,
11=GND, 12=B8, 13=B7, 14=B6, 15=B5, 16=B4, 17=B3, 18=B2, **19=VCCB(5V)**,
**20=B1**. Tous les OE sur le net OE_EN (R_OE 10 k vers GND ; piloté haut
par le FPGA via J_ULX_A.33 après verrouillage des PLL).

## J_EXP — peigne (numérotation officielle Atmos, annexe 11)

Face AVANT (F.Cu) = broches paires, face ARRIÈRE (B.Cu) = impaires,
même position le long du bord. Position k (1..17) : avant = 2k, arrière = 2k-1.

| Doigt | Net 5V | | Doigt | Net 5V |
|---|---|---|---|---|
| 1 | MAP5_n | 2 | ROMDIS5_n |
| 3 | PHI2_5 | 4 | RST5_n |
| 5 | IO5_n | 6 | IOCTL5_n |
| 7 | RW5 | 8 | IRQ5_n |
| 9 | D5V2 | 10 | D5V0 |
| 11 | A5V3 | 12 | D5V1 |
| 13 | A5V0 | 14 | D5V6 |
| 15 | A5V1 | 16 | D5V3 |
| 17 | A5V2 | 18 | D5V4 |
| 19 | D5V5 | 20 | A5V4 |
| 21 | A5V5 | 22 | D5V7 |
| 23 | A5V6 | 24 | A5V15 |
| 25 | A5V7 | 26 | A5V14 |
| 27 | A5V8 | 28 | A5V13 |
| 29 | A5V9 | 30 | A5V12 |
| 31 | A5V10 | 32 | A5V11 |
| 33 | +5V | 34 | GND |

Géométrie doigts : largeur 1,6 mm, longueur 6 mm depuis le bord, pas
2,54 mm, sans masque (mask ouvert), F.Cu ET B.Cu.
⚠️ Pas à CONFIRMER par mesure sur la LOCI réelle avant envoi en fab.

## Affectation TXS

| Chip | Côté A (3V3) ← J_ULX_A | Côté B (5V) → destination |
|---|---|---|
| U1 A1..A8 | A0..A7 | A5V0..A5V7 → J_EXP |
| U2 A1..A8 | A8..A15 | A5V8..A5V15 → J_EXP |
| U3 A1..A8 | D0..D7 | D5V0..D5V7 → J_EXP |
| U4 A1..A8 | RW, PHI2, IO_n, RST_n, IRQ_n, ROMDIS_n, MAP_n, IOCTL_n | RW5, PHI2_5, IO5_n, RST5_n, IRQ5_n, ROMDIS5_n, MAP5_n, IOCTL5_n → J_EXP |
| U5 A1..A8 | PA0..PA7 | PRN_D0..PRN_D7 → J_PRN |
| U6 A1,A2 | STROBE_n, ACK | PRN_STB_n, PRN_ACK → J_PRN (A3..A8/B3..B8 : NC) |

## J_ULX_A (2×20) — vers GPIO ULX3S (Dupont)

1..16 = A0..A15 ; 17..24 = D0..D7 ; 25=RW, 26=PHI2, 27=IO_n, 28=RST_n,
29=IRQ_n, 30=ROMDIS_n, 31=MAP_n, 32=IOCTL_n ; 33=OE_EN ; 34..36=GND ;
37,38=+3V3 (depuis ULX3S) ; 39,40=GND.

## J_ULX_B (2×10)

1..8 = PA0..PA7 ; 9=STROBE_n ; 10=ACK ; 11=TAPE_OUT_3V3 ; 12=MOTOR_3V3 ;
13=TAPE_IN_3V3 ; 14,15,16=GND ; 17,18=+3V3 ; 19,20=GND.

## J_PRN (2×10, brochage imprimante Atmos officiel)

Impairs : 1=PRN_STB_n, 3=PRN_D0, 5=PRN_D1, 7=PRN_D2, 9=PRN_D3, 11=PRN_D4,
13=PRN_D5, 15=PRN_D6, 17=PRN_D7, 19=PRN_ACK. Pairs 2..20 : GND.

## J_CAS (DIN-7, brochage Atmos)

1=TAPE_OUT_DIN (depuis diviseur R1/R2), 2=GND, 3=TAPE_IN_DIN (vers C1),
4=SOUND (depuis J_SND.1), 5=NC, 6=MOTOR_A, 7=MOTOR_B (contacts K1).

## Circuits analogiques

- TAPE OUT : TAPE_OUT_3V3 —R1(10k)— TAPE_OUT_DIN —R2(1k)— GND.
- TAPE IN : TAPE_IN_DIN —C1(1µF)— nœud IN+ ; R3(100k) IN+→3V3 ;
  R4(100k) IN+→GND ; R5(100k) IN+→IN- ; C2(100n) IN-→GND ;
  LM393 : IN+=broche 3, IN-=broche 2, OUT=broche 1 ; R6(10k) OUT→3V3 ;
  OUT = net TAPE_IN_3V3. VCC LM393(8)=3V3, GND(4)=GND. 2e comparateur :
  entrées (5,6) à GND, sortie (7) NC.
- MOTEUR : MOTOR_3V3 —R7(470)— K1 LED+(1) ; K1 LED-(2)=GND ;
  K1 contacts (3,4) = MOTOR_A/MOTOR_B (contact sec).

## Alimentations

+5V : J_PWR centre → VCCB U1..U6 (19), J_EXP.33. GND : commun.
+3V3 : J_ULX_A.37/38 → VCCA U1..U6 (2), R3, R6, LM393.8.
Découplage 100 nF au plus près de chaque broche VCCA et VCCB.

## Placement (indicatif)

- Bord droit : J_EXP (doigts, centrés).
- Bord haut (« face arrière ») de gauche à droite : J_PWR, J_CAS, J_PRN.
- Bande centrale : U1..U6 alignés, côté B vers la droite/haut.
- Bord bas : J_ULX_A puis J_ULX_B (accès Dupont), U7/K1 près de J_CAS.

## Critères d'acceptation des fichiers de fabrication

1. `kicad-cli pcb drc` : 0 erreur (avertissements sérigraphie tolérés).
2. 0 net non routé (ratsnest vide).
3. Gerbers + perçage Excellon exportés (`kicad-cli pcb export gerbers/drill`).
4. BOM.csv (réf LCSC quand dispo : TXS0108EPWR=C17197?, à vérifier) et
   CPL.csv (positions top) au format JLCPCB.
5. README de commande : 2 couches, 1,6 mm, ENIG, gold fingers + bevel.
