# Version SIMPLIFIÉE — `loci_lvc_simple` (façon vraie LOCI)

**Date :** 2026-08-15 · **Auteur :** bmarty

## L'idée
La carte à **5 transceivers** (`loci_lvc` / `SPEC_NETLIST.md`) est dense et dure à
router. Or la **vraie LOCI n'a qu'UN transceiver octal** (74LVC4245A) + de petits
buffers, parce que sa logique est dans le RP2040.

On applique le même principe : **les entrées des périphériques Oric sont
5 V-tolérantes** (seuil TTL ≈ 2 V), donc les **sorties du FPGA** (A0–A15, Φ2, R/W,
/IO) pilotent le peigne **en direct en 3,3 V — sans aucun transceiver**. Il ne
reste à adapter que :
- le **bus de données** (bidirectionnel) → **1× 74LVC4245A** (`U1`) ;
- les **entrées de contrôle** (/IRQ, /ROMDIS, /MAP, /IOCTL, venant du périphérique
  en 5 V) → **1× 74LVC245** (`U2`, alim 3,3 V, 5 V-tolérant) ;
- **/RESET** (drain ouvert) → **1× BSS138** (`Q1`).

## Résultat
- **15 composants** au lieu de 25.
- **Route en 2 couches** : freerouting ferme **tous les signaux, 0 violation**
  (là où la version 5-transceivers plafonnait à 12–17 signaux !).
- Reste **9 masses à coudre** + 3 vias GND de freerouting à écarter — **finition
  triviale**.

## Reproduire
```sh
python3 gen_pcb_simple.py loci_lvc_simple.kicad_pcb   # placement + zones
python3 route_simple.py                               # freerouting 2 couches
# -> tous signaux routes, 0 violation, 9 masses restantes
```

## Finir (couture des 9 masses)
Le plus simple : **passer en 4 couches** (plan GND interne) → la couture devient un
via par pad GND (cf. `convert_6layer.py` adapté, ou dans KiCad). Ou, en 2 couches,
poser à la main un **via GND** près de chaque pad GND non connecté (9 vias, ~5 min
dans KiCad). Puis DRC → 0/0 → Gerbers → JLCPCB.

## BOM (simplifiée)
| Réf | Composant | Boîtier |
|---|---|---|
| U1 | SN74LVCC3245APW (data) | TSSOP-24 |
| U2 | SN74LVC245APW (entrées ctrl) | TSSOP-20 |
| Q1 | BSS138 (/RESET) | SOT-23 |
| R1–R4 | 10 kΩ | 0603 |
| C1–C5 | 100 nF / 10 µF | 0603 / 0805 |
| J_ULX | 2×20 (vers ULX3S) | THT |
| J_EXP | peigne 34 doigts | bord de carte |
| J_PWR | jack +5 V | THT |

> **Mapping GPIO ULX3S** : inchangé (`top_ulx3s.v` / `mapping-gpio-contraintes.md`).
> Les nets `A5V*`, `RW5`, `PHI2_5`, `IO5_n` disparaissent (adresses/Φ2/R-W//IO
> pilotées en direct) ; seuls `D5V*`, `*5_n`, `RST5_n` restent (via composants).
