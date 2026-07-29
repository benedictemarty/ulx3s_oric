# CHANGELOG — ulx3s_oric

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]

## [1.1.1] — 2026-07-29 — Correctif HIRES

### Corrigé
- **HIRES : charset des 3 rangées texte du bas** — la base charset suit
  désormais le mode global de la ULA (`vmode[2]`) et non la zone de la
  ligne : en HIRES ces rangées lisent $9800/$9C00 (seule zone entretenue
  par la ROM), $B400 contenant alors des données périmées (symptôme
  constaté sur carte : texte blanc sur fond blanc). Conforme à
  `get_charset_byte` de la référence. Test ajouté à tb_ula.
- **Clignotement** : inversion périodique des couleurs (XOR avec le bit 7),
  et non masquage du caractère — conforme à `blink_phase_on` de la
  référence.

## [1.1.0] — 2026-07-29 — Sprint 2 : clavier série + fiabilisation HDMI

### Déployé
- Bitstream v1.1.0 gravé en flash SPI (--unprotect-flash requis) :
  démarrage autonome à la mise sous tension.

### Ajouté
- **Clavier série depuis le PC** (port US1, 115200 8N1) : `uart_rx.v` +
  `key_injector.v` (FIFO 256 octets, table ASCII→matrice Oric issue des
  tables ROM $FF70/$FFB0, frappe 45 ms + pause 25 ms, Shift automatique,
  CR/LF dédupliqués). Voir docs/CLAVIER_SERIE.md. Testbench `tb_injector`.

### Corrigé
- **HDMI : chargement TMDS aligné en phase** : le compteur mod-5 libre
  pouvait verrouiller les mots TMDS pendant leur transition selon la phase
  de démarrage de la PLL (perte de synchro intermittente constatée sur
  écran). Le front de clk_pixel est maintenant détecté dans le domaine
  125 MHz et le chargement s'effectue ~16 ns après la mise à jour des mots.

## [1.0.0] — 2026-07-29 — Sprint 1 terminé : « Il boote »

### Validé
- `tb_boot` : boot complet de la ROM en simulation — écran
  « ORIC EXTENDED BASIC V1.1 / © 1983 TANGERINE / 37631 BYTES FREE / Ready »
  identique à la machine réelle (bannière + charset copiés par la ROM).
- Timing nextpnr final : clk_sys 54,5 MHz (requis 25), clk_shift 256 MHz
  (requis 125), clk_pixel 59,4 MHz, clk_usb 76 MHz — tous PASS.
- Ressources ECP5-85F : 87/208 DP16KD (41 %), 4 MULT18, 2/4 PLL.
- Bitstream `build/oric_ulx3s.bit` flashé sur carte (openFPGALoader, SRAM).

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
