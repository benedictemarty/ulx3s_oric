# Backlog agile — ulx3s_oric

## Sprint 1 (TERMINÉ 2026-07-29) — « Il boote »
Objectif : Oric Atmos fonctionnel sur ULX3S 85F — BASIC 1.1b au boot,
affichage HDMI, clavier USB, son AY.

- [x] US1.1 Squelette projet + docs + git
- [x] US1.2 RTL cœur : ULA, VIA 6522, mémoire, intégration 6502/jt49
- [x] US1.3 HDMI 640×480 + top-level ULX3S + USB HID + audio
- [x] US1.4 Testbenches : VIA, ULA, boot ROM (message BASIC en RAM écran)
- [x] US1.5 Synthèse 85F propre en timing + bitstream + flash carte

### Validation matérielle
- [x] Affichage HDMI réel (2026-07-29 — boot BASIC visible ; synchro
      fiabilisée par l'alignement de phase TMDS)
- [x] Clavier série UART depuis le PC (2026-07-29 — frappes visibles à
      l'écran via picocom)
- [x] Flash permanent en SPI v1.1.0 (2026-07-29, --unprotect-flash)
- [x] HIRES validé sur carte (2026-07-29, correctif v1.1.1 confirmé par bmarty)
- [x] Frappe clavier USB réelle (2026-08-02 — clavier physique confirmé
      fonctionnel par bmarty sur ULX3S)
- [x] Bascule disposition QWERTY/AZERTY sur BTN6 (2026-08-02 — décodage
      ASCII FR + table partagée, LED4 = AZERTY, testbench tb_azerty)
- [ ] Son AY sur la prise jack (ex. `PING`, `ZAP`, `MUSIC` en BASIC)

## Sprint 2 — « On charge des programmes »
- [x] US2.1 Chargement .tap (cassette) (2026-08-02) — injecteur cassette FPGA
      alimenté par UART avec contrôle de flux par crédits (voie retour
      ftdi_rxd) ; modulation fidèle à la référence, script tools/send_tap.py,
      testbench tb_tape. VALIDÉ SUR CARTE avec un vrai .tap (bmarty, 2026-08-02).
- [ ] US2.2 Bouton reset physique (BTN) + reset à chaud/froid
- [ ] US2.3 LED d'activité (IRQ, VSYNC, USB)

## Épopée MODEM WiFi — 6551 ACIA + ESP32 Hayes (plan : docs/MODEM_WIFI.md)
Objectif : modem WiFi Oric (telnet/BBS) via 6551 émulé (FPGA) + firmware
Hayes/WiFi sur l'ESP32 embarqué. Décisions (bmarty, 2026-08-02) : Hayes+TCP
dans l'ESP32 ; 6551 mappé `$031C-$031F` (standard Oric, fidèle à
`~/Oric1/src/io/acia6551.c`) ; pont UART FPGA↔ESP32 sur `wifi_rxd`/`wifi_txd`.
- [x] US-MODEM.1 **Phase 1 — Cœur 6551 FPGA** (2026-08-02) : `rtl/acia6551.v`
      (registres data/status/command/control, TDRE/RDRF/OVRN, IRQ, DCD/DSR),
      décodage `sel_acia` ($031C-$031F) dans oric_atmos + IRQ
      `via_irq|ext_irq|acia_irq`, pont UART ESP32 (uart_tx/uart_rx 115200) sur
      wifi_rxd (K3) / wifi_txd (K4), `wifi_en`, testbench `tb_acia`. RTL fait,
      testé (tb_acia), synthèse OK. Reste : brancher DCD réel en phase 2.
- [~] US-MODEM.2 **Phase 2 — Firmware ESP32** : SCAFFOLD + outillage faits
      (2026-08-02, `firmware/esp32_modem/`, `tools/esp32/`). ⚠️ **BLOCAGE
      MATÉRIEL** : l'ESP32 INTERNE de la carte v3.0.8 n'est PAS flashable par le
      FPGA (GPIO0 non tenable bas → jamais en mode download ; gestion ajoutée
      seulement en v3.1.7/R56). Épuisé : passthru officiel, esptool 5.3.1/4.5.1,
      no_reset, re-plug, bitstream `download_esp32.v`, BTN0 maintenu. → **NE PAS
      retenter l'interne.**
- [ ] US-MODEM.2b **Modem WiFi externe** (issue retenue) : repointer le pont
      UART du 6551 de `wifi_rxd/txd` vers 2 broches `gp[]` accessibles + doc
      câblage (TX/RX/GND). Cible décidée 2026-08-02 : **Pico W** (branché sur
      US2 pour l'ALIM 5 V ; données via UART GPIO sur le connecteur gp[], PAS
      via l'USB de US2 — un hôte USB-CDC FPGA serait trop lourd). Firmware :
      **arduino-pico** (réutilise le sketch modem, API WiFi ~ESP32 ; flash .uf2
      par BOOTSEL, trivial). Reste à faire : repointage RTL + portage sketch
      Pico W + brochage 3 fils.
- [ ] US-MODEM.3 **Phase 3 — Terminal Oric** : programme pilotant le 6551
      (poll RDRF, R/W $031C), v0 BASIC (PEEK/POKE pour AT/OK), v1 terminal ML
      (VT52/ANSI mini) vers un BBS. Réutiliser la logique de la référence.

## Épopée NETFS — Navigateur de fichiers WiFi (tap/dsk) (plan : docs/NETFS_WIFI.md)
Objectif : parcourir depuis l'Oric une arborescence de .tap/.dsk servie en
HTTP via WiFi, et charger le fichier choisi. Décisions (bmarty, 2026-08-02) :
.tap d'abord (.dsk après) ; OSD incrusté par le FPGA ; serveur HTTP + listing
JSON. Partage le lien ESP32↔FPGA de l'épopée MODEM.
- [ ] US-NETFS.1 **Protocole ESP32↔FPGA & client HTTP** : trames série
      (DIR/ENTRY/END côté ESP32 ; CD/UP/LOAD/REFRESH côté FPGA), multiplexées
      avec le modem sur l'UART ESP32. Firmware ESP32 : GET listing JSON d'un
      dossier → trames ENTRY ; sur LOAD, GET du fichier → stream cassette.
- [ ] US-NETFS.2 **OSD incrusté (FPGA)** : couche texte+curseur dans
      `hdmi_out.v` (police 8×8, fenêtre défilante), tampon des entrées de la
      page courante, navigation flèches `btn[3..6]` + FIRE, ouverture/fermeture
      OSD ; incrustation combinatoire (ne touche pas au timing vidéo).
      Testbench de rendu.
- [ ] US-NETFS.3 **Chargement .tap via WiFi (bout-en-bout)** : router le flux
      du fichier sélectionné ESP32 → `tape_injector` (réutilise le contrôle de
      flux crédits, source = UART ESP32). Validation sur carte.

## Épopée DISK — support .dsk (Microdisc) (ultérieure, cf. NETFS_WIFI.md)
- [ ] US-DISK.1 Émulation contrôleur **Microdisc / FDC WD1793** + ROM de boot,
      fidèle à `~/Oric1/src/io/microdisc.c` (registres, mapping I/O, /ROMDIS).
- [ ] US-DISK.2 Streaming/bufferisation des secteurs depuis l'ESP32/WiFi
      (à la demande ou par piste ; stockage SDRAM/BRAM), protocole secteur.
- [ ] US-DISK.3 Intégration OSD : sélectionner un .dsk « insère » la disquette.

## Épopée ULA-NG — extensions « voie Telestrat » : banques mémoire + vidéo étendue
> **Frontière avec `~/oric2`** (2026-08-10) : le projet Oric 2 « chimère »
> (65C816, OricOS multitâche, GPU blitter, golden model Phosphoric) est un
> **workspace séparé** (`~/oric2`). Ici, `ulx3s_oric` reste l'Atmos fidèle
> en 6502, étendu à la manière de l'époque (Telestrat/Sedoric) — pas de
> duplication de la chimère.
Objectif : étendre l'ULA FPGA vers la spec ULA-NG de la référence
(`~/Oric1/docs/ula-ng/ULA-NG-SPEC.md`) : commutation ROM/RAM pilotée par
l'ULA, banques ROM, puis modes vidéo NG (80 colonnes, chunky 4bpp).
Décisions (bmarty, 2026-08-10) : registre de banque logé dans la fenêtre
ULA-NG (`$03E0-$03EF`, toujours visible) ; l'ULA exporte le signal de
sélection vers le décodage existant de `oric_atmos.v` (sémantique
`sel_rom`/`rom_as_ram` conservée — changement minimal) ; comportement
HCS10017 strict par défaut (verrouillage NG), boot sur la banque BASIC.
Expérience utilisateur (bmarty, 2026-08-10) : boot 100 % classique ; la
commande **`HIRES 1`** (argument inexistant en BASIC standard) bascule en
mode OCULA/NG + BASIC étendu ; `HIRES` sans argument = HIRES classique
inchangé. Implique une ROM 1.1b patchée (handler HIRES seul modifié) en
banque de boot + banque(s) d'extension via NG_BANK (trampoline RAM basse).
Prototypage de la ROM patchée dans l'émulateur `~/Oric1` d'abord.
ROM patchée = usage personnel uniquement (cf. dette technique).
Cible mémoire : 48 Ko RAM fixe + fenêtre 16 Ko à `$C000` commutée
(jusqu'à 4-8 banques ROM + RAM haute = « 64 Ko ROM / 64 Ko RAM »).
L'émulateur `~/Oric1` sert de modèle de référence à chaque incrément.
- [~] US-ULA-NG.1 **Registre NG_BANK + commutation ROM/RAM** — première
      tranche FAITE (2026-08-11, validée sur carte) : `oric_rom.v` à
      2 banques (1.1b défaut + **BASIC 1.0**), bascule BTN5 + reset,
      Citadel (loader protégé, sensible à la révision ROM) chargé jusqu'au
      bout sur la banque 1.0. Reste : registre NG_BANK dans `$03E0-$03EF`
      (bit ROM/RAM + n° de banque, sélection via l'ULA), RAM haute,
      testbench POKE ; + nettoyage signature warm-boot à la bascule
      (bannière absente aujourd'hui : warm-boot silencieux).
- [ ] US-ULA-NG.2 **Palette + registres NG** : LUT palette redéfinissable,
      mécanisme de déverrouillage, fidèle à la spec et à l'émulateur.
- [ ] US-ULA-NG.3 **Texte 80 colonnes** (480 px, charset RAM natif,
      `NG_SCRSTART`, modes latchés en début de trame).
- [ ] US-ULA-NG.4 **Chunky 4bpp** 320×224, 16 couleurs (LUT NG).
- [ ] US-ULA-NG.5 **DOS en banque de boot + hooks façon Sedoric** (décision
      bmarty, 2026-08-10 — architecture actée, remplace l'« exploratoire ») :
      - Banque 0 (vecteur reset `$FFFC`) = **DOS** (cc65) : init, SD/FAT32
        (RTL existant), menu/chargement, installation des hooks, puis
        handover vers la banque BASIC (trampoline RAM basse + entrée à
        froid du BASIC). Modèle = ROM de boot Microdisc.
      - Banque 1 = BASIC 1.1b patché (`HIRES 1`, cf. US-ULA-NG.6) ;
        banques 2+ = extensions ; 5e position = RAM haute.
      - **DOS appelable depuis le BASIC** : hooks dans les vecteurs RAM
        page 2 + petit résident RAM basse ; commandes style Sedoric
        (`!DIR`, `!LOAD"X"`) → commutation NG_BANK aller-retour,
        échanges de données par la RAM basse (< `$C000`, seule zone
        visible des deux banques). Choisir l'emplacement du résident
        hors des zones système BASIC.
- [ ] US-ULA-NG.6 **BASIC étendu — bascule `HIRES 1`** : ROM 1.1b patchée
      (handler HIRES : argument optionnel ; sans argument = code d'origine),
      déverrouillage NG + commandes étendues en banque d'extension
      (trampoline RAM basse). Prototype dans l'émulateur `~/Oric1` d'abord.
- [ ] US-ULA-NG.7 **VRAM dédiée + modes « Hercules »** (décision bmarty,
      2026-08-10 : la vidéo étendue a sa VRAM à part) : framebuffer en BRAM
      séparé de la RAM 6502 (zéro contention CPU/vidéo), accès CPU par port
      indexé style VDP (registres adresse+données en `$03xx`). Modes visés :
      texte haute qualité (police 8×16 → 80×30, ou gros texte 14×18 → 45×26,
      à trancher) + hires 640×400 monochrome. Extension AU-DELÀ de la spec
      ULA-NG actuelle (480 px max, lecture RAM principale) → à spécifier
      d'abord dans `ULA-NG-SPEC.md` + émulateur, puis FPGA.
- [x] US-ULA-NG.8 **Mode turbo chargement** (2026-08-12, VALIDÉ SUR CARTE) :
      auto pendant `tape_active` — domaine cen1 (CPU+VIA+AY) 1→4,17 MHz +
      cassette au même ratio (~3× effectif avec les stops anti-IRQ),
      vidéo/ULA sur phase 1 MHz dédiée (écran vivant), retour 1 MHz à la
      fin (moteur coupé inclus). Cf. CHANGELOG (3 correctifs, enquête via
      tb_cload + désassemblage ROM). Resterait (plus tard) : registre
      NG_TURBO pour un turbo PERMANENT commandé par logiciel (jeu à
      8/16 MHz, VIA/AY à 1 MHz — découplage à concevoir).

## Épopée SPEECH — synthèse vocale TMS5220 (le chip voix de l'EXL 100)
Objectif : intégrer un TMS5220 (synthèse LPC Texas Instruments) en RTL dans
le cœur Oric. Décisions (bmarty, 2026-08-10) : réécriture Verilog-2005
fidèle à la référence MAME `tms5220.cpp` (pas de vrai chip 5 V sur le port
d'extension) ; mode **Speak External** uniquement (le CPU streame les
données LPC dans la FIFO — pas de ROM VSM propriétaire) ; pilotage par
2 adresses dans la page `$03xx` (fenêtre libre à choisir entre les zones
réservées Microdisc/LOCI/ACIA/ULA-NG) ; sortie mixée avec l'AY dans le
chemin audio existant (jack + HDMI). Aucun logiciel Oric d'époque ne le
supporte : c'est notre soft (BASIC POKE, puis ROM système US-ULA-NG.5)
qui l'exploitera.
- [ ] US-SPEECH.1 **Cœur LPC TMS5220** : filtre en treillis 10 coefficients,
      excitation chirp/bruit, interpolation de trames, FIFO Speak External,
      status /READY. Testbench de non-régression contre la référence MAME
      (mêmes trames LPC → mêmes échantillons).
- [ ] US-SPEECH.2 **Intégration Oric** : décodage 2 registres page `$03xx`
      dans `oric_atmos.v` (data/status + handshake), mixage avec l'AY vers
      jack + HDMI, synthèse 85F en timing.
- [ ] US-SPEECH.3 **Outillage + démo** : encodeur PC WAV → flux LPC
      (python_wizard ou équivalent), envoi depuis l'Oric (BASIC POKE ou
      loader), démo « l'Oric parle » validée sur carte.

## Sprint 3 — « Confort »
- [ ] US3.1 OSD de sélection de fichiers .tap → couvert par US-NETFS.2 (OSD
      incrusté FPGA) ; la source de fichiers devient le serveur WiFi.
- [ ] US3.2 Mode 60 Hz optionnel / meilleure synchro vidéo (triple buffer)
- [ ] US3.3 Joystick USB → interface joystick Oric
- [ ] US3.4 Shift register VIA complet + entrée cassette réelle (jack)

## Sprint 4+ — « Atmos moderne » (carte format Atmos)
- [x] US4.1 Conception bandeau LOCI terminée (144/144, DRC 0) — NON commandée : blocs intégrés à la carte unique (décision carte unique 2026-07-29)
- [ ] US4.2 Carte UNIQUE « Atmos moderne » : Tang Nano + 2 Pico W + TXS + tous connecteurs — hérite des blocs du bandeau
- [ ] US4.3 **PRIORITAIRE — Portage du core sur Tang Nano 20K** (Gowin
      GW2AR-18, yosys synth_gowin + apicula ; PLL/TMDS/USB à adapter).
      Prérequis d'usage du bandeau phase A : c'est le Tang Nano qui le
      pilote (décision 2026-07-29). L'ULX3S reste banc de dev ECP5.
- [ ] US4.4 Carte format Atmos (phase B) : mesures boîtier, routage,
      berceaux Pico W ×2 + Tang Nano, micro-SD externe (découpe TV),
      HP + PAM8302, imprimante via Pico
- [ ] US4.5 Firmware LOCI natif sur Pico #1 (build loci-firmware, SD)

## Dette technique / risques identifiés
- Battement 50/60 Hz → tearing occasionnel (accepté v1, cf. US3.2).
- usb_hid_host ne gère que les claviers *boot protocol* low-speed ; certains
  claviers USB ne répondent pas (prévoir un clavier simple).
- ROM : droits d'auteur — usage personnel uniquement, pas de redistribution.

## Sprint 5 — « Boîtier maîtrisé »
- [ ] US5.1 Boîtier paramétrique OpenSCAD silhouette Atmos : profil extrait
      des STL OriClone (hardware/boitier/profil_coupe.json), paramètres :
      profondeur 175 (fidèle/clavier d'origine) ou 205 (clavier MX),
      découpes arrière générées depuis les coordonnées du PCB phase B,
      tuilage imprimable 220×220 (queues d'aronde + bossages à vis)
- [ ] US5.2 Chaînage/nettoyage du profil brut en polygone propre
- [ ] US5.3 Rendu STL + impression test d'un tronçon
