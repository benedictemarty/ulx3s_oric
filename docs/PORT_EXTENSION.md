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

## Correspondance GPIO ULX3S → signal Oric (câblage Dupont)

Tous les signaux passent par les modules TXS0108E (3,3 V côté FPGA,
5 V côté cartouche). `gp[n]`/`gn[n]` : en-têtes J1/J2 de l'ULX3S.

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
| —      | +5V     | 33 | depuis l'alim 5 V externe (PAS du FPGA !) |
| GND    | GND     | 34 | masse commune ULX3S + alim 5 V + cartouche |

⚠️ **Ne jamais relier le +5 V de la cartouche à une broche du FPGA.** Masse
commune obligatoire entre ULX3S, modules TXS et alimentation 5 V.

## Chronologie du bus (1 cycle CPU = 1 µs = 25 phases de clk_sys)

```
phase   0        12                24
        |--------|-----------------|
A/RW/IO ████████████████████████████  stables tout le cycle
Φ2      ________██████████████████    haut phases 12-24
D (écr.)________██████████████████    pilotées pendant Φ2 haut
D (lec.)              ↑ échantillon phase 22
```

Marges énormes à 1 MHz : compatible câblage Dupont + TXS0108E.
La LOCI ajuste elle-même sa fenêtre d'échantillonnage (ADJ_SCAN du menu).

## Mise en route avec la LOCI

1. Vérifier la masse commune et le 5 V externe AVANT d'insérer la cartouche.
2. Démarrer l'ULX3S : boot BASIC normal (LOCI inactive tant que son bouton
   n'est pas pressé / selon firmware).
3. La LOCI s'annonce en pilotant /ROMDIS + /MAP pour servir sa ROM menu.
4. En cas d'instabilité : lancer l'auto-réglage de timing du menu LOCI
   (ADJ_SCAN) qui balaye les fenêtres d'échantillonnage.
