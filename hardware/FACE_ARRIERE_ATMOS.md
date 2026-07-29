# Carte « Atmos moderne » — carte mère format Oric Atmos

Carte mère complète au format Atmos, **motorisée par le Tang Nano 20K en
berceau** (le core Oric y sera porté — voir « Portage Gowin » ci-dessous).
L'ULX3S reste la plateforme de développement du core, hors carte.
Berceaux pour 2 Pico W, 2 USB-A latéraux, connecteurs d'époque à l'arrière.

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

Principe : **un Pico = un firmware** ; les berceaux sont de simples
supports femelles, à peupler selon l'usage. Avec la LOCI réelle branchée
sur le peigne, le berceau #1 (LOCI intégrée) reste VIDE — un seul Pico W
(#2, modem WiFi + scan clavier) suffit. Le #1 se peuple pour une config
autonome sans cartouche.

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

- **Slot micro-SD ACCESSIBLE DE L'EXTÉRIEUR** (exigence 2026-07-29) :
  monté au bord arrière de la carte, poussoir push-push, câblé en SPI sur
  le berceau Pico #1 — c'est le stockage LOCI (.tap/.dsk), celui qu'on
  change au quotidien. Accès par l'ancienne découpe TV (RF) du boîtier
  Atmos, inutilisée (prévoir un insert imprimé 3D pour guider la carte
  dans l'ouverture ronde).
- Le micro-SD embarqué du Tang Nano 20K (core, rarement manipulé) reste
  interne ; en cas de besoin, une rallonge micro-SD souple peut le
  déporter.
- **RAM : aucun boîtier sur la carte porteuse.** La RAM de l'Oric (64 Ko)
  est en BRAM dans le FPGA ; le Tang Nano 20K apporte 8 Mo de SDRAM
  intégrés — le bus 6502 n'adresse que 64 Ko.

## USB latéraux

Chaque USB-A latéral est un port **hôte PIO-USB appartenant à un Pico**
(D+/D- sur 2 GPIO + 5 V du jack ; le Tang Nano n'a aucun rôle USB) :
- **USB1 → Pico #1** (firmware LOCI) : clé USB de stockage et
  clavier/souris HID, comme le port USB de la vraie cartouche (hub
  supporté par le firmware) ;
- **USB2 → Pico #2** (modem WiFi + scan matrice) : clavier USB de secours
  quand le berceau #1 est vide (vraie LOCI sur le peigne).
La LOCI réelle branchée sur le peigne conserve son propre port USB.
Les micro-USB natifs des Picos restent accessibles sur les berceaux pour
flasher leurs firmwares (opération d'atelier, ne sort pas du boîtier).

## Portage Gowin (nouveau chantier RTL)

Le core développé sur ULX3S (ECP5) devra être porté sur le GW2AR-18 du
Tang Nano 20K : chaîne yosys `synth_gowin` + nextpnr-himbaechel/apicula
(le Tang Nano 20K est bien supporté par la chaîne libre), ou Gowin EDA.
À adapter : PLL (rPLL Gowin), sérialiseur TMDS (primitives ODDR Gowin),
BRAM (inférence identique), USB clavier (déplacé vers les Pico).
CPU/ULA/VIA/AY : portables tels quels. → épic au backlog.

## Alimentation

- Le jack 5 V alimente exclusivement le domaine 5 V de la carte
  (VCCB des TXS, cartouche broche 33, imprimante, LM393).
- L'ULX3S garde sa propre alimentation USB. **Masses communes obligatoires.**
- Prévoir 5 V / 1 A (la LOCI consomme < 300 mA).

## Format : carte mère Atmos complète

**Boîtier cible acté (2026-07-29) : OriClone-1** — boîtier imprimable 3D
(Thingiverse 6228328, CC-BY-SA, ~284×205×~100 mm assemblé) conçu pour la
carte du projet OriClone-1 de JennyDigital (github.com/JennyDigital/OriClone-1,
cloné en `hardware/oriclone-1-ref/`). Notre carte reprend donc le gabarit
**OriClone-1 : 206,5 × 138,0 mm**, trous de fixation à (3,8;3,8),
(3,8;133), (96,8;133), (202,5;3,8), (202,5;133) mm (+ 2 petits trous à
l'origine), extraits du fichier Eagle `OriClone-1.brd`. Le clavier peut
être la platine **« Oric Tactile KB » du même dépôt** (switches MX,
gerbers prêts à commander, compatible avec ce boîtier et sa touche SHIFT
imprimée). Positions des connecteurs arrière à reprendre du .brd au
moment du routage :
- connecteurs arrière positionnés exactement comme l'origine (découpes du
  boîtier) : le peigne d'extension au bord arrière droit, DIN cassette,
  port imprimante, HDMI à l'emplacement du DIN RGB, jack alim ;
- trous de fixation aux emplacements des plots du boîtier Atmos ;
- **le Tang Nano 20K en berceau est le cœur** : son HDMI est déporté sur le
  connecteur arrière (câble/adaptateur court), son micro-SD sert au core,
  sa SDRAM 8 Mo est intégrée ; le bus 6502 5 V sort de ses GPIO via les
  TXS0108E ;
- **haut-parleur** : emplacement pour HP Ø 40-50 mm (comme l'origine) +
  ampli classe D PAM8302 attaqué en PWM/sigma-delta depuis un GPIO du
  Tang Nano ;
- **budget GPIO Tang Nano 20K** (~40 broches utiles) : bus extension
  (32) + cassette (3) + OE + audio + pont UART Pico #2 (2) ≈ 40 ;
- **architecture satellites (actée 2026-07-29)** : seuls le FPGA et la
  LOCI (réelle ou Pico #1 avec le firmware LOCI, ~26 GPIO consommés par
  le bus) touchent le bus parallèle. Le Pico #2 est un satellite HORS
  bus relié au FPGA par un **pont UART multiplexé** (2 GPIO) qui
  transporte : les octets imprimante (logique VIA dans le FPGA, lignes
  Centronics physiques et handshake ACK sur le Pico — mode « imprimante
  virtuelle » vers SD/WiFi possible), le modem WiFi (ACIA 6551 en RTL
  dans le FPGA, modèle dispo dans la référence Phosphoric), et les
  événements du clavier matrice scanné par le Pico ;
- **pont UART : aucun composant à ajouter** (pistes 3,3 V courtes sur
  PCB ; la liaison PC du Nano 20K passe par son BL616 embarqué, comme le
  FTDI de l'ULX3S). Protocole du pont avec trames typées + CRC8 +
  acquittement (3 flux multiplexés : imprimante, modem ACIA, clavier) —
  la robustesse est logicielle, pas matérielle ;
- **clavier d'origine réutilisable tel quel** : la platine Atmos est une
  matrice 8×8 passive (aucune électronique). Header nappe au même
  emplacement que la carte d'origine (brochage : schéma du manuel de
  service, à transcrire au routage). Scan par le **Pico #2** (16 GPIO,
  injection vers le core par le canal clavier série existant) — le FPGA
  reste déchargé. Pas de diodes dans la matrice d'origine : ghosting
  authentique conservé.

⚠️ Mesures à faire sur boîtier/carte réels avant le routage final :
dimensions exactes, positions des découpes arrière, entraxes de fixation,
position du connecteur nappe clavier.

## Stratégie : CARTE UNIQUE (décision bmarty 2026-07-29)

**Une seule platine porte tout** : berceau Tang Nano 20K, 2 berceaux
Pico W, les 6 TXS, le peigne LOCI, cassette, imprimante, HDMI déporté,
micro-SD externe, HP, clavier. Pas de bandeau intermédiaire commandé.

Le dossier « phase A » (hardware/phaseA/) N'EST PAS perdu : c'est le
prototype virtuel dont la carte unique hérite les blocs VALIDÉS PAR DRC :
banc de 6 TXS et affectations, géométrie exacte du peigne (pas confirmé
sur la LOCI réelle), chaîne analogique cassette (LM393+hystérésis,
PhotoMOS), port imprimante, pinouts fan-out monotone, et toutes les
leçons de routage (paires de doigts, échappements TSSOP, routage
conjoint). Maîtrise du risque sans deuxième commande : DRC 0 erreur
exigé + revue visuelle des rendus + lot de 5 (une itération de réserve).

Le boîtier paramétrique OpenSCAD (backlog S5) est généré depuis les
coordonnées des connecteurs de CETTE carte : gabarit libre (plus
contraint par l'OriClone), silhouette Atmos par le profil extrait.

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
