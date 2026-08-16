# Émulation LOCI dans le FPGA — document de conception

Objectif : décider **ce qui, de la carte LOCI, peut et doit être « émulé »**
dans l'ECP5 de l'ULX3S — et surtout **ce qui ne peut pas l'être** honnêtement
en RTL pur. Ce document tranche l'architecture **avant** d'écrire du Verilog.

> Statut : **conception seule** (2026-08-17). Aucune ligne de RTL « loci »
> n'existe encore. Le pont physique vers une **vraie** LOCI existe déjà
> (`rtl/expansion_port.v`, cf. `docs/PORT_EXTENSION.md`,
> `docs/NOTE_EQUIPE_LIAISON_LOCI.md`) — c'est un sujet distinct.

---

## 1. Ce qu'est réellement la LOCI (constat, sources locales)

La LOCI (`sodiumlb/loci-hardware` rev 1.3, firmware `loci-fw` v0.3.1) **n'est
pas un circuit logique** : c'est un **RP2040** (`U1`, `BOM_loci-1.3.csv`) qui
**espionne le bus 6502** via ses **PIO** (state machines matérielles) et exécute
un **firmware C** sur ses deux cœurs. Toute sa valeur est **logicielle**.

Puces d'interface (adaptation de niveau uniquement, pas de logique métier) :
`U3` 74LVC4245 (bus données), `U5/U7/U8/U9` 74LVC1G57, `U6` PI4IOE5V6408.

### Cartographie bus 6502 servie par la LOCI

| Fenêtre | Rôle | Nature |
|---|---|---|
| `$0310–$031F` | WD1793 + Microdisc **émulé** (stub ou FDC cycle-accurate) | logiciel |
| `$0380–$0383` | **ACIA 6551** (canal modem / CDC-USB vers Pico W) | **registres** |
| `$03A0–$03BF` | **MIA** (*Memory Interface Adapter*) : console, **API POSIX**, xstack, errno | **firmware** |
| `$C000–$FFFF` | ROM menu LOCI, swap à chaud via `/ROMDIS`+`/MAP` | overlay + firmware |

Contrôle du bus : le RP2040 génère `/MAP`, `/ROMDIS`, `/IRQ` et pilote la
direction des transceivers **par ses PIO**, avec des **délais accordables**
(`tmap/tior/tiow/tiod/tadr`, ops `0xA1–0xA6`, auto-tuning `ADJ_SCAN`) — un
étalonnage analogique-temporel du sampling, propre à une implémentation MCU.

### Le cœur MIA (`$03A0–$03BF`) — pourquoi c'est du logiciel

Registres MIA (offsets depuis `$03A0`, réf `~/Oric1/include/io/loci.h:23-56`) :
`FLAGS`, `CONSOLE TX/RX`, `RW0/STEP0` & `RW1/STEP1` (2 fenêtres DMA
auto-incrément), `xstack` (512 o), `errno`, **`API_OP` ($03AF)** dont l'écriture
**déclenche** une opération, `BUSY` ($03B2 bit 7) à scruter, registres de retour
`A/X/SREG`.

L'API expose ~36 opérations **POSIX** : `open/read/write/lseek/close/unlink/
rename`, `opendir/readdir/mkdir`, `mount`, `boot`, horloge RTC, RNG, HID USB.
C'est un **système de fichiers FAT/LittleFS complet + montages dynamiques +
pile USB** tournant sur le MCU. **Réimplémenter cela en machine à états Verilog,
c'est reconstruire un OS de fichiers en matériel.**

---

## 2. Le recouvrement : ce projet émule DÉJÀ la fonction disque

`ulx3s_oric` fournit **déjà** le service que rend la LOCI (charger/booter une
disquette), mais par une **autre voie, native et validée sur carte** :

```
SD (SPI) ─► sd_spi.v ─► fat32.v ─► dsk_track.v ─► wd1793.v ─► microdisc.v ─► bus 6502
                                                             ($0310–$0318, EPROM $E000)
```

- Boot **Sedoric** depuis un `.dsk` sur SD : **VALIDÉ carte** (US-DISK.4).
- Sélection/insertion par **OSD** (BTN3/BTN4), reset auto à l'insertion.
- Écriture disquette en cours (US-DISK.5, phases 1-2 faites).

→ Une « soft-LOCI » qui referait `open/mount/boot` **dupliquerait l'essentiel
de l'existant** sans gain fonctionnel. Le seul morceau **distinct** de
l'existant est le **canal modem ACIA `$0380`**.

---

## 3. Décision d'architecture — ce qu'on émule, ce qu'on n'émule pas

| Bloc LOCI | Émulable RTL pur ? | Décision |
|---|---|---|
| **ACIA `$0380–$0383`** | ✅ oui (registres, bien spécifié) | **Candidat n°1** — voir §4 |
| MIA `$03A0` API POSIX | ❌ non sans soft-CPU + OS fichiers | **Hors périmètre RTL** |
| ROM menu `$C000` swap | ⚠️ overlay possible, mais casse la ROM BASIC interne | Reporté (l'OSD natif remplit ce rôle) |
| Tuning PIO `tmap/tior…` | ❌ artefact du sampling MCU | **Sans objet** en émulation interne (bus déjà synchrone) |
| WD1793/Microdisc | ✅ **déjà fait** nativement | Réutiliser l'existant |

**Conclusion.** Une « émulation LOCI » **fidèle et complète en RTL pur n'est pas
réaliste** : son cœur (MIA/POSIX/ROM-swap) est du firmware RP2040. La seule
brique LOCI à la fois **utile, distincte de l'existant et honnêtement émulable**
est l'**ACIA 6551 à `$0380`**. Le reste relèverait d'un **soft-CPU exécutant
`loci-fw`** — un projet à part entière (cf. §6), non retenu ici.

---

## 4. Brique retenue — ACIA 6551 « façon LOCI » à `$0380`

### 4.1 Constat de départ
Le projet a **déjà** un 6551 : `rtl/acia6551.v`, mappé **`$031C–$031F`** (pont
ESP32, épopée MODEM WiFi). La LOCI, elle, met son ACIA en **`$0380–$0383`**.

### 4.2 Registres (fidèles à `loci-fw/src/mia/oric/acia.c`)

| Offset | Adresse | Lecture | Écriture |
|---|---|---|---|
| 0 | `$0380` | `DATA` RX (efface RX_FULL) | `DATA` TX (efface TX_EMPTY) |
| 1 | `$0381` | `STATUS` | — |
| 2 | `$0382` | — | `COMMAND` |
| 3 | `$0383` | — | `CONTROL` |

`STATUS` : b7 IRQ, b6 /DSR, b5 /DCD, b4 TX_EMPTY, b3 RX_FULL, b2 OVR, b1 FRM,
b0 PAR. Reset matériel LOCI → `STATUS=$70` (`TX_EMPTY|/DCD|/DSR`),
`COMMAND=$02`, `CONTROL=$00` (réf `acia.c:337-354`).

### 4.3 Question ouverte — **à trancher avant de coder** (§ Backlog US-LOCI.1)
Faut-il :
- **(a)** un **second** 6551 à `$0380` (LOCI) **coexistant** avec celui de
  `$031C` (ESP32/MODEM) — deux canaux série distincts ? ou
- **(b)** rendre l'adresse du 6551 existant **paramétrable/commutable**
  (`$031C` ↔ `$0380`) — un seul cœur, moins de LUT, mais pas les deux à la fois ?

`$0380–$03FF` tombe aujourd'hui dans `sel_ext` (exporté au port d'extension) et
n'est **jamais adressé en interne** — la fenêtre est donc libre côté CPU interne
(réf `rtl/oric_atmos.v`, décodage `sel_ext = sel_io & ~sel_via & ~sel_acia &
~sel_md`). Ajouter un `sel_loci` **prioritaire sur `sel_ext`** est propre.

⚠️ Coexistence avec une **vraie** LOCI branchée sur le port d'extension : si un
soft-LOCI interne décode `$0380`, il **entre en conflit** avec la carte
physique. Les deux usages sont **mutuellement exclusifs** (garde à prévoir :
`wifi_en`/switch, comme le Microdisc).

---

## 5. Points d'intégration (si US-LOCI.1 est votée)

1. `rtl/oric_atmos.v` : ajouter `sel_loci = sel_io & (addr[7:2]==6'b111000_0>>…)`
   pour `$0380–$0383`, **prioritaire** sur `sel_ext` ; router `loci_dout` dans
   le multiplexeur `cpu_di` ; OR l'IRQ (`… | loci_irq`).
2. `rtl/top_ulx3s.v` : instancier le cœur, câbler le pont UART (réutiliser la
   voie ESP32 `wifi_rxd/txd` ou une paire `gp[]` selon décision (a)/(b)).
3. Testbench `sim/tb_loci_acia.v` + cible Makefile (calqué sur `tb_acia`).
4. Pas de modification de `expansion_port.v`.

---

## 6. Écarté — soft-CPU exécutant le vrai firmware LOCI

Pour une fidélité **totale** (MIA POSIX, ROM swap, montages) il faudrait
embarquer un **RISC-V/Cortex-M soft-core** dans l'ECP5, porter `loci-fw`
(RP2040 → soft-core), et remplacer les **PIO** par de la logique. C'est un
**projet en soi** (portage OS + FatFS + pile USB), sans bénéfice face à la
chaîne disque native déjà validée. **Non retenu.** Documenté ici pour mémoire.

---

## 7. Ce que je ne sais pas / à confirmer avec les sources si on avance

- Format `.dsk` **interne** attendu par un `mount` LOCI : non explicité dans les
  sources (seul le montage par chemin l'est). Sans objet tant qu'on reste sur
  l'ACIA `$0380`.
- Comportement CDC exact si `parity ≠ NONE` : jamais exercé par le code client
  (réf agent protocole) — à ignorer en v0.

---

## 8. Backlog agile (proposé — voir `docs/BACKLOG.md`, épopée LOCI)

- **US-LOCI.0** (ce doc) — conception + décision de périmètre. **FAIT.**
- **US-LOCI.1** — trancher (a) 2ᵉ 6551 à `$0380` vs (b) 6551 commutable ;
  garde d'exclusivité avec la vraie LOCI.
- **US-LOCI.2** — RTL `loci_acia` (ou paramétrage de `acia6551.v`) + `sel_loci`
  prioritaire + testbench `tb_loci_acia`.
- **US-LOCI.3** — intégration top + pont UART + synthèse timing.
- **US-LOCI.4** — validation carte (dialogue AT depuis l'Oric sur `$0380`).
