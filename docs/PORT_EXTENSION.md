# Port d'extension Oric sur GPIO ULX3S

Reconstitution du connecteur d'extension 34 points de l'Oric Atmos (annexe 11
du manuel officiel) sur les en-têtes GPIO de l'ULX3S, pour brancher une vraie
cartouche — cible : **LOCI**.

## Brochage officiel du connecteur Oric (34 points, mâle vu de l'arrière)

| Broche | Signal  | Sens (vu de l'Oric) | | Broche | Signal   | Sens |
|-------:|---------|---------------------|-|-------:|----------|------|
| 1  | /MAP    | entrée  | | 2  | /ROMDIS | entrée  |
| 3  | Φ2      | sortie  | | 4  | /RESET  | bidir   |
| 5  | /I/O    | sortie  | | 6  | /IOCTRL | entrée  |
| 7  | R/W     | sortie  | | 8  | /IRQ    | entrée  |
| 9  | D2      | bidir   | | 10 | D0      | bidir   |
| 11 | A3      | sortie  | | 12 | D1      | bidir   |
| 13 | A0      | sortie  | | 14 | D6      | bidir   |
| 15 | A1      | sortie  | | 16 | D3      | bidir   |
| 17 | A2      | sortie  | | 18 | D4      | bidir   |
| 19 | D5      | bidir   | | 20 | A4      | sortie  |
| 21 | A5      | sortie  | | 22 | D7      | bidir   |
| 23 | A6      | sortie  | | 24 | A15     | sortie  |
| 25 | A7      | sortie  | | 26 | A14     | sortie  |
| 27 | A8      | sortie  | | 28 | A13     | sortie  |
| 29 | A9      | sortie  | | 30 | A12     | sortie  |
| 31 | A10     | sortie  | | 32 | A11     | sortie  |
| 33 | +5V     | alim    | | 34 | GND     | alim    |

Sémantique mémoire $C000-$FFFF (wiki Defence Force) :
- /ROMDIS et /MAP inactifs → ROM BASIC interne ;
- /ROMDIS actif seul → RAM cachée (overlay) ;
- /ROMDIS **et** /MAP actifs → le périphérique externe fournit les données.
- /IOCTRL actif → le décodage interne de la VIA ($0300-$030F) est inhibé.

## Adaptation de niveau 3,3 V ↔ 5 V : 74LVC245, PAS de TXS0108E

**Le TXS0108E est à proscrire sur ce bus** (révision 2026-08-13). C'est un
translateur auto-sens (pass-gates + one-shot + pull-ups ~40 kΩ) conçu pour
des lignes open-drain lentes (I²C) : pas de contrôle de direction (risque
de contention avec le 74LVC4245A push-pull de la LOCI → glitches), one-shot
sensible à la capacité des fils volants (oscillations, faux niveaux),
drive faible. OK pour I²C/SPI lents, inadapté à un bus parallèle push-pull.

**Plan retenu : famille 74LVC à DIR//OE.** L'impératif est la FAMILLE :
du **74LVC** (entrées 5 V-tolérantes quand alimenté en 3,3 V — c'est ce qui
protège l'ECP5).
- ✅ `74LVC245` alimenté en **3,3 V** (DIP-20, breadboard) — le plan.
- ✅ `74LVCC3245A`/`74LVC4245A` (dual-supply 5 V/3,3 V) — encore plus
  propre, mais SMD (moins commode en fils volants).
- ❌ `74HC`/`74VHC`/`74AHC` 245 : NON 5 V-tolérants en 3,3 V → destruction
  possible du FPGA.
- ⚠️ `74AHCT245` (alim 5 V, entrées TTL) : uniquement pour le sens montant
  3,3 V→5 V (adresses/contrôles) ; jamais pour lire la LOCI (il sortirait
  du 5 V vers le FPGA).

Affectation (3× DIP-20 + 1 pour les entrées) :
- **Données D0-D7** : 1× 74LVC245 (3,3 V), `DIR = R/W`. **Attention /OE :**
  `/OE = /IO` ne suffit PAS — la LOCI sert sa ROM menu via /ROMDIS+/MAP en
  `$C000-$FFFF`, ces lectures MÉMOIRE passent aussi par D0-D7. Deux
  options : `/OE` à la masse (toujours validé, sûr : le FPGA ne pilote D
  qu'en écriture Φ2 haut, la LOCI ne pilote que sélectionnée en lecture),
  ou — plan retenu — les broches FPGA dédiées **XCVR_DIR (gp[16])** et
  **/XCVR_OE (gn[16])** : DIR = écriture CPU (polarité 74LVCC3245A,
  haut = A→B), /OE passant pendant Φ2 haut seulement. Aucune logique
  externe, tous les cycles visibles de la cartouche (fidèle au vrai bus).
- **Adresses A0-A15 + Φ2, R/W, /I/O** : 2-3× 74LVC245 en sortie fixe
  (DIR figé, /OE à la masse) ou 74AHCT245.
- **Entrées /IRQ, /ROMDIS, /MAP, /IOCTRL** : 1× 74LVC245 (3,3 V) DIR figé
  vers le FPGA.
- **/RESET (bidir drain ouvert)** : PAS par un transceiver — 1 MOSFET-N
  (BSS138) + pull-ups des deux côtés, comme un niveau I²C classique.

## Correspondance GPIO ULX3S → signal Oric (câblage Dupont)

`gp[n]`/`gn[n]` : en-têtes J1/J2 de l'ULX3S.

Les GPIO gp/gn[11..17] sont volontairement évitées (partagées avec l'ESP32
et l'ADC de l'ULX3S).

| GPIO ULX3S | Signal Oric | Broche connecteur | Sens FPGA |
|------------|-------------|-------------------|-----------|
| gp[0]…gp[10]  | A0…A10  | 13,15,17,11,20,21,23,25,27,29,31 | sortie |
| gp[18]…gp[22] | A11…A15 | 32,30,28,26,24 | sortie |
| gn[0]…gn[7]   | D0…D7   | 10,12,9,16,18,19,14,22 | bidir |
| gn[8]  | R/W     | 7  | sortie |
| gn[9]  | Φ2      | 3  | sortie |
| gn[10] | /I/O    | 5  | sortie |
| gn[18] | /RESET  | 4  | bidir (drain ouvert, pull-up) |
| gn[19] | /IRQ    | 8  | entrée (pull-up) |
| gn[20] | /ROMDIS | 2  | entrée (pull-up) |
| gn[21] | /MAP    | 1  | entrée (pull-up) |
| gn[22] | /IOCTRL | 6  | entrée (pull-up) |
| gp[16] | XCVR_DIR | — (transceiver données) | sortie : 1 = FPGA→cartouche |
| gn[16] | /XCVR_OE | — (transceiver données) | sortie : passant si Φ2 haut |
| —      | +5V     | 33 | depuis l'alim 5 V externe (PAS du FPGA !) |
| GND    | GND     | 34 | masse commune ULX3S + alim 5 V + cartouche |

⚠️ **Ne jamais relier le +5 V de la cartouche à une broche du FPGA.** Masse
commune obligatoire entre ULX3S, buffers LVC et alimentation 5 V.

## Chronologie du bus (1 cycle CPU = 1 µs = 25 phases de clk_sys)

```
phase   0        12                24
        |--------|-----------------|
A/RW/IO ████████████████████████████  stables tout le cycle
Φ2      ________██████████████████    haut phases 12-24
D (écr.)________██████████████████    pilotées pendant Φ2 haut
D (lec.)              ↑ échantillon phase 22
```

Marges énormes à 1 MHz : compatible câblage Dupont + 74LVC245.
La LOCI ajuste elle-même sa fenêtre d'échantillonnage (ADJ_SCAN du menu).

Câblage Dupont anti-diaphonie : fils courts (< 20 cm), et intercaler des
fils de MASSE entre les groupes (un GND tous les 4-6 signaux, en
particulier entre bus d'adresses, bus de données et Φ2).

## Mise en route avec la LOCI

1. Vérifier la masse commune et le 5 V externe AVANT d'insérer la cartouche.
2. Démarrer l'ULX3S : boot BASIC normal (LOCI inactive tant que son bouton
   n'est pas pressé / selon firmware).
3. La LOCI s'annonce en pilotant /ROMDIS + /MAP pour servir sa ROM menu.
4. En cas d'instabilité : lancer l'auto-réglage de timing du menu LOCI
   (ADJ_SCAN) qui balaye les fenêtres d'échantillonnage.
