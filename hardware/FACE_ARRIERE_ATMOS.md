# Carte « Face arrière Atmos » pour ULX3S

Reproduction de la face arrière d'un Oric Atmos pilotée par le core FPGA,
étendue en mini fond de panier : berceaux pour 2 Pico W et un Tang Primer
20K, 2 USB-A latéraux.

```
                    face arrière (connecteurs d'époque)
┌──────────────────────────────────────────────────────────────────────┐
│  [HDMI]   [DIN-7]     [===== 2x10 =====]    [██ peigne 34 ██]   [5V] │
│  vidéo    cassette     port imprimante        extension (LOCI)  jack │
│                                                                      │
│U │   ┌─────────────┐  ┌─────────────┐  ┌──────────────────────┐     │
│S │   │ berceau      │  │ berceau     │  │ berceau              │     │
│B │   │ Pico W  #1   │  │ Pico W #2   │  │ Tang Primer 20K      │     │
│1 │   │ (LOCI fw /   │  │ (modem WiFi │  │ (dock, 2 headers     │     │
│  │   │  stockage)   │  │  picowifi)  │  │  2x20)               │     │
│U │   └─────────────┘  └─────────────┘  └──────────────────────┘     │
│S │                                                                   │
│B │      TXS0108E x5, LM393, picots Dupont -> GPIO ULX3S              │
│2 │                                                                   │
└──────────────────────────────────────────────────────────────────────┘
   côté : USB1, USB2 (USB-A femelles)
```

## Connecteurs (de gauche à droite, comme l'Atmos)

| Emplacement Atmos | Ici | Référence |
|---|---|---|
| Prise TV (RF) | — supprimée | |
| DIN RGB | **HDMI femelle** coudée, déport mécanique du GPDI ULX3S par câble HDMI court mâle-mâle (aucune électronique) | prise HDMI-A traversante |
| DIN-7 cassette | **DIN-7 femelle** identique à l'origine (brochage Atmos : TAPE OUT, GND, TAPE IN, SOUND, RELAYS) | DIN 7 broches 270° |
| Port imprimante 20 pts | **Header mâle 2×10** au pas 2,54 comme l'origine (câbles imprimante d'époque compatibles) | |
| Port d'extension 34 pts | **Peigne doré 2×17** au bord de la carte — la LOCI s'y clipse comme sur un vrai Atmos | doigts or, PCB 1,6 mm |
| Jack alim 9 V | **Jack 5,5/2,1 mm, 5 V** : alimente le côté 5 V (cartouche, imprimante, cassette, TXS) | |

## Électronique embarquée (assemblage JLCPCB, zéro soudure)

- 5× **TXS0108E** (TSSOP-20) : 16 adresses + 8 données + 8 contrôles
  extension + 8 données imprimante + strobe/ack/cassette.
- 1× **LM393** + réseau RC : mise en forme du signal TAPE IN
  (magnétophone → niveau logique).
- Condensateurs de découplage, résistances de pull-up 5 V (bus au repos).
- 2 rangées de picots 2,54 vers les GPIO ULX3S (câblage Dupont documenté
  dans docs/PORT_EXTENSION.md, complété ci-dessous).

## Affectation GPIO complémentaire (imprimante + cassette)

| GPIO | Signal | Sens FPGA |
|------|--------|-----------|
| gp[23..27], gn[23..25] | Données imprimante PA0..PA7 | sortie |
| gn[26] | /STROBE imprimante (PB4) | sortie |
| gn[27] | /ACK imprimante (CA1) | entrée (pull-up) |
| gp[14] | TAPE OUT (PB7) | sortie |
| gp[15] | MOTEUR cassette (PB6, vers relais/transistor) | sortie |
| gp[16] | TAPE IN (vers CB1, après LM393) | entrée |

## Berceaux (côté 3,3 V — le même bus que le lien ULX3S)

- **2× berceau Pico W** (2 rangées de supports femelles 1×20, pas 2,54) :
  - Pico #1 : candidat naturel pour porter le **firmware LOCI natif**
    (github.com/sodiumlb/loci-firmware, RP2040) ou tout périphérique de bus
    maison — il voit le bus 6502 en 3,3 V, comme le RP2040 de la vraie LOCI ;
  - Pico #2 : **modem WiFi** (PicoWiFiModemUSB, ACIA à $0380 — déjà supporté
    par l'émulateur de référence) ;
  - straps de sélection pour choisir quelles lignes de bus chaque Pico voit
    (éviter les conflits de pilotage — deux périphériques ne répondent
    jamais à la même adresse).
- **1× berceau Tang Nano 20K** (choix acté 2026-07-29, remplace le couple
  Primer 20K + dock) : format DIP à picots 2,54 → deux rangées de supports
  femelles. GW2AR-18 avec 8 Mo de SDRAM intégrée, HDMI et lecteur SD à
  bord ; FPGA d'expérimentation sur le bus (co-processeur, cartouche
  synthétique…). Même règle : il voit le bus 3,3 V.

⚠️ Règle de cohabitation : la ULX3S pilote toujours A/RW/Φ2 ; les berceaux
sont des **périphériques** (ils ne pilotent D que sur lecture de leur
plage, /IRQ//ROMDIS//MAP en drain ouvert).

## Stockage et mémoire

- **Slot micro-SD** câblé en SPI sur le berceau Pico #1 — architecture de la
  vraie LOCI (firmware RP2040 + stockage SD). S'ajoutent le micro-SD de
  l'ULX3S (utilisable par le core, chargement .tap au backlog) et celui du
  Tang Nano 20K.
- **RAM : aucun boîtier sur la carte porteuse.** La RAM de l'Oric (64 Ko)
  est en BRAM dans le FPGA ; l'ULX3S apporte 32 Mo de SDRAM et le Tang
  Nano 20K 8 Mo intégrés — chaque module a sa mémoire, le bus 6502
  n'adresse que 64 Ko.

## USB latéraux

- **USB1** (USB-A femelle) : câblée au Pico #1 en hôte PIO-USB
  (D+/D- sur deux GPIO + 5 V du jack) — clé USB de stockage pour le
  firmware LOCI, comme sur la vraie cartouche.
- **USB2** (USB-A femelle) : déport mécanique du port US2 de l'ULX3S
  (clavier USB du core) : 4 picots D+/D-/5V/GND à relier en Dupont
  vers us2 — plus pratique que le micro-USB de la carte.

## Alimentation

- Le jack 5 V alimente exclusivement le domaine 5 V de la carte
  (VCCB des TXS, cartouche broche 33, imprimante, LM393).
- L'ULX3S garde sa propre alimentation USB. **Masses communes obligatoires.**
- Prévoir 5 V / 1 A (la LOCI consomme < 300 mA).

## Format : carte mère Atmos complète

Objectif final : la carte reprend **les dimensions de la carte mère de
l'Oric Atmos d'origine** (~280 × 178 mm, à confirmer par mesure sur un
exemplaire réel) pour se monter dans un vrai boîtier Atmos :
- connecteurs arrière positionnés exactement comme l'origine (découpes du
  boîtier) : le peigne d'extension au bord arrière droit, DIN cassette,
  port imprimante, HDMI à l'emplacement du DIN RGB, jack alim ;
- trous de fixation aux emplacements des plots du boîtier Atmos ;
- l'ULX3S se visse sur la carte (entretoises) et s'y raccorde par nappes ;
- **haut-parleur** : emplacement pour HP Ø 40-50 mm (comme l'origine) +
  ampli classe D PAM8302, alimenté par la sortie jack audio de l'ULX3S
  (câble TRS court ou 2 fils Dupont depuis les picots audio) — aucun GPIO
  supplémentaire nécessaire ;
- à terme, le clavier mécanique du boîtier peut être scanné par un des
  berceaux (matrice 8×8 → bus) : prévoir le connecteur nappe clavier Atmos.

⚠️ Mesures à faire sur boîtier/carte réels avant le routage final :
dimensions exactes, positions des découpes arrière, entraxes de fixation,
position du connecteur nappe clavier.

## Phasage recommandé

1. **Phase A — bandeau prototype** (~150×40 mm, ~30 €) : peigne LOCI +
   TXS + DIN cassette + imprimante + jack 5 V. Valide le bus, la LOCI
   réelle et les niveaux — risque minimal.
2. **Phase B — carte format Atmos** : reprend la phase A validée, ajoute
   berceaux Pico/Tang, USB, HP, fixations boîtier. Lancée seulement après
   validation électrique de la phase A et mesures du boîtier.

## Notes de conception vérifiées

- **TXS0108E TSSOP-20 (PW), brochage vérifié sur datasheet TI SCES642H** :
  1=A1, 2=VCCA(3,3 V), 3..9=A2..A8, 10=OE, 11=GND, 12..18=B8..B2,
  **19=VCCB(5 V), 20=B1**. OE : pull-down 10 kΩ vers GND (Hi-Z au
  démarrage, exigence datasheet) + strap vers 3,3 V pour activer.
- Moteur cassette : contact sec attendu par le magnétophone → relais
  statique PhotoMOS (AQY212 ou TLP222A) piloté par MOTOR_3V3, pas un
  transistor à la masse.
- TAPE IN : comparateur LM393 (seuil ~200 mV) avec pull-up 3,3 V en sortie.
- TAPE OUT : diviseur résistif vers niveau ligne (~10 k/1 k).

## Fabrication

- PCB 2 couches ~150×40 mm, doigts or biseautés (option « gold fingers +
  bevel » chez JLCPCB), épaisseur 1,6 mm.
- Assemblage face top (économique) : TXS0108E, LM393, passifs.
- Connecteurs traversants (HDMI, DIN-7, headers, jack) en assemblage
  standard JLCPCB.
- Fichiers à produire : KiCad (schéma + PCB), gerbers, BOM.csv, CPL.csv.

## État

- [x] Spécification (ce document)
- [x] RTL : signaux imprimante + cassette exposés (cf. CHANGELOG)
- [ ] Schéma KiCad (en attente installation KiCad : `sudo apt install kicad`)
- [ ] PCB + DRC + gerbers + BOM/CPL JLCPCB
- [ ] Vérification du pas exact du connecteur LOCI avant envoi en fab
      (mesure sur la cartouche réelle : pas attendu 2,54 mm, à confirmer !)
