# CHANGELOG — ulx3s_oric

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]

### Documenté
- **Épopée US-SPEECH** au backlog : synthèse vocale **TMS5220** (le chip
  voix TI de l'Exelvision EXL 100) en RTL, réécrit d'après la référence
  MAME `tms5220.cpp` avec testbench de non-régression. Mode Speak External
  (données LPC streamées par le CPU, pas de ROM VSM), 2 registres page
  `$03xx`, sortie mixée avec l'AY (jack + HDMI). Outillage PC WAV→LPC et
  démo à venir ; exploité par notre propre soft (BASIC, puis ROM système).
- **Épopée US-ULA-NG « Oric 2 »** au backlog : banques mémoire pilotées par
  l'ULA (registre NG_BANK dans `$03E0-$03EF`, fenêtre 16 Ko à `$C000`
  commutée ROM/RAM, jusqu'à 64 Ko de ROM + 64 Ko de RAM) puis modes vidéo
  étendus de la spec ULA-NG de la référence `~/Oric1` (palette, texte
  80 colonnes, chunky 4bpp), et à terme une ROM système façon Orix (cc65).
  Compatibilité par défaut : comportement HCS10017 strict tant que le mode
  NG n'est pas déverrouillé, boot sur la banque BASIC.
- **Plan « Navigateur de fichiers WiFi »** (`docs/NETFS_WIFI.md`) + épopées
  US-NETFS et US-DISK au backlog : parcourir une arborescence de `.tap`/`.dsk`
  servie en HTTP (listing JSON) via WiFi, OSD incrusté par le FPGA, chargement
  `.tap` réutilisant l'injecteur cassette. `.dsk` (Microdisc WD1793) = épopée
  ultérieure. Partage le lien ESP32↔FPGA du plan modem.
- **Plan « Modem WiFi Oric »** (`docs/MODEM_WIFI.md`) + épopée US-MODEM au
  backlog : 6551 ACIA émulé (FPGA, `$031C-$031F`, fidèle à `acia6551.c`) relié
  au firmware Hayes/WiFi de l'ESP32 embarqué. 3 phases — cœur 6551 FPGA (RTL),
  firmware ESP32 (Zimodem, bmarty flashe), terminal Oric.

### Ajouté
- **Lecteur carte micro-SD (SPI) — épopée US-SDCARD (en cours)** : première
  étape vers le chargement de programmes depuis une carte SD (le lecteur SD de
  l'ULX3S, jusqu'ici inutilisé), alternative simple à l'USB Mass Storage —
  clavier branché en direct + stockage sur bus séparé.
  - **Incrément 1 — pilote SD**, **validé sur carte** :
    - `rtl/spi_byte.v` : moteur SPI mode 0 (octet full-duplex). Testbench
      `tb_spi_byte` (loopback).
    - `rtl/sd_spi.v` : FSM d'init (CMD0/CMD8/ACMD41/CMD58, détection SDHC via
      CCS) + lecture de secteur (CMD17). Octet `status` pour diagnostic LED.
    - `sim/sd_card_model.v` + `sim/tb_sd_spi.v` (`make test-sd`) : init complète
      + lecture secteur 0, motif + signature 0x55AA vérifiés en simulation.
    - Intégration `top_ulx3s` : broches `sd_clk`/`sd_cmd`/`sd_d` (SPI : mosi=cmd,
      miso=d0, cs=d3), test au boot lisant le secteur 0 → LEDs (`0xAA` = carte
      OK + signature valide). **Confirmé sur carte réelle par bmarty.**
  - **Incrément 2 — parseur FAT32**, **validé sur carte** :
    - `rtl/fat32.v` : lecture seule ; détecte table MBR *ou* superfloppy, lit le
      BPB, calcule les LBA, parcourt le répertoire racine, liste les `.TAP`/
      `.DSK` (ignore LFN/volume/dir + autres extensions). Listing exposé par
      port indexé (nom 8.3, cluster, taille, dsk?).
    - `sim/sd_card_file.v` (carte servie depuis une image) +
      `tools/gen_fat_test.py` (image FAT32 avec MBR) + `sim/tb_fat32.v`
      (`make test-fat`) : listing vérifié en simulation.
    - `top_ulx3s` : LEDs = nombre de `.tap`/`.dsk` trouvés. **Confirmé sur la
      carte réelle par bmarty** (les fichiers de la carte sont bien listés).
  - Suite : OSD à l'écran + navigation, chargement `.tap` via `tape_injector` ;
    `.dsk` = épopée US-DISK (émulation Microdisc).
- **Son sur HDMI — épopée US-HDMI-AUDIO (en cours)** : le son de l'Oric
  (AY-3-8912) ne sortait que sur le jack DAC 3,5 mm car la sortie GPDI est du
  **DVI pur** (vidéo seule). Objectif : transporter l'audio dans les *data
  islands* HDMI, en réécrivant en Verilog-2005 la logique standard (le module
  de référence `hdl-util/hdmi` est en SystemVerilog, incompatible en direct
  avec le flow yosys/iverilog du projet). Jack conservé en parallèle (aucune
  interaction avec l'entrée cassette, câblée sur `gp[14]`).
  - **Incrément 1 — encodeur TMDS 3-modes** (`rtl/hdmi_tmds_channel.v`) :
    control / video (8b/10b) / **data island TERC4** / guard bands vidéo et
    data-island, par canal (CN=0/1/2). Testbench `sim/tb_hdmi_tmds.v`
    (cible `make test-hdmi`) : **non-régression** stricte contre l'ancien
    `tmds_encoder.v` sur 512 cycles + vérification littérale des 16 codes
    TERC4, des guard bands et des codes de contrôle.
  - **Incrément 2 — packets audio** :
    - `rtl/hdmi_packet_assembler.v` : assemble un data island packet (header
      24 bits + 8 ECC, 4 subpackets 56 bits + 8 ECC) et le sérialise sur les
      32 pixels. ECC BCH par LFSR (polynôme 0x83). Testbench
      `sim/tb_hdmi_packet.v` (`make test-hdmi-packet`) : framing exact +
      **syndrome BCH nul** sur les mots reconstitués.
    - `rtl/hdmi_audio_packets.v` : contenu des packets Audio Clock
      Regeneration (N/CTS, N=4096 pour 32 kHz), Audio InfoFrame (LPCM 2 canaux,
      checksum), Audio Sample Packet (échantillon IEC60958 stéréo, preamble
      P/C/U/V, parité). Testbench `sim/tb_hdmi_audio.v`
      (`make test-hdmi-audio`) : headers, slices N/CTS, checksum nul, parité
      recalculée (1 et 2 échantillons).
  - **Incrément 3 — ordonnanceur + cadence audio** (`rtl/hdmi_data_island.v`) :
    place un data island par ligne dans le blanking (preamble + guard bands +
    island), plus video preamble/guard avant la reprise vidéo ; ordonnance
    InfoFrame (ligne 0), ACR (ligne 1) et Audio Sample Packets (autres lignes).
    Cadence audio 32 kHz exacte par accumulateur rationnel (pixel clock 25 MHz),
    jusqu'à 4 échantillons/packet (cadence ligne 31,25 kHz < 32 kHz). Testbench
    `sim/tb_hdmi_island.v` (`make test-hdmi-island`) : séquence complète des
    modes vérifiée pixel par pixel.
  - **Intégration** : `rtl/hdmi_out.v` passe de DVI pur à HDMI (3 canaux
    `hdmi_tmds_channel` + data islands) ; image inchangée sur écran DVI.
    `rtl/top_ulx3s.v` : audio PSG converti en PCM 16 bits signé, traversée de
    domaine clk_sys→clk_pixel, **jack 3.5 mm conservé** en parallèle.
  - **AVI InfoFrame** (`hdmi_audio_packets` type 0x82, ligne 2) : décrit la
    vidéo à l'écran passé en mode HDMI. **VIC=0** (format non-CEA) : sans lui
    (VIC=1) l'écran imposait le timing 25,175 MHz de la norme 640×480 et coupait
    l'image après ~30 s (on génère 25,000 MHz). **PB1 underscan (S=10)** :
    supprime le traitement d'image (halo/fantômes autour des glyphes) sans
    couper le son. NB : le bit `IT_CONTENT` (mode « PC ») supprime aussi le halo
    mais **coupe les haut-parleurs** de certaines TV — non retenu.
  - **Validé sur carte (ULX3S)** : image nette + audio HDMI dans le signal +
    stable, jack conservé. Cadence audio et compatibilité écran confirmées par
    bmarty. Flash en FLASH (`make oric-flash`) recommandé (le load SRAM peut
    être perdu au reboot).
- **Outillage ESP32 embarqué** (`tools/esp32/` + cibles Makefile
  `esp32-setup`/`esp32-build`/`esp32-flash`) : compile et flashe l'ESP32 de
  l'ULX3S *à travers* le FPGA via le **bitstream passthru officiel 85F**
  (`emard/ulx3s-bin`) + `arduino-cli`/esptool. `setup.sh` (arduino-cli local,
  core esp32, passthru), `build.sh`, `flash.sh` (passthru → upload → recharge
  l'Oric). README avec méthode, config WiFi, dépannage (TMS/GND, gpio5).
- **Scaffold firmware ESP32 « modem Hayes WiFi » — US-MODEM phase 2**
  (`firmware/esp32_modem/`) : sketch Arduino (WiFi STA, parseur AT —
  `ATDT host:port`, `ATH`, `+++`, `ATO`, `ATE`, `ATI`, config SSID/pass en
  NVS via `AT$SSID/$PASS/$C/$W`), pont transparent série↔TCP/telnet (filtrage
  IAC minimal), porteuse en bande (`CONNECT`/`NO CARRIER`). README : câblage
  K3/K4, compilation `arduino-cli`, procédure de flash ULX3S, points ouverts
  (mappage UART ESP32, flash, DCD matériel). À compiler/flasher par bmarty
  (non testé dans le dépôt).
- **6551 ACIA + pont ESP32 — US-MODEM phase 1** : cœur `rtl/acia6551.v`
  émulé et mappé `$031C-$031F` (fidèle à `~/Oric1/src/io/acia6551.c` :
  registres data/status/command/control, `TDRE`/`RDRF`/`OVRN`, IRQ armé/
  acquitté par lecture STATUS, bits DCD/DSR). Décodé dans `oric_atmos`
  (`sel_acia`, carve hors du bus d'extension, IRQ `via_irq|ext_irq|acia_irq`).
  Pont UART 115200 vers l'ESP32 embarqué : 6551 TX → `wifi_rxd` (K3), `wifi_txd`
  (K4) → 6551 RX (nouveaux `uart_tx`/`uart_rx`), `wifi_en` actif. Testbench
  `tb_acia` (registres, TX/RX, overrun, IRQ). Le firmware Hayes/WiFi de l'ESP32
  = phase 2 (bmarty). DCD/DSR câblés à 0 en attendant.
- **Chargement de programmes `.tap` (cassette) — US2.1** : injecteur cassette
  dans le FPGA (`rtl/tape_injector.v`) qui reçoit un `.tap` par UART et génère
  la forme d'onde cassette Oric exacte sur `tape_in` (→ VIA CB1 → `CLOAD`).
  Modulation conforme à la référence `~/Oric1/src/io/cassette.c` : trame 14
  bits (start, 8 data, parité impaire, 4 stop), amorce 64×`0x16`, bit `1`
  416 µs / bit `0` 624 µs, joué quand le moteur (PB6) tourne. **Contrôle de
  flux par crédits** sur la voie retour `ftdi_rxd` (nouvel `rtl/uart_tx.v`) :
  1 octet crédit `0x5A` par octet absorbable → aucune perte quelle que soit la
  taille (jeux 48 Ko inclus). Aiguillage UART clavier/cassette (`tape_active`),
  LED5 = chargement. Script PC `tools/send_tap.py`, doc `docs/CASSETTE.md`,
  testbench `tb_tape` (redécodage de la forme d'onde, framing, crédits).

### Corrigé
- **Touche `*` AZERTY sans effet** : le scancode réel de la touche `*µ`
  variait (`0x31` mappé, mais certains claviers émettent `0x32`). Ajout de
  `0x32` (variante ISO) et `0x55` (pavé numérique) → `*` = Shift+8 Oric.
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
