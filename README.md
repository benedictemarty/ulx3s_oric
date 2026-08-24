# ulx3s_oric — Oric Atmos sur FPGA ULX3S

Portage matériel (core FPGA) de l'**Oric Atmos** pour la carte **ULX3S** (Lattice ECP5-85F),
entièrement en Verilog et synthétisable avec la chaîne open-source (yosys / nextpnr-ecp5).

La référence fonctionnelle est l'émulateur logiciel `~/Oric1` (timing ULA, VIA, clavier, AY
vérifiés contre son code source).

## Fonctionnalités (v1)

- CPU **6502** à 1 MHz (core Arlet Ottens)
- **ULA** vidéo réimplémentée : timing PAL 50 Hz (64 µs/ligne, 312 lignes), modes
  TEXT 40×28 et HIRES 240×200, attributs série (ink/paper/charset alternatif/double
  hauteur/clignotement/inversion), palette 8 couleurs
- ROM **BASIC 1.1b** (Atmos), 48 Ko de RAM
- **VIA 6522** complète ($0300) : ports A/B, timers T1/T2, IFR/IER, PCR/ACR
- **AY-3-8912** (core jt49) piloté par CA2/CB2 (BC1/BDIR), audio sur la prise jack
  (DAC 4 bits ULX3S)
- **Clavier USB** sur le port US2 (core usb_hid_host), traduit vers la matrice 8×8 Oric
- Sortie vidéo **HDMI/DVI** (GPDI) 640×480@60, framebuffer 240×224 doublé ×2

## Arborescence

```
rtl/           RTL spécifique au projet (ULA, VIA, clavier, top…)
third_party/   Cores libres vendorés (verilog-6502, jt49, usb_hid_host)
roms/          ROM BASIC 1.1b (+ conversion .hex pour $readmemh)
sim/           Testbenches iverilog
tests/         Scripts de test automatisés
constraints/   Fichier LPF ULX3S v2.0 (85F)
docs/          Documentation projet (architecture, backlog agile)
build/         Produits de synthèse (non versionnés)
```

## ROMs requises (non fournies)

Les ROMs propriétaires ne sont **pas distribuées** dans ce dépôt (copyright). À
placer soi-même dans `roms/` avant de construire :

| Fichier | Contenu | Format |
|---------|---------|--------|
| `roms/basic11b.rom` | BASIC 1.1b (Atmos), 16 Ko | binaire |
| `roms/basic11b.hex` | idem, converti pour `$readmemh` | un octet hexa/ligne |
| `roms/basic10.hex`  | BASIC 1.0 (banque alternative) | idem |
| `roms/microdis.hex` | firmware Microdisc (support `.dsk`) | idem |

Conversion binaire → `.hex` (exemple) :
```sh
xxd -c1 -p roms/basic11b.rom > roms/basic11b.hex
```
`roms/font8x8.hex` (police OSD, maison) est fournie.

## Construire

```sh
make            # synthèse complète -> build/oric_ulx3s.bit
make test       # lance tous les testbenches (iverilog)
make prog       # flash SRAM via openFPGALoader (ou: make prog-fujprog)
```

## Matériel requis

- ULX3S avec ECP5-**85F**
- Écran HDMI (640×480@60 minimum)
- Clavier USB (le port **US2**, connecteur micro-USB du dessus)
- Casque/enceintes sur la prise jack 3,5 mm (son AY)

## Licences

- `third_party/verilog-6502` : licence libre (voir README amont, Arlet Ottens)
- `third_party/jt49` : GPL-3.0 (Jose Tejada)
- `third_party/usb_hid_host` : MIT (nand2mario)
- RTL du projet : GPL-3.0 (contaminé par jt49)
- Les ROMs BASIC (Oric/Tangerine) et le firmware Microdisc restent la propriété
  de leurs ayants droit ; **non distribués ici** — à fournir localement (cf.
  « ROMs requises »).
