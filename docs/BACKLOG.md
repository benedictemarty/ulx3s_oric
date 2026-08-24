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
- [x] Son AY sur la prise jack (2026-08-20) : déjà routé (DAC R-2R 4 bits),
      **amélioré** par un noise-shaper sigma-delta `rtl/audio_dac_sd.v`
      (suréchantillonné 25 MHz → résolution effective ~10 bits). `test-audio-dac`.
      Reste validation carte (écoute PING/ZAP/MUSIC au casque).

## Sprint 2 — « On charge des programmes »
- [x] US2.1 Chargement .tap (cassette) (2026-08-02) — injecteur cassette FPGA
      alimenté par UART avec contrôle de flux par crédits (voie retour
      ftdi_rxd) ; modulation fidèle à la référence, script tools/send_tap.py,
      testbench tb_tape. VALIDÉ SUR CARTE avec un vrai .tap (bmarty, 2026-08-02).
- [x] US2.2 Bouton reset physique (BTN1) + reset à chaud/froid (2026-08-16 :
      BTN1 reset ; BTN5 bascule ROM+reset ; SW1 bascule Microdisc+reset AUTO
      anti-rebondi ; insertion .dsk = reset auto. tb_sw1reset garde-fou.)
- [x] US2.3 LED d'activité (IRQ, VSYNC, USB) (2026-08-23, sim + synthèse OK,
      **carte à valider**) : `rtl/led_activity.v` monostable re-déclenchable
      (heartbeat IRQ/VSYNC, flash USB) ; overlay opt-in **SW4** (`sw[3]`) →
      `led[7:5]={IRQ,VSYNC,USB}`, vue diagnostic SD/FAT inchangée sinon.
      tb_led_activity (cible `test-led`).

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
      (2026-08-02, `firmware/esp32_modem/`, `tools/esp32/`). ⚠️ Flash esptool
      de l'ESP32 interne IMPOSSIBLE (v3.0.8, GPIO0 non tenable — épuisé le
      2026-08-02, ne pas retenter). **DÉBLOQUÉ le 2026-08-13 par une autre
      voie : le firmware d'usine MicroPython 1.14 est vivant** (REPL UART
      115200 via le passthru, `network.WLAN` OK, flash 4 Mo, boot.py stub).
      **FAIT le 2026-08-13** : `firmware/esp32_modem/main.py` (MicroPython,
      commandes compatibles ~/picowifi PicoWiFiModemUSB) installé par
      raw-REPL (`tools/esp32/install_main.py`) et persistant. AT/ATI/AT?
      validés via passthru. Reste : ATC1 sur le vrai WiFi, ATDT vers un
      BBS, et le terminal Oric (US-MODEM.3). Pico W (2b) = plan B.
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

## Épopée DISK — support .dsk (Microdisc) — EN COURS (démarrée 2026-08-12)
Objectif : émuler l'interface Microdisc (FDC WD1793 + EPROM microdis) pour
booter Sedoric et charger la logithèque disquette (dont `Citadelle.dsk`).
Références : `~/Oric1/src/io/microdisc.c` (wrapper : `$0310-$0313` = WD1793,
`$0314` W = contrôle INTENA/ROMDIS/side/drive/EPROM, `$0314`/`$0318` R =
/INTRQ//DRQ bit 7, actifs bas) et `~/Oric1/src/storage/disk.c` (WD1793
complet : types I-IV, timings réels, format MFM_DISK). ROM `microdis.rom`
(8 Ko) dispo dans `~/Oric1/roms`. **Révision 2026-08-12 : la source des
.dsk est la CARTE SD** (le plan WiFi de 2026-08-02 prédate l'épopée
US-SDCARD ; `fat32` liste déjà les `.dsk`). Pas de conflit ACIA : le
Microdisc s'arrête à `$0318`, l'ACIA est à `$031C-$031F` (comme la réf).
Architecture retenue : **buffer de PISTE en BRAM** (~6,4 Ko, piste MFM
brute du format MFM_DISK) rechargé depuis la SD à chaque seek (~200 ms,
comparable à une vraie mécanique 3") ; v1 en LECTURE SEULE.
- [x] US-DISK.1 **Cœur WD1793 RTL** (2026-08-12, validé en sim) fidèle à `disk.c` : registres
      cmd/track/sector/data, commandes type I (seek/step, h/V/r1r0),
      type II (read sector : recherche d'ID dans la piste MFM, DRQ par
      octet), type III (read address), type IV (force interrupt), status
      par type, timings réels (step 6-30 ms, latence rotation, RNF après
      5 tours d'index). Testbench : piste MFM synthétique en BRAM,
      séquences lecture/seek vérifiées contre le comportement de la réf.
- [x] US-DISK.2 **Wrapper Microdisc + intégration** (2026-08-12, VALIDÉ SUR
      CARTE) : registres `$0310-$0318` actifs-bas, EPROM 8 Ko overlay
      `$E000-$FFFF`, /ROMDIS combiné, IRQ si INTENA, **SW1 (DIP) =
      interface branchée** (OFF = Atmos intact). Sur carte : SW1 ON →
      « insert system disc », SW1 OFF → Atmos normal.
- [x] US-DISK.3 **Pistes depuis la SD** (2026-08-12, validé en sim :
      22 pistes réelles Citadelle au byte près) : accès aléatoire dans le
      fichier .dsk (fat32 : seek par re-suivi de chaîne de clusters +
      offset piste = f(side, track) de l'en-tête MFM_DISK), chargement du
      buffer de piste, poignée « disquette insérée » pour le WD1793.
- [x] US-DISK.4 **OSD : insérer un .dsk** (2026-08-13, VALIDÉ SUR CARTE :
      menu Sedoric au boot) : BTN4 sur un `.dsk` = insertion + reset auto
      (attente `dsk_inserted` puis ~5 ms) → boot EPROM → Sedoric. Gel du
      boot résolu (init RAM motif Oricutron + course seek/rechargement,
      cf. CHANGELOG). OSD ouvert/fermé : BTN4 ferme, appui suivant rouvre
      (fini les chargements cassette accidentels pendant un boot disque).
      `Citadelle.dsk` validé sur carte (choix du menu OK — l'« erreur de
      syntaxe » venait de la course de piste). Reste ouvert : lenteur des
      chargements de piste (cf. US-SD-SPEED).
- [x] US-SD-SPEED **SPI SD haute vitesse + seek FAT32 incrémental**
      (2026-08-13, VALIDÉ SUR CARTE — « ok cela fonctionne », gravé SPI) :
      SPI à 6,25 MHz après init (×16) et seek avant en O(1) depuis le
      cluster courant (`cur_base` dans fat32). Le boot Sedoric re-suivait
      la chaîne depuis le début du fichier à chaque piste (piste 60 ≈ 90
      sauts FAT à 390 kHz). Boot Sedoric rapide, Citadelle OK, cassette
      et Atmos pur sans régression.
- [x] US-DISK.5 **Écriture disquette** (TERMINÉ 2026-08-17, 4 phases sim OK) :
      - [x] Phase 1 : sd_spi écrit un bloc (CMD24) — test-sd-write, suite OK
      - [x] Phase 2 : fat32 écrit un bloc à un offset quelconque (suivi de
            chaîne FAT + LBA) — test-fat-write (offset 8192, 3e cluster), OK
      - [x] Phase 3 : dsk_track write-back (2026-08-17, sim OK) — `sec_we` écrit
            le secteur dans tbuf ; `wr_commit` déclenche le **RMW** des 1-2 blocs
            SD touchés (lecture bloc -> overlay des octets du secteur depuis tbuf
            -> réécriture via `fat32.wblk`). Overlay déterministe par `ocnt0`
            (octets dans le 1er bloc) ; `wblk_data` combinatoire (latence 1-cycle
            fatale au streaming, cf. `tb_fat_write`). **`test-dsk-write`** :
            écrit un secteur, recharge depuis la SD, vérifie la nouvelle donnée
            + secteur voisin intact ; **`test-dsk` (lecture) sans régression**.
      - [x] Phase 4 : WD1793 commande write sector (2026-08-17, e2e OK) —
            commande `0xA0`, DRQ pour recevoir 256 octets → `sec_we` vers tbuf
            (position via DRQ pour éviter la course avec le pulse), `wr_commit`
            en fin → attente `wr_ok`/`wr_err` (niveaux, échantillonnables à cen).
            Câblage top complet : WD1793 → microdisc → oric_atmos → dsk_track →
            fat32.wblk (tie-offs supprimés). Write-protect retiré. **`test-wd`
            (écriture 256 o) et `test-dsk-wr-e2e` (Write Sector → SD → relecture,
            secteur voisin intact) PASSED ; test-boot/dsk/microdisc/dsk-write
            sans régression.**
- [x] US-DISK.6 **Formatage — commande Write Track WD1793** (2026-08-17, sim OK) :
      `rtl/wd1793.v` — commande `0xF0` : parseur du flux IBM/MFM (réf. `~/Oric1`
      `disk.c`) — marque `FE` → champ ID 4 octets (secteur), `FB/F8` → champ data
      256 o poussé dans `tbuf` (`sec_we`, secteur = ID courant) ; gaps/CRC (`F5/
      F6/F7/4E`) ignorés ; write-back **par secteur** (réutilise la chaîne phase
      3/4), fin quand les `n_spt` secteurs sont écrits. Même anti-course
      `cur_offset` (incrément à l'échéance DRQ). **`test-wd`** (flux 17 secteurs →
      capture par secteur vérifiée) PASSED ; e2e/boot/microdisc sans régression.
      Permet un `INIT`/formatage Sedoric sur une piste déjà cataloguée (réécrit
      la donnée). Read Track reste non implémenté (peu utile).

## Épopée CSAVE — sauvegarde cassette — EN COURS (démarrée 2026-08-20)
Objectif : capturer la forme d'onde `CSAVE` que la ROM bit-bange sur PB7 et la
reconstruire en `.tap`. Miroir de l'épopée LOAD (`tape_injector`). Destination :
**les deux, en incrémental** — UART vers le PC d'abord (validation rapide),
carte SD ensuite. Décodeur de référence : `~/Oric1/src/io/cassette.c`
(`tape_capture_*`, mode `--tape-out-capture`).
- [x] US-CSAVE.1 **Démodulateur RTL** (2026-08-20, sim OK) : `rtl/tape_demod.v`
      — fronts montants PB7 → période front-à-front → seuil 512 µs (`CYC_THRESH`)
      → bit ; réassembleur d'octet par chasse au start (comme `GetTapeByte`,
      brûle la parité, ignore le nombre de stops) ; `byte_out`/`byte_valid` +
      `capturing` (fin sur `GAP_CYCLES` de silence). `sim/tb_tape_demod.v` (cible
      `test-tape-demod`) : boucle `tape_injector`→`tape_demod`, octets décodés ==
      amorce + données (flux simple + multi-blocs). **PASSED, suite sans
      régression.**
- [x] US-CSAVE.2 **Sortie UART vers le PC** (2026-08-20, synthèse OK, **carte à
      valider**) : `tape_demod` branché sur `tape_out` dans `top_ulx3s`, octets
      injectés dans le mux UART (priorité dump > SAVE > écran > crédits),
      `sav_capturing` coupe l'écran. `tools/recv_tap.py` : resync `0x16…0x24`,
      parse les blocs, écrit le `.tap`. Synthèse 85F propre (pas de double-driver),
      parseur validé sur flux synthétique. Reste : `CSAVE"NOM"` réel sur carte
      → `.tap` relisible par `send_tap.py`/un émulateur.
- [~] US-CSAVE.3 **Sortie carte SD** (stratégie **placeholder** retenue :
      écrase un `SAVE.TAP` pré-créé, pas de création FAT32) :
      - [x] **Phase A** (2026-08-20, sim e2e OK) : `rtl/tape_saver.v` — octets
            démod → double buffer ping-pong → `fat32.wblk` dans `SAVE.TAP` ;
            dernier bloc padé `0x00`, `nbytes` = taille réelle.
            `tools/gen_fat_test.py` : placeholder `SAVE.TAP` (4096 o, 0xEE).
            `sim/tb_tape_saver.v` (`test-tape-saver`) : chaîne complète
            injector→demod→saver→fat32→SD, 600 o (2 blocs, ping-pong), relecture
            vérifiée. `file_count` des tests fat32/dsk 7→8. Suite 29/29.
      - [x] **Phase B** (2026-08-20, synthèse OK, **carte à valider**) :
            intégration top — `fat32` 4ᵉ port de nom (`q4`), locator FSM qui
            verrouille l'index de `SAVE.TAP`, instance `tape_saver`, mux
            `fat32.wblk` disque↔saver (`sav_busy`). Save inhibée si `SAVE.TAP`
            absent (`sav_found`). Synthèse 85F propre, suite sans régression.
            Reste : `CSAVE"NOM"` réel sur carte → `SAVE.TAP` mis à jour.
      - [x] **Refinement** (2026-08-20, sim e2e + synthèse OK) : primitive
            `dsize_*` de fat32 (RMW du secteur de répertoire, octets 28-31),
            localisation de l'entrée mémorisée au parsing, déclenchée par le top
            à la fin de la save (`sav_done` → `sav_nbytes`). Post-check
            `tools/check_save_tap.py` sur l'image. `SAVE.TAP` porte sa taille
            réelle. **US-CSAVE.3 complète** (reste validation carte).
- [~] US-CSAVE.4 **Vraie création FAT32** (EN COURS, démarrée 2026-08-24) :
      lever le *placeholder* `SAVE.TAP` — créer un vrai fichier `.tap` sur la SD
      (allocation de cluster + entrée de répertoire) au lieu d'écraser un fichier
      pré-existant. Stratégie retenue : **allocation incrémentale** (clusters
      alloués à la demande pendant l'écriture, pas de pré-allocation ni de
      troncature).
      - [x] **Phase 1 — Allocateur de cluster** (2026-08-24, sim + check OK) :
            `fat32.v` gagne `alloc_start/alloc_prev → alloc_clus/alloc_done/
            alloc_error`. Scanne la FAT depuis le cluster 2 (multi-secteur),
            trouve la 1re entrée libre, la marque **EOC** (RMW du secteur FAT
            via `secbuf`) ; si `alloc_prev≠0`, chaîne aussi `prev → nouveau`
            (extension). `sim/tb_fat_alloc.v` (cible `test-fat-alloc`) : 3 allocs
            chaînées, la persistance de l'EOC est prouvée (alloc #2 rend c1+1) ;
            `tools/check_fat_alloc.py` valide la chaîne FAT sur l'image. Trous FAT
            de l'image de test bouchés (`gen_fat_test.py`) → 1er libre > 128,
            scan multi-secteur exercé. Top : allocateur tie-off (pas encore
            piloté).
      - [x] **Phase 2 — Création d'entrée de répertoire** (2026-08-24, sim OK) :
            `fat32.v` gagne `mkent_start/mkent_name/mkent_clus/mkent_size →
            mkent_idx/mkent_done/mkent_error`. Scanne le répertoire racine
            (`DIRSECS` secteurs), trouve un slot libre (1er octet `0x00`/`0xE5`),
            écrit l'entrée 8.3 (nom, attr 0x20, cluster hi/lo, taille) par RMW du
            secteur, puis ajoute le fichier au listing en mémoire (visible sans
            re-parse). `sim/tb_fat_mkent.v` (cible `test-fat-mkent`) : alloc +
            création de `NEWSAVE.TAP`, contrôle du listing mémoire, puis
            **re-parse** de l'image → le fichier réapparaît (nom/cluster/taille),
            persistance prouvée.
      - [x] **Phase 3 — Extension de chaîne** (2026-08-24, sim OK) : nouvel input
            `wblk_extend` — quand l'écriture (`wblk`) atteint la fin de chaîne
            (EOC), si `wblk_extend=1` l'allocateur est invoqué en sous-routine
            (`wb_extending`) pour allouer et chaîner un cluster puis poursuivre ;
            si `wblk_extend=0`, comportement inchangé (`wblk_error`, fichiers
            disque pré-alloués). `sim/tb_fat_extend.v` (cible `test-fat-extend`) :
            crée un fichier neuf (alloc + entrée), écrit 3 blocs (SPC=1 → 2
            extensions), relit les 1536 o par le chemin de lecture (suivi de la
            chaîne construite) — contenu conforme.
      - [~] **Phase 4 — Intégration top** : orchestration `mkfile` (alloc +
            dirent) branchée au `tape_saver`, nom de fichier généré.
            **Décision nommage : nom réel du `CSAVE"NOM"`** (extrait de l'en-tête
            cassette).
            - [x] **D1 — Extracteur de nom** (2026-08-24, sim OK) : `rtl/tape_name.v`
                  observe le flux `tape_demod` (amorce 0x16 → 0x24 → 9 o d'en-tête
                  → nom ASCII + 0x00) et reconstruit un nom 8.3 (troncature 8,
                  majuscules, `[A-Z0-9]` sinon `_`, extension `TAP`, défaut
                  `NONAME`). `sim/tb_tape_name.v` (cible `test-tape-name`) : nom
                  normal, minuscules/invalides, troncature, nom vide.
            - [x] **D2 — Orchestration** (2026-08-24, sim e2e + synthèse OK) :
                  `rtl/tape_creator.v` (intègre `tape_name`) séquence
                  extraction du nom → `alloc` → `mkent` (nom réel, taille 0) →
                  `file_ready`/`file_idx` → écriture `tape_saver` (avec
                  `wblk_extend`) → `dsize` (taille réelle) à la fin. `tape_saver`
                  gagne `file_ready` (le 1er bloc attend la création ; il
                  bufferise pendant l'amorce). `top_ulx3s` remplace le locator
                  `SAVE.TAP` + le bloc `dsize` par `tape_creator` ; `alloc`/
                  `mkent`/`dsize` de fat32 pilotés par lui, `wblk_extend=sav_busy`.
                  `sim/tb_tape_create.v` (cible `test-tape-create`) : chaîne e2e
                  complète (injector→demod→creator+saver→fat32→SD), flux avec
                  en-tête + nom « TESTPROG », capture du flux décodé réel, puis
                  re-parse → fichier `TESTPROGTAP` créé, taille inscrite, contenu
                  relu identique. **Plus de placeholder SAVE.TAP.** Reste :
                  validation carte.
      - [ ] **Phase 5 — e2e** : injector→demod→saver→(création+écriture)→SD,
            relecture du `.tap` créé + vérif entrée + chaîne FAT.

## Épopée LOCI — émulation interne (plan : docs/LOCI_EMULATION.md)
> ⏸ **PARQUÉE (2026-08-17)** — décision « retour à l'Atmos pur » (on arrête
> d'élargir). Exploration conservée pour mémoire, non reprise pour l'instant.
Objectif : décider ce qui, de la carte LOCI (`sodiumlb/loci-hardware` 1.3,
firmware `loci-fw`), est émulable dans l'ECP5. **Constat de conception
(2026-08-17)** : la LOCI est un **RP2040 + firmware** ; son cœur (MIA `$03A0`,
API POSIX, ROM swap) est **logiciel**, non émulable en RTL pur, et **redondant**
avec la chaîne disque native déjà validée (épopée DISK). Seule brique retenue :
l'**ACIA 6551 à `$0380`** (canal modem LOCI), distincte du 6551 existant à
`$031C`. Le pont vers une **vraie** LOCI est un sujet séparé (`expansion_port.v`,
`docs/NOTE_EQUIPE_LIAISON_LOCI.md`).
- [x] US-LOCI.0 **Conception + périmètre** (2026-08-17) : `docs/LOCI_EMULATION.md`
      — cartographie LOCI, ce qui est/n'est pas émulable, recouvrement avec
      l'épopée DISK, brique ACIA `$0380` retenue, soft-CPU écarté.
- [ ] US-LOCI.1 **Décision** : (a) 2ᵉ 6551 à `$0380` coexistant avec `$031C`
      vs (b) 6551 commutable ; garde d'exclusivité avec une vraie LOCI branchée.
- [ ] US-LOCI.2 **RTL** `loci_acia` (ou paramétrage `acia6551.v`) + `sel_loci`
      prioritaire sur `sel_ext` + testbench `tb_loci_acia`.
- [ ] US-LOCI.3 **Intégration** top + pont UART + synthèse timing.
- [ ] US-LOCI.4 **Validation carte** : dialogue AT depuis l'Oric sur `$0380`.

## Épopée LOCI-SOC — soft-core RISC-V exécutant loci-fw (plan : docs/LOCI_SOC.md)
> ⏸ **PARQUÉE (2026-08-17)** — décision « retour à l'Atmos pur ». Conception
> conservée, non reprise.
Objectif : LOCI fidèle via un **soft-core VexRiscv/LiteX** dans l'ECP5 exécutant
un **portage de `loci-fw`**. **Faits de conception (2026-08-17)** : aucun portage
RP6502→FPGA n'existe (*from scratch*) ; ARM M0 open = expérimental → **RISC-V**
(LiteX a une cible ULX3S). « Tel quel » impossible : recompilation + réécriture du
HAL RP2040 (PIO/DMA/dual-core/USB/XIP). Les couches PIO-bus et WD1793 sont
**redondantes** avec le natif → on garde la **logique applicative** (MIA/API,
menu, fatfs) et on branche sur le bus 6502 natif + SD. **Seul vrai mur : l'USB
host du modem** (repli v0 = UART/ESP32). Approche dé-risquée par spikes.
- [x] US-LOCI-SOC.0 **Conception SoC** (2026-08-17) : `docs/LOCI_SOC.md` —
      faisabilité, choix RISC-V, carte SoC, HAL gardé/réécrit, point USB, jalons.
- [ ] US-LOCI-SOC.1 **Spike** : VexRiscv minimal qui boote sur ULX3S (blinky+UART).
- [ ] US-LOCI-SOC.2 **Mémoire & stockage** : SDRAM + SD lus par le soft-core (fatfs).
- [ ] US-LOCI-SOC.3 **Coexistence** SoC ↔ cœur Oric sans casser le boot actuel.
- [ ] US-LOCI-SOC.4 **MIA bridge** : registre-file `$03A0-$03BF` RTL, 1er API_OP.
- [ ] US-LOCI-SOC.5 **Portage loci-fw** (RV32) : logique MIA/API/menu, op par op.
- [ ] US-LOCI-SOC.6 **Modem** : décision USB (v0 UART/ESP32) puis fidélité.
- [ ] US-LOCI-SOC.7 **Validation carte** : menu LOCI piloté depuis l'Oric.

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

### Sous-chantier MULTIBANK — voie Telestrat fidèle (plan : docs/MULTIBANK.md)
> ⏸ **PARQUÉ (2026-08-17)** — décision « retour à l'Atmos pur ». Le RTL déjà
> livré (bank_window, VIA-2 $0320, telestrat_mode, SDRAM) reste en place mais
> **DORMANT et rétro-compatible** : `telestrat_mode`=0 dans le top, VIA-2 inactif
> tant que non écrit → l'Atmos boote strictement comme avant (test-boot vert).
> Aucune reprise (US-MBANK.3b et suivantes) tant que la décision tient.
**Décision (bmarty, 2026-08-17)** : le mécanisme de banques est spécifié
**Telestrat-fidèle** (spec confirmée sur le web, état de l'art 2026 : core FPGA
BigMist GPL-2.0, ORIX 2025). Fenêtre `$C000` = **8 banques** hétérogènes ROM/RAM,
sélecteur = **3 bits PA0-2 d'un 2ᵉ VIA à `$0320`** (et non le simple `NG_BANK
$03E0`, qui devient un alias optionnel) ; **bank 0 = overlay RAM** (STRATSED),
**bank 7 = TELEMON** (boot). Écritures `$C000` → toujours overlay RAM. Répond à
« RAM aussi ? » = OUI (RAM = banques comme les ROM ; BigMist a 128 Ko RAM).
Clean-room d'après la spec, pas de reprise du code GPL BigMist.
**Cible ORIX (2026-08-17)** : ORIX = **TELEMON 3.0** (bank 7 bootable, appels
`BRK_TELEMON`, 7 banques `orixbank1..7.rom` présentes dans `~/oricutron/roms/`).
La compat ORIX impose : **boot bank 7** (mode Telestrat, US-MBANK.3), **banques
en SDRAM** (112 Ko, US-MBANK.4, cf. `docs/MULTIBANK_SDRAM.md`) et un **CH376**
(stockage FAT32 d'ORIX, à émuler par-dessus `fat32.v`/`sd_spi.v` — modèle dans
`~/oricutron`). ROM ORIX/Telestrat = **usage perso, jamais commitées** (droits).
- [x] US-MBANK.0 **Conception** (2026-08-17) : `docs/MULTIBANK.md` (spec Telestrat,
      `bank_window.v` unifié ROM/RAM+overlay, intégration, budget BRAM/SDRAM, SotA).
- [x] US-MBANK.1 **`bank_window.v` + testbench** (2026-08-17, sim OK) : 8 banques
      logiques à rôle (0=vide→$FF, 1=ROM A, 2=ROM B, 3=RAM→overlay externe) ;
      sortie `bank_is_ram` (crochet banques RAM). Remplace `oric_rom` dans
      `oric_atmos.v` avec `bank_sel={2'b0,rom_bank}` → **strictement identique**
      (bank0=1.1b, bank1=1.0). `test-bank` (défaut + remap + is_ram) et **`test-boot`
      (boot BASIC complet, zéro régression) PASSED**. NB : overlay write + `/MAP`
      **non déplacés** dans le module (déjà servis par `oric_ram`+`rom_as_ram`) —
      écart assumé vs conception §2 pour zéro régression ; `bank_is_ram` les
      branchera en US-MBANK.4. `oric_rom.v` conservé (inutilisé) pour rollback.
- [x] US-MBANK.2 **2ᵉ VIA `$0320` → `bank_sel`** (2026-08-17, sim OK) :
      `via6522` réinstancié à `$0320-$032F` (`sel_via2`, retiré de `sel_ext`,
      ajouté au mux `cpu_di`) ; `bank_sel = (PA0-2 & DDRA) != 0 ? PA0-2 :
      {2'b0,rom_bank}` → le logiciel Telestrat pilote la banque par le port A,
      repli sur le BTN5 validé carte au reset (DDRA=0). IRQ du VIA-2 non câblée
      (banking seul). `test-bank-sel` (écriture DDRA/ORA → banque 1..7, masquage,
      repli) et **`test-boot` (zéro régression) PASSED**.
- [~] US-MBANK.3 **Mode boot Telestrat** (2026-08-17, sim OK) : `oric_atmos.v`
      — nouvel input `telestrat_mode` (câblé `1'b0` dans `top_ulx3s.v` = Atmos par
      défaut) ; `bank_sel` affiné **gate par DDRA** (banque 0 désormais
      sélectionnable ; ambiguïté US-MBANK.2 levée) : DDRA≠0 → banque du port A ;
      DDRA=0 → défaut = **banque 7 (TELEMON)** si `telestrat_mode`, sinon BTN5
      (BASIC 1.1b/1.0). `test-bank-sel` (gate DDRA + défaut bank7 + masquage) et
      **`test-boot` (zéro régression) PASSED**. Les 5 testbenches cœur câblent
      `telestrat_mode(1'b0)`. Reste **US-MBANK.3b** : charger les 7 ROM ORIX
      (`orixbank1..7`) en banques BRAM (conversion .rom→.hex, extension
      `bank_window` à 8 banques physiques, variante de build Telestrat) — les ROM
      restent gitignorées (droits).
- [~] US-MBANK.4 **Banques en SDRAM** (plan : docs/MULTIBANK_SDRAM.md) —
      investigation faite (2026-08-17). Cible ORIX = 7 banques × 16 Ko (112 Ko)
      → hors BRAM → **SDRAM**. Actif réutilisable : `sdram_ctrl.v` d'`~/oric2`
      (EUPL, bmarty, même carte). **Archi retenue** : banque active 16 Ko en
      BRAM adossée SDRAM, **re-remplie par DMA au changement de banque** (PAS de
      lecture SDRAM au fil de l'eau — latence/refresh vs bus 1 MHz). Sous-jalons :
      - [x] US-MBANK.4a Investigation + architecture (doc).
      - [x] US-MBANK.4b Porter `sdram_ctrl` + testbench SDRAM (**sim PASSED**
            2026-08-17 : `rtl/sdram_ctrl.v` + `sim/sdram_model.v` + `sim/tb_sdram.v`
            d'oric2, EUPL/bmarty ; `test-sdram` = init JEDEC + W/R + refresh, 0
            viol). Reste **sur carte** : `sdram_clk` (F19) + PLL + brochage dans
            `top_ulx3s.v` (non validable en sim). SDRAM réservée à la RAM haute.
      - [x] US-MBANK.4c **ABANDONNÉ** (2026-08-17) : mesure yosys — les banques
            ROM tiennent en BRAM (**121→177/208 EBR** avec 7 banques ORIX), donc
            pas de DMA refill (qui cassait le switch instantané des trampolines
            TELEMON). Switch instantané par `bank_sel` → voir US-MBANK.3.
      - [ ] US-MBANK.4d (RAM haute en SDRAM) — reporté, hors chemin critique ORIX.
- [ ] US-MBANK.5 Validation carte : booter TELEMON/ORIX, `!DIR` STRATSED.

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
- [ ] US3.0b **Berceau PCBA « LOCI-Bridge » — routage** (pivot 2026-08-14) :
      la carte à fabriquer est le BERCEAU (l'ULX3S s'enfiche, LOCI par nappe
      IDC 34, schéma = SPEC_NETLIST loci_lvc, 5× LVCC3245A + BSS138).
      Fait : spec convergée avec l'étude ~/NetMaze/ulx3s2Loci (cotes J1/J2
      relevées : 2×20 pas 2,54, entraxe 88,90 mm, piège pairs/impairs des
      embases mâles). Reste : (1) récupérer la table gp/gn ↔ broches J1/J2
      depuis le KiCad emard/ulx3s (pas en local), (2) gen_pcb berceau
      (réutiliser la table U1..U5 de loci_lvc, remplacer peigne par IDC),
      (3) routage. AVANCÉ 2026-08-14 (hardware/berceau, b293439) :
      généré (JB1/JB2 par positions exactes du relevé emard/ulx3s — piège
      pairs/impairs éliminé par construction), TOUS les signaux routés par
      freerouting, plans F.Cu=GND / B.Cu=3V3|5V, vias d'alim posés.
      RESTE (~30 min de KiCad interactif, cf. hardware/berceau/README.md) :
      ~15 liaisons d'alim (îlots de plan isolés), 3 courts, sérigraphie,
      puis REVUE MÉCANIQUE (sens d'enfichage, hauteurs, détrompeur) avant
      gerbers/PCBA. La variante B (loci_lvc, carte peigne) reste gelée
      (7d4b66b).
- [ ] US3.0 **Validation LOCI sur le port d'extension** (demandée 2026-08-13) :
      le bus 34 points est câblé et actif (`rtl/expansion_port.v`,
      `docs/PORT_EXTENSION.md`, gp/gn J1-J2, pull-ups OK, /IOCTRL inhibe
      VIA/ACIA/Microdisc interne). Config visée : cartouche **LOCI** +
      **Pico W sur le port USB externe de la LOCI** (transparent pour le
      FPGA — seul le bus d'extension nous concerne). Matériel à réunir (révision
      2026-08-13 : PAS de TXS0108E — auto-sens inadapté à un bus parallèle
      push-pull, cf. PORT_EXTENSION.md) : 4× 74LVC245 DIP-20 (données
      DIR=R/W + adresses/contrôles + entrées), BSS138 pour /RESET, alim
      5 V externe pour la cartouche (JAMAIS le 5 V du FPGA), masse
      commune, Dupont < 20 cm avec GND intercalés. Consigne : **SW1 OFF** (Microdisc interne
      débranché — la LOCI sert son propre DOS via /ROMDIS+/MAP, éviter
      tout double décodage $0310-$0318). Premier test : boot BASIC normal
      cartouche branchée mais inactive, puis menu LOCI (ADJ_SCAN si
      instable).
- [ ] US3.1 OSD de sélection de fichiers .tap → couvert par US-NETFS.2 (OSD
      incrusté FPGA) ; la source de fichiers devient le serveur WiFi.
- [ ] US3.2 Mode 60 Hz optionnel / meilleure synchro vidéo (triple buffer)
- [x] US3.3 Joystick USB → interface joystick Oric (2026-08-20, sim+synthèse OK,
      **carte à valider**) : `rtl/joystick_ijk.v` (interface IJK, Port A du VIA,
      portage `~/Oric1` joystick.c) ; gamepad USB HID (`game_*`) synchronisé et
      superposé sur `via_pa_in` dans `oric_atmos`. `test-joystick` (9 vecteurs).
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
