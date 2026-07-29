# Architecture du core Oric Atmos pour ULX3S

## Domaines d'horloge

| Horloge   | Fréquence | Rôle                                            |
|-----------|-----------|-------------------------------------------------|
| clk_sys   | 24 MHz    | Domaine système : CPU, VIA, AY, ULA, RAM/ROM    |
| clk_pixel | 25 MHz    | Timing vidéo 640×480@60                         |
| clk_shift | 125 MHz   | Sérialisation TMDS (DDR ×2 = 250 Mb/s/canal)    |
| clk_usb   | 12 MHz    | Hôte USB HID (clavier)                          |

Dans le domaine système, des *clock enables* dérivent les cadences d'époque :
- `cen1` : 1 MHz (24÷24) → CPU 6502, VIA 6522, AY-3-8912 (1 MHz authentique)
- `cen6` : 6 MHz (24÷4) → pixel ULA (64 µs/ligne × 6 MHz = 384 pixels/ligne)

## Chemin vidéo

L'Oric génère du PAL 50 Hz (312 lignes), l'écran HDMI attend du 640×480@60.
Découplage par **framebuffer double horloge** en BRAM :

```
ULA (clk_sys, cen6)  ──écrit──▶  FB 240×224 ×4 bits  ──lit──▶  HDMI 640×480@60
                                 (27 Ko BRAM, 2 ports)          zoom ×2, centré
```

- Côté ULA : balayage authentique 384×312 à 6 MHz, fetch écran/charset sur le
  port B de la RAM 64 Ko (dual-port, donc zéro contention avec le CPU).
- Côté HDMI : fenêtre active 480×448 centrée (marges 80 px H, 16 px V),
  chaque pixel Oric affiché 2×2. Les trames 50 Hz/60 Hz battent librement
  (tearing rare et acceptable en v1).

## Mémoire

| Plage        | Contenu                                    |
|--------------|--------------------------------------------|
| $0000–$BFFF  | RAM 48 Ko (BRAM dual-port)                 |
| $0300–$03FF  | VIA 6522 (page I/O, miroirs de $0300–$030F)|
| $C000–$FFFF  | ROM BASIC 1.1b 16 Ko (BRAM, écriture ignorée) |

Zones vidéo dans la RAM (lues par la ULA) : texte $BB80, hires $A000,
charsets $B400/$B800 (text) et $9800/$9C00 (hires).

## Clavier

Chaîne complète : clavier USB → usb_hid_host (12 MHz) → synchroniseurs →
table scancode HID → matrice 8×8 Oric (`pressed[col][row]`) →
`PB3 = |(pressed[ORB[2:0]] & ~AY_IOA)` (sense actif haut, colonnes actives bas).

Positions spéciales : LSHIFT (4,4), RSHIFT (7,4), LCTRL (2,4), FUNCT (5,4),
RETURN (7,5), ESC (1,5), flèches (4,3)(4,6)(4,5)(4,7), DEL (5,5).

## AY-3-8912

Bus piloté par la VIA : BC1 = CA2, BDIR = CB2 (modes manuels 110/111 du PCR),
données sur le port A. Le port IOA de l'AY pilote les colonnes clavier.
Audio : sortie `sound[9:0]` de jt49 → 4 bits MSB → DAC résistif jack ULX3S.

## Décisions notables

- **Pas de VHDL** : pas de plugin GHDL pour yosys sur cette machine ; tous les
  composants sont en Verilog (d'où la réécriture de la ULA et de la VIA plutôt
  que le port du core MiST).
- ULA conforme au rapport d'analyse de `~/Oric1/src/video/` (constantes :
  64 cycles/ligne, 312 lignes, VSYNC ligne 256, attributs `(byte & 0x60)==0`,
  inversion = XOR 7, blink = bit 4 du compteur de trames).
- La VIA implémente T1/T2, latching, CA2/CB2 modes manuels — le shift register
  est partiel (suffisant pour le boot et le clavier ; la cassette viendra en v2).
