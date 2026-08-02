# CHANGELOG — ulx3s_oric

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]

### Corrigé
- **Touche accentuée AZERTY tombait sur le chiffre QWERTY** (« la touche 2
  reste à 2 même avec Shift »). Les touches dont le glyphe est hors ASCII
  (é è à ç ù ° £ § µ) renvoyaient 0 et `key_map` retombait alors sur la table
  positionnelle QWERTY (→ chiffre). Ajout d'un drapeau « touche AZERTY
  reconnue » (`azerty_map` renvoie {reconnue, ASCII}) : une touche AZERTY à
  glyphe hors ASCII ne produit rien, sans repli parasite.
- **Shift synthétisé AZERTY intermittent** (symptôme : `&&7&&&&7` en tapant
  la touche « 1 »). Sur l'Oric `&` = Shift+7 ; un Shift dérivé du même
  scancode montait exactement en même temps que la touche, et le scan
  clavier de la ROM attrapait parfois la touche seule. Diagnostic confirmé
  sur carte (le Shift *physique*, qui précède la touche, était fiable ; le
  synthétisé non). Les glyphes AZERTY à Shift sont désormais séquencés par
  une FSM dans `oric_keyboard.v` : le Shift **précède** la touche (LEAD
  ~20 ms), la **maintient** (HOLD, minimum garanti pour être vu par ≥1
  balayage), puis la **prolonge** au relâché (TAIL ~10 ms) — comme un vrai
  doigt. Lettres, touches directes, modificateurs, clavier série et Shift
  physique QWERTY restent combinatoires. `tb_azerty` étendu (avance/maintien/
  traîne vérifiés avec paramètres réduits).

### Ajouté
- **Bascule de disposition clavier QWERTY ⇄ AZERTY** (ULX3S) sur le bouton
  `BTN6` (RIGHT), anti-rebond ~10 ms + détection de front ; `led[4]` allumée
  indique le mode AZERTY. En AZERTY le décodage passe par
  `(scancode, Shift) → ASCII français → matrice Oric` en réutilisant la table
  `map_char` du clavier série (factorisée dans `rtl/ascii2oric.vh`) : lettres
  permutées (A/Q, Z/W, M…), rangée du haut en **chiffres directs** (sans
  Shift), symboles en Shift avec Shift Oric automatique (`(` = Shift+9, etc.). Les touches non
  alphanumériques (Entrée, Échap, flèches, espace) retombent sur la table
  positionnelle. Les glyphes hors ASCII (é è à ç ù ° £ § µ) sont ignorés
  (l'Oric ne les affiche pas). Nouveau testbench `tb_azerty` (7 tests dans la
  suite).
- **`rtl/ascii2oric.vh`** : table ASCII→matrice Oric partagée entre
  `key_injector` (clavier série UART) et `oric_keyboard` (disposition AZERTY),
  élimine la duplication. Makefile : `-I rtl` (iverilog) et `read_verilog
  -I../rtl` (yosys) pour l'include.

### Validé sur carte
- **Clavier USB physique fonctionnel** sur l'ULX3S (frappe réelle confirmée
  par bmarty) — clôt le point de validation matérielle US2.

## [2.0.0-tn20k] — 2026-07-29 — Portage Gowin : premier bitstream Tang Nano 20K

### Ajouté
- **Portage complet du core sur GW2AR-18** (gowin/) : bitstream
  `oric_tn20k.fs` généré par la chaîne libre (yosys synth_gowin +
  nextpnr-himbaechel/apicula + gowin_pack). LUT 19 %, timing 79,6 MHz
  pour 27 requis. Cœur Oric (6502/ULA/VIA/AY) inchangé, DIV=27.
- **Vidéo 720×576p50 par doubleur de lignes** : trames ULA et HDMI de
  longueur strictement égale (539 136 cycles, vérifié par tb_video576),
  verrouillées au reset — zéro framebuffer, zéro tearing (résout US3.2
  par construction). TMDS par OSER10 + TLVDS_OBUF, rPLL 27→135 MHz.
- Clavier série via le BL616 embarqué (USB-C), audio sigma-delta 1 bit.
- RAM Gowin dédiée : 64 Ko simple-port + miroir vidéo $9800-$BFFF
  (10 Ko) pour la ULA — 45/46 blocs BSRAM (la 1W2R naïve en exigeait 64).

### Corrigé
- Collision de nom avec la primitive Gowin `ALU` : ALU du 6502 renommée
  à la volée au build.
- RAM principale passée en lecture/écriture exclusives (NO_CHANGE) —
  régression ECP5 6/6 tests OK.

## [1.2.0] — 2026-07-29 — Sprint 3 : port d'extension, cassette, imprimante

### Ajouté
- **Port d'extension Oric complet sur GPIO** (`expansion_port.v`) : bus 6502,
  Φ2, /ROMDIS, /MAP, /IOCTRL, /IRQ, /RESET drain ouvert — sémantique fidèle
  (ROM / RAM cachée / cartouche), VIA restreinte à $0300-$030F. Cible :
  cartouche LOCI réelle. Brochage officiel (annexe 11 manuel Atmos) et table
  de câblage dans docs/PORT_EXTENSION.md. Testbench tb_expansion.
- **Signaux cassette** (PB7 sortie, PB6 moteur, CB1 entrée) et
  **imprimante Centronics** (PA données, PB4 strobe, CA1 ack) sur GPIO.
- Spécification de la carte « face arrière Atmos » au format carte mère
  d'origine (hardware/FACE_ARRIERE_ATMOS.md) : connecteurs d'époque + HDMI,
  berceaux 2× Pico W + carte FPGA, 2 USB-A, haut-parleur, phasage A/B.

### Déployé
- Bitstream v1.2.0 (inclut les correctifs HIRES/clignotement v1.1.1) gravé
  en flash SPI : démarrage autonome. 6/6 tests, timing 54,7 MHz (25 requis).

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
