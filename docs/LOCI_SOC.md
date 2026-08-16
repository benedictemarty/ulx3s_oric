# LOCI sur soft-core FPGA — document de conception (SoC)

Objectif : **exécuter (un portage de) le firmware `loci-fw`** sur un **soft-core**
embarqué dans l'ECP5 de l'ULX3S, pour obtenir la LOCI la plus **fidèle** possible
sans la carte RP2040 physique. Ce document tranche la faisabilité, le choix du
cœur et l'architecture **avant** d'écrire du RTL ou de porter du firmware.

> Statut : **conception seule** (2026-08-17). Fait suite à `docs/LOCI_EMULATION.md`
> (qui écartait le RTL pur et le soft-core comme « projet en soi ») : ici on
> **assume** ce projet et on le cadre honnêtement. Décision de périmètre prise
> avec bmarty : voie **soft-core + firmware**, fidélité maximale.

---

## 1. Verdict de faisabilité (recherche 2026-08-17, faits)

- **Aucun portage RP6502/RP2040 → FPGA n'existe.** Le RP6502 (base de la LOCI)
  exploite les capacités **natives** du RP2040 (PIO, dual-core), pas un soft-core.
  → Rien à réutiliser : c'est *from scratch*.
- **Cortex-M0 open-source sur ECP5 = expérimental.** Le netlist ARM DesignStart
  est sous licence/obfusqué ; « an experiment in creating an ARM Cortex-M0 SoC
  using only open source tools » existe mais n'est pas un drop-in yosys/nextpnr.
- **RISC-V sur ECP5-85F = voie ouverte éprouvée.** yosys/nextpnr/Trellis couvrent
  le 85K LE ; l'écosystème y fait tourner des SoC complets (jusqu'à booter Linux
  sur OpenRISC). **LiteX** fournit une cible **ULX3S** clé en main (VexRiscv +
  SDRAM). → **On part sur RISC-V, pas ARM.**

**Conséquence : « exécuter `loci-fw` tel quel » n'est pas atteignable.** La voie
ARM (binaire inchangé) est bloquée par la licence/toolchain ; la voie RISC-V
impose de **recompiler** `loci-fw`, donc de **réécrire tout son HAL RP2040**.

---

## 2. Le vrai coût : le HAL RP2040 de `loci-fw`

`loci-fw` est **intimement lié au pico-sdk**. Portage RISC-V = remplacer :

| Couche `loci-fw` (RP2040) | Ampleur | Sur notre FPGA |
|---|---|---|
| **PIO** (bus-sniffing `$03A0`, ROM read, MAP) | cœur du firmware | **inutile** → pont RTL natif (bus déjà interne, cf. `oric_atmos.v`/`expansion_port.v`) |
| **WD1793 / Microdisc** émulé | moyen | **déjà en RTL** (`wd1793.v`+`microdisc.v`) — non porté |
| `fatfs` + SD (SPI/SDIO) | moyen | soft-core + `sd_spi.v` existant |
| `littlefs` sur flash interne | faible | flash SPI ULX3S ou SDRAM |
| **XIP flash** (exécution) | structurel | firmware en **SDRAM** (l'ULX3S en a) |
| **dual-core** (core1 = `act_loop` temps-réel) | structurel | **disparaît** : le bus est servi en RTL, pas par un core |
| **USB host** (modem CDC) | **le mur** | à construire (voir §4) |
| RTC, RNG, HID USB | faible | périphériques SoC / réutiliser l'existant |

### L'ironie « fidélité »
Les deux pièces les plus « LOCI » du HAL (**PIO bus-sniffing** + **WD1793**) sont
**redondantes** avec ce que `ulx3s_oric` fait déjà **nativement et mieux**. On
porterait un gros firmware pour ensuite **jeter** ses couches bus/disque. Donc
« fidélité maximale » ne veut PAS dire « tout le firmware » : ça veut dire
**garder la logique applicative** (MIA/API POSIX, menu, montages) et **brancher**
sur le natif FPGA.

---

## 3. Architecture cible retenue — SoC LiteX/VexRiscv

```
        ECP5-85F (ULX3S)
  ┌───────────────────────────────────────────────┐
  │  VexRiscv (RV32IM)  ── Wishbone/AXI ──┐        │
  │     │ firmware = loci-fw porté        │        │
  │     │ (MIA/API, fatfs, littlefs, menu)│        │
  │     ▼                                 ▼        │
  │  SDRAM ctrl (code+data)      Périphériques :   │
  │                              - MIA bridge  ────┼──► bus 6502 natif (oric_atmos)
  │                              - SD ctrl (sd_spi)│        $03A0-$03BF + ROM $C000
  │                              - USB host (§4) ──┼──► modem CDC
  │                              - UART debug      │
  │                                               │
  │  [déjà présent] 6502 + ULA + VIA + Microdisc  │
  │  + WD1793 + fat32 + HDMI + clavier ...         │
  └───────────────────────────────────────────────┘
```

Le **« MIA bridge »** est le périphérique-clé neuf : un bloc RTL qui expose au
6502 les registres `$03A0-$03BF` (FLAGS, RW0/STEP0, RW1/STEP1, xstack, API_OP,
BUSY, retours A/X/SREG — cf. `docs/LOCI_EMULATION.md` §1) et les présente au
soft-core comme un registre-file Wishbone. Le firmware porté lit/écrit ce
registre-file au lieu de piloter les PIO. Le timing temps-réel du RP2040
(`act_loop`, tuning `tior/tmap`) **disparaît** : le bus est synchrone en RTL.

---

## 4. Le point dur unique — USB host du modem

Le canal modem de la LOCI est un **CDC-USB host** (`tinyusb` host + PicoWiFiModemUSB).
L'ULX3S **n'a pas d'USB host matériel** dédié ; il expose l'USB via le FPGA
(soft-PHY). Options, par risque croissant de rejet :

1. **Contourner l'USB** : le modem WiFi de `ulx3s_oric` est **déjà** l'ESP32
   interne via UART (épopée MODEM, 6551 à `$031C`). → Le « modem LOCI » pourrait
   être un **UART** vers l'ESP32, pas de l'USB host. **Fidélité réduite mais
   coût quasi nul.** *(recommandé pour un v0)*
2. **HID/CDC host minimal** : étendre `third_party/usb_hid_host` (déjà utilisé
   pour le clavier) vers un CDC host bespoke. Faisable, spécifique, pas `tinyusb`.
3. **`tinyusb` host sur le soft-core** : le plus fidèle, le plus lourd (pile USB
   host + soft-PHY temps-réel dans le SoC). À réserver si (1)/(2) insuffisants.

→ **À trancher tôt** : la fidélité visée sur le modem conditionne l'ampleur.

---

## 5. Ressources ULX3S (à confirmer sur la carte réelle)

- ECP5 **85F** (~84 K LUT) — largement assez pour VexRiscv + périphériques.
- **SDRAM** (SDR, ~32 Mo sur la 85F) — accueille code+data du firmware porté.
- **SD** micro (SPI) — déjà piloté (`sd_spi.v`).
- **USB** (US1/US2 via soft-PHY), **ESP32** interne (UART), **flash SPI** de conf.
- LiteX a une cible `ulx3s` (VexRiscv + LiteSDRAM) → **socle de démarrage**.

> ⚠️ Je ne sais PAS encore : la coexistence LiteX-SoC ↔ le RTL Oric actuel
> (`top_ulx3s.v` n'est pas un design LiteX). Deux voies : (a) intégrer VexRiscv
> **dans** notre RTL (instancier le cœur seul + Wishbone maison), ou (b) partir
> du SoC LiteX et y **importer** l'Oric comme périphérique. À trancher (§7).

---

## 6. Jalons agiles (dé-risquer avant d'investir)

- **US-LOCI-SOC.0** — ce doc : faisabilité, cœur, archi, point USB. **FAIT.**
- **US-LOCI-SOC.1** — *Spike matériel* : un VexRiscv minimal boote sur l'ULX3S
  (blinky + UART « hello »), **hors** de tout contexte Oric. Preuve carte que la
  toolchain soft-core marche chez nous. (dé-risque le socle)
- **US-LOCI-SOC.2** — *Mémoire & stockage* : SDRAM + SD lus par le soft-core
  (firmware trivial listant la carte SD via un `fatfs` porté). (dé-risque le HAL)
- **US-LOCI-SOC.3** — *Coexistence* : trancher (a)/(b) du §5 et faire cohabiter
  le SoC avec le cœur Oric sans casser le boot BASIC/Sedoric actuel.
- **US-LOCI-SOC.4** — *MIA bridge* : registre-file `$03A0-$03BF` en RTL, vu du
  6502 ET du soft-core ; premier `API_OP` bout-en-bout (ex. `CLK` ou un `open`).
- **US-LOCI-SOC.5** — *Portage `loci-fw`* : compiler la logique applicative
  (MIA/API/menu) pour RV32, HAL branché sur SOC.2/SOC.4. Itératif, op par op.
- **US-LOCI-SOC.6** — *Modem* : décision §4 (v0 = UART/ESP32), puis fidélité.
- **US-LOCI-SOC.7** — *Validation carte* : menu LOCI réel piloté depuis l'Oric.

**Critère d'arrêt honnête** : si SOC.1/SOC.2 révèlent que la coexistence
SoC↔Oric ne tient pas en timing/ressources sur la 85F, on réévalue (repli sur le
MIA RTL pur de `LOCI_EMULATION.md` §3, sans soft-core).

---

## 7. Ce que je ne sais pas encore (à lever, pas à inventer)

1. **Coexistence LiteX ↔ RTL Oric** (§5) : intégration du cœur VexRiscv seul dans
   notre `top_ulx3s.v` vs SoC LiteX englobant. Décide toute la structure de build.
2. **Empreinte** : VexRiscv + SDRAM ctrl + périphériques **en plus** de l'Oric
   complet (HDMI, USB HID, AY, disque) tiennent-ils dans la 85F en timing ? Non mesuré.
3. **Ampleur réelle du portage `loci-fw`** : quelle part du code applicatif est
   *portable* (C standard + fatfs) vs *pico-sdk* diffus dans la logique. À auditer.
4. **Modèle mémoire** : firmware en SDRAM — latence acceptable pour la logique MIA
   (pas de contrainte temps-réel bus, celle-ci passe en RTL). À confirmer.

---

## 8. Lien avec le reste du projet

- Ne remplace **pas** l'émulation disque native (épopée DISK) — la complète.
- N'est **pas** le pont vers une vraie LOCI (`expansion_port.v`, notes LOCI).
- Réutilise : `sd_spi.v`, `oric_atmos.v` (décodage bus), `usb_hid_host` (piste USB).
- Le firmware source de référence : `~/loci-build/loci-fw` et `~/loci-webdisk/
  loci-firmware` (branche `webdisk`, où la Stratégie C a libéré la RAM — sans
  objet ici puisqu'on quitte le RP2040, mais même base de code applicative).
