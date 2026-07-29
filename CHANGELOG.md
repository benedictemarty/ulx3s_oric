# CHANGELOG — ulx3s_oric

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]

## [0.2.0] — 2026-07-29 — Sprint 1 (suite)

### Ajouté
- RTL complet du core : `oric_ula.v` (PAL 384×312, TEXT/HIRES, attributs
  série, framebuffer 240×224), `via6522.v`, `oric_keyboard.v` (HID→matrice),
  `oric_atmos.v` (6502 Arlet à 1 MHz + RAM 48 Ko + ROM 16 Ko + AY jt49),
  `hdmi_out.v`/`tmds_encoder.v` (DVI 640×480@60, zoom ×2), `top_ulx3s.v`
  (2 PLL, hôte USB HID, audio jack 4 bits, LEDs de vie).
- Testbenches auto-vérifiants : `tb_via6522`, `tb_keyboard`, `tb_ula`,
  `tb_boot` (boot ROM complet). Cible `make test`.
- Makefile : synthèse yosys/nextpnr/ecppack, `make prog` (openFPGALoader).

### Corrigé
- **Protocole bus 6502 sous RDY** : le core d'Arlet ne garantit AB/WE/DO que
  pendant la phase RDY (DIMUX bascule de DIHOLD vers DI). Re-temporisation
  exacte de l'environnement natif : capture AB/WE/DO au front cen1, fetch au
  début du cycle suivant, DI verrouillé à t4 et consommé au front cen1
  suivant. Vérifié instruction par instruction contre le core en
  environnement natif pleine vitesse (sim/tb_trace.v).
- Boucle combinatoire AB→DI→AB avec le 6502 d'Arlet : lecture VIA et mux DI
  registrés.
- yosys `-noabc9` (assertion abc9 sur le pmux du CPU).
- RAM initialisée à zéro (état réel de la BRAM ECP5 ; supprime la
  propagation de X en simulation).
- clk_sys porté à 25 MHz (DIV=25) : le 1 MHz CPU est exact, ecppll ne
  pouvant pas produire 24 MHz.

## [0.1.0] — 2026-07-29 — Sprint 1

### Ajouté
- Structure initiale du projet (rtl/, third_party/, sim/, tests/, docs/, constraints/).
- Documentation : README, ARCHITECTURE, BACKLOG agile, CHANGELOG.
- Cores libres vendorés : verilog-6502 (Arlet), jt49 (jotego), usb_hid_host (nand2mario).
- Contraintes ULX3S v2.0 (ulx3s_v20.lpf, emard).
- ROM BASIC 1.1b copiée depuis la référence ~/Oric1 et convertie en .hex.
