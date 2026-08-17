# CHANGELOG — ulx3s_oric

Toutes les modifications notables de ce projet sont documentées ici.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/).

## [Non publié]

### Ajouté
- **US-DISK.6 — Formatage disquette : commande Write Track du WD1793** (bmarty,
  2026-08-17, **sim validée**) : `rtl/wd1793.v` — la commande `0xF0` (jusque-là
  « write protect ») implémente le **parseur du flux IBM/MFM** de formatage
  (modèle `~/Oric1/src/storage/disk.c`) : marque `FE` → champ ID de 4 octets
  (dont le n° de secteur), marque `FB`/`F8` → champ data de 256 octets poussé
  dans `tbuf` via `sec_we` (au secteur nommé par le dernier ID) ; gaps et octets
  de contrôle CRC (`F5/F6/F7/4E`) ignorés (layout seul). **Write-back par
  secteur** réutilisant la chaîne RMW des phases 3/4 (`wr_commit` → attente
  `wr_ok`), fin de commande quand les `n_spt` secteurs de la piste sont écrits.
  Nouveaux ops `OP_WR_TRK`/`OP_WR_TRK_WB` ; même correctif anti-course
  `cur_offset` (incrément à l'échéance DRQ) que la phase 4. `tb_wd1793` étendu :
  génère un flux MFM de 17 secteurs, capture par secteur, vérifie le motif
  écrit → **`test-wd` PASSED** ; `test-dsk-wr-e2e`/`test-boot`/`test-microdisc`
  **sans régression**. Autorise un `INIT`/formatage Sedoric sur une piste déjà
  cataloguée. (Read Track reste non implémenté — usage marginal.)
- **US-DISK.5 phase 4 — commande Write Sector du WD1793 (écriture disquette
  bout-en-bout)** (bmarty, 2026-08-17, **e2e sim validé**) : `rtl/wd1793.v`
  (commande `0xA0` : DRQ → réception de 256 octets → `sec_we`/`sec_wr_data` vers
  `dsk_track`, `wr_commit` en fin → attente `wr_ok`/`wr_err` ; write-protect
  retiré ; `currentop` élargi à 3 bits, ops `OP_WR_SEC`/`OP_WR_WB`),
  `rtl/dsk_track.v` (`wr_ok`/`wr_err` passés en **niveaux** pour un
  échantillonnage fiable côté WD1793 en domaine `cen`), et **câblage top complet**
  du chemin d'écriture : `wd1793` → `microdisc` → `oric_atmos` → `dsk_track` →
  `fat32.wblk` (tie-offs supprimés). Bug corrigé : décalage d'un octet
  (l'incrément de `cur_offset` était concurrent du pulse `sec_we` large ; déplacé
  à l'assertion du DRQ suivant). Nouveau `sim/tb_dsk_wr_e2e.v` (+ cible
  `test-dsk-wr-e2e`) : chaîne Microdisc+WD1793+dsk_track+fat32+SD, écrit le
  secteur 1 par la commande WD1793, relit → nouveau motif, secteur 2 intact.
  `tb_wd1793` mis à jour (le Write Sector n'est plus « write protect » : écrit
  256 octets vérifiés). **`test-dsk-wr-e2e`, `test-wd` PASSED ;
  `test-boot`/`test-dsk`/`test-microdisc`/`test-dsk-write` sans régression.**
  **US-DISK.5 (écriture disquette) est complète** — un `SAVE` Sedoric a désormais
  tout le chemin RTL (validation carte à faire).
- **US-DISK.5 phase 3 — write-back disquette (RMW) dans `dsk_track`** (bmarty,
  2026-08-17, **sim validée**) : `rtl/dsk_track.v` + `sim/tb_dsk_write.v` + cible
  `test-dsk-write`. Nouveau chemin d'écriture : `sec_we`/`sec_wr_data` poussent
  les octets du secteur dans le buffer de piste (`tbuf`), puis `wr_commit`
  déclenche une **FSM read-modify-write** — pour chacun des 1-2 blocs SD de 512 o
  couvrant le secteur : lecture du bloc (fat32) → overlay des octets du secteur
  (depuis `tbuf`) → réécriture (`fat32.wblk`). Overlay **déterministe** via
  `ocnt0` (octets du secteur dans le 1er bloc), 3 phases par octet pour la
  latence BRAM. `wr_busy`/`wr_ok`/`wr_err` pilotent le WD1793 (phase 4 à venir).
  **2 bugs corrigés au debug** : (1) `ocnt0[12:0]` sur un reg 10 bits → `x` sur le
  2e bloc ; (2) `wblk_data` registré → latence 1-cycle → `sd_spi` latchait
  l'octet précédent au streaming → source rendue **combinatoire** (comme
  `tb_fat_write`). **`test-dsk-write`** (écrit un secteur, recharge depuis la SD,
  vérifie nouvelle donnée + secteur voisin intact) et **`test-dsk`** (lecture,
  zéro régression) **PASSED**. Reste US-DISK.5 phase 4 (commande write sector
  WD1793 + câblage top WD1793↔dsk_track↔fat32.wblk).

### Décision
- **Retour à l'Atmos pur — tangentes Telestrat/ORIX/LOCI parquées** (bmarty,
  2026-08-17) : après une session d'exploration large (émulation LOCI, soft-core
  loci-fw, banking Telestrat, cible ORIX, CH376, comparaison LOCI/CH376), décision
  de **recentrer sur l'Atmos fidèle qui marche** et d'arrêter d'élargir. Les
  épopées **LOCI**, **LOCI-SOC** et le sous-chantier **MULTIBANK** sont **PARQUÉS**
  dans `docs/BACKLOG.md` (exploration conservée, non reprise). **Aucun revert** :
  le RTL multibank livré (bank_window, VIA-2 `$0320`, telestrat_mode, contrôleur
  SDRAM) reste en place mais **dormant et rétro-compatible** — `telestrat_mode`=0,
  VIA-2 inactif tant que non écrit → l'Atmos boote comme avant (`test-boot` vert).
  Les docs de conception (`LOCI_EMULATION`, `LOCI_SOC`, `MULTIBANK`,
  `MULTIBANK_SDRAM`) restent comme trace des études.

### Ajouté
- **US-MBANK.3 — Mode boot Telestrat + affinage sélecteur de banque** (bmarty,
  2026-08-17, **sim validée**) : `rtl/oric_atmos.v` — nouvel input
  **`telestrat_mode`** (0 = Atmos/boot BASIC bank0 ; 1 = Telestrat/boot TELEMON
  bank7), câblé `1'b0` dans `top_ulx3s.v` (Atmos par défaut, zéro régression).
  Sélecteur `bank_sel` affiné : **gate par DDRA** du 2e VIA — dès que le port A
  est piloté (DDRA≠0) la banque en vient (**banque 0 désormais sélectionnable**,
  l'ambiguïté « via2_bank=0 » de US-MBANK.2 est levée) ; sinon défaut =
  **banque 7 (TELEMON, vecteur reset)** en mode Telestrat, ou chemin BTN5
  (BASIC 1.1b/1.0) en Atmos. `sim/tb_bank_sel.v` étendu (gate DDRA, défaut
  bank7, masquage PA0-2) **PASSED** ; **`test-boot` PASSED** (zéro régression) ;
  les 5 testbenches cœur (`tb_boot`/`tb_sedboot`/`tb_trace`/`tb_cload`/
  `tb_cload_sd`) câblent `telestrat_mode(1'b0)`. Reste **US-MBANK.3b** : charger
  les 7 ROM ORIX en banques BRAM (les 177/208 EBR mesurés le permettent).

### Modifié
- **Plan MULTIBANK révisé par une mesure — banques ORIX en BRAM, DMA abandonné**
  (bmarty, 2026-08-17) : synthèse yosys du design complet → **121/208 EBR
  occupés** (87 libres). Une banque ROM 16 Ko = 8 EBR, donc 7 banques ORIX =
  56 EBR → **177/208, ça TIENT en BRAM**. Corrige l'hypothèse non mesurée de
  US-MBANK.4a (« 112 Ko trop juste → SDRAM »). Conséquence : **toutes les banques
  ORIX vont en BRAM** (switch instantané, fidèle aux trampolines TELEMON) ;
  l'architecture « banque active + DMA refill » (US-MBANK.4c) est **ABANDONNÉE**
  (son switch en ~ms cassait les trampolines) ; `bank_backing.v` non écrit. Le
  contrôleur SDRAM (4b) reste pour la **RAM haute**, hors chemin critique ORIX.
  Vrai prochain pas : `bank_window` à 8 banques BRAM + ROM ORIX (MBANK.3).
  Doc mis à jour : `docs/MULTIBANK_SDRAM.md` §2bis.

### Ajouté
- **US-MBANK.4b — Portage du contrôleur SDRAM (bring-up sim)** (bmarty,
  2026-08-17, **sim validée**) : `rtl/sdram_ctrl.v` + `sim/sdram_model.v` +
  `sim/tb_sdram.v` importés d'`~/oric2/hdl` (EUPL-1.2, auteur bmarty, en-têtes
  conservés) + cible `test-sdram`. Contrôleur SDR JEDEC closed-page, 16-bit,
  25-bit adresse (32 Mo). **`test-sdram` PASSED** : init JEDEC (PRECHARGE ALL →
  2× AUTO_REFRESH → LOAD MODE), écriture/relecture de 4 mots sur 2 lignes
  (exerce ACTIVE), persistance après ≥1 auto-refresh (refresh=5), **0 violation**
  READ/WRITE-sans-ACTIVE. Hors bus Oric — c'est le spike dé-risquant qui prouve
  que le contrôleur fonctionne dans `ulx3s_oric` avant d'y accrocher les banques.
  **Reste (sur carte, non simulable)** : `sdram_clk` (F19) + PLL + brochage dans
  `top_ulx3s.v`. Note licence : ces 3 fichiers sont **EUPL-1.2** (mixage assumé).
- **US-MBANK.4a — Investigation budget SDRAM pour les banques ORIX** (bmarty,
  2026-08-17, conception) : `docs/MULTIBANK_SDRAM.md`. Déclenchée par la cible
  **ORIX** (= TELEMON 3.0, **7 banques ROM** `orixbank1..7.rom` dans
  `~/oricutron/roms/`, boot bank 7, stockage **CH376**). 112 Ko de banques ne
  tiennent pas en BRAM → **SDRAM**. Actif réutilisable identifié : `sdram_ctrl.v`
  d'`~/oric2/hdl` (contrôleur SDR JEDEC 16-bit, 32 Mo, EUPL, auteur bmarty, même
  carte) + arbitre + `ulx3s_sdram.lpf`. **Décision d'architecture** : NE PAS lire
  les banques en SDRAM au fil de l'eau (latence variable + refresh vs bus 1 MHz,
  risque de rater l'échantillon t4) mais **banque active de 16 Ko en BRAM adossée
  à la SDRAM, re-remplie par DMA au changement de banque** (modèle `oric_bankN`
  du firmware LOCI). Sous-jalons US-MBANK.4a→d définis. Risques ouverts listés
  (fréquence de swap TELEMON, collision refresh, coexistence horloges HDMI/SDRAM,
  mixage licence EUPL). **Aucun RTL SDRAM ajouté** — investigation seule.
- **US-MBANK.2 — 2ᵉ VIA `$0320` pilotant la banque `$C000` (voie Telestrat)**
  (bmarty, 2026-08-17, **sim validée**) : `rtl/oric_atmos.v` — un `via6522` est
  réinstancié à **`$0320-$032F`** (`sel_via2`, décodage `$03xx` mis à jour :
  retiré de `sel_ext`, ajouté au multiplexeur `cpu_di`). Le **port A** de ce VIA
  (bits de sortie `PA0-2 & DDRA`) devient le **registre de banque** :
  `bank_sel = (via2_bank != 0) ? via2_bank : {2'b0, rom_bank}` — un logiciel
  Telestrat sélectionne la banque `$C000` en écrivant le port A, avec **repli sur
  le BTN5** (BASIC 1.1b↔1.0) validé sur carte quand aucune banque n'est
  sélectionnée (au reset DDRA=0 → repli → **boot inchangé**). IRQ du 2ᵉ VIA **non
  câblée** (banking seul ; IER=0 au reset → pas d'IRQ parasite). Nouveau
  `sim/tb_bank_sel.v` + cible `test-bank-sel` : vérifie écriture DDRA/ORA →
  banques 1..7, masquage PA0-2, et repli BTN5. **Zéro régression prouvée** :
  `test-bank-sel` ET `test-boot` (boot BASIC complet) **PASSED**. Suite :
  numérotation Telestrat fidèle (bank0=RAM overlay, bank7=TELEMON) + ROM réelles
  (US-MBANK.3).
- **US-MBANK.1 — `bank_window.v` : fenêtre multibank $C000 (voie Telestrat)**
  (bmarty, 2026-08-17, **sim validée**) : `rtl/bank_window.v` + `sim/tb_bank_window.v`
  + cible `test-bank`. Généralise `oric_rom.v` (2 banques figées) vers **8 banques
  logiques à rôle** (2 bits/banque : 0=non peuplée→$FF, 1=ROM A, 2=ROM B, 3=RAM
  servie par l'overlay externe), avec sortie **`bank_is_ram`** (crochet pour router
  les futures banques RAM vers l'overlay `oric_ram`+`rom_as_ram` existant, US-MBANK.4).
  Intégré dans `oric_atmos.v` en remplacement de `oric_rom` avec
  `bank_sel={2'b0,rom_bank}` → comportement **strictement identique** (bank0=BASIC
  1.1b, bank1=1.0). **Zéro régression prouvée** : `test-bank` (défaut + remapping
  des rôles + `bank_is_ram`) et `test-boot` (boot BASIC complet du cœur, bannière
  détectée) tous deux **PASSED**. Écart assumé vs conception (`docs/MULTIBANK.md`
  §2) : l'overlay write et `/MAP` **restent** gérés par la RAM 64 Ko existante
  (non dupliqués dans le module) — c'est ce qui garantit la non-régression.
  `oric_rom.v` conservé mais retiré des listes de build (rollback). Suite : 2e VIA
  `$0320` pilotant `bank_sel` (US-MBANK.2). **Makefile** : `oric_rom.v`→`bank_window.v`
  dans `RTL`/`SIM_CORE`, `test-bank` ajouté à `TESTS`.
- **US-MBANK.0 — Conception multibank « voie Telestrat fidèle »** (bmarty,
  2026-08-17) : `docs/MULTIBANK.md` + sous-chantier MULTIBANK sous l'épopée
  ULA-NG dans `docs/BACKLOG.md`. Décision prise avec bmarty : le banking mémoire
  est spécifié **Telestrat-fidèle**, après vérification web (spec faisant autorité
  cc65/OSDK + **état de l'art 2026** : core FPGA **BigMist/Oric_Telestrat**
  GPL-2.0, core MiSTer, OS **ORIX v2025.3**). Spec confirmée : fenêtre `$C000`
  = **8 banques** hétérogènes ROM/RAM, sélecteur = **3 bits PA0-2 d'un 2ᵉ VIA à
  `$0320`** (le `NG_BANK $03E0` de US-ULA-NG.1 devient un alias optionnel),
  **bank 0 = overlay RAM** (STRATSED), **bank 7 = TELEMON** (boot, vecteur reset) ;
  écritures `$C000` → toujours overlay RAM. Réponse tranchée à « si ROM alors RAM
  aussi ? » = **OUI** (la RAM est des banques comme les ROM ; BigMist embarque
  128 Ko RAM). Conception d'un `bank_window.v` **unifié** (banques ROM/RAM +
  overlay + `/MAP`) remplaçant `oric_rom.v`, avec réserve **budget BRAM/SDRAM**
  (128 Ko bankés probablement trop justes en EBR seule → banques RAM en SDRAM à
  chiffrer). Approche **clean-room** (spec, pas le code GPL BigMist). 6 jalons
  US-MBANK.0→5. **Aucun code produit** — conception seule.
- **US-LOCI-SOC.0 — Conception SoC : soft-core RISC-V exécutant loci-fw**
  (bmarty, 2026-08-17) : `docs/LOCI_SOC.md` + épopée LOCI-SOC dans
  `docs/BACKLOG.md`. Périmètre décidé avec bmarty : voie **soft-core + firmware**,
  fidélité maximale. Recherche factuelle : **aucun portage RP6502/RP2040→FPGA
  n'existe** (*from scratch*) ; **Cortex-M0 open-source sur ECP5 = expérimental**
  (netlist DesignStart obfusqué) → on part sur **RISC-V (VexRiscv/LiteX**, cible
  ULX3S clé en main). Constat honnête : « exécuter `loci-fw` tel quel » n'est pas
  atteignable — la voie RISC-V impose de **recompiler** et de **réécrire le HAL
  RP2040** (PIO/DMA/dual-core/USB host/XIP) ; or PIO-bus et WD1793 sont
  **redondants** avec le natif `ulx3s_oric`. Architecture retenue : SoC
  LiteX/VexRiscv gardant la **logique applicative** (MIA/API POSIX, `fatfs`, menu)
  branchée sur le bus 6502 natif + `sd_spi.v`, via un **« MIA bridge »** RTL
  (`$03A0-$03BF`). **Seul vrai mur : l'USB host du modem CDC** (repli v0 =
  UART/ESP32 déjà présent). Plan dé-risqué en 7 jalons (spike VexRiscv →
  SDRAM/SD → coexistence → MIA bridge → portage → modem → validation), avec
  critère d'arrêt (repli sur le MIA RTL pur de `LOCI_EMULATION.md` si la
  coexistence ne tient pas sur la 85F). **Aucun code produit** — conception seule.
- **US-LOCI.0 — Conception de l'émulation LOCI interne** (bmarty, 2026-08-17) :
  `docs/LOCI_EMULATION.md` + nouvelle épopée LOCI dans `docs/BACKLOG.md`.
  Analyse factuelle des sources réelles (`loci-hardware` 1.3, `loci-fw`,
  ROM menu, code client `bbsoric`/`scum`) via 3 explorations parallèles.
  **Décision de périmètre** : la LOCI est un **RP2040 + firmware** ; son cœur
  (MIA `$03A0`, API POSIX open/read/write/mount/boot, ROM swap `$C000`) est
  **logiciel** — non émulable en RTL pur et **redondant** avec la chaîne disque
  native déjà validée (sd_spi→fat32→dsk_track→wd1793→microdisc, boot Sedoric OK).
  Seule brique retenue comme émulable ET distincte de l'existant :
  l'**ACIA 6551 à `$0380`** (canal modem LOCI), face au 6551 existant à `$031C`.
  Soft-CPU exécutant `loci-fw` **écarté** (projet en soi). Backlog : US-LOCI.1
  (décision 2ᵉ 6551 vs commutable) → US-LOCI.4 (validation carte). **Aucun RTL
  produit** — conception seule, à valider avant codage.
- **Note à l'équipe — liaison physique vers la LOCI + berceau PCBA**
  (bmarty, 2026-08-13) : `docs/NOTE_EQUIPE_LIAISON_LOCI.md`. Revue croisée avec
  l'étude indépendante `~/NetMaze/ulx3s2Loci/` : **validation mutuelle** du
  brochage 34 points (reconstruit du schéma réel LOCI 1.3), du choix 74LVC
  (TXS0108E proscrit) et du piège `/OE=/IO` (ROM menu `$C000–$FFFF`). Apport d'un
  **berceau PCBA** (l'ULX3S s'enfiche, entraxe J1/J2 = **88,90 mm** relevé du
  `.kicad_pcb`, 2× 74LVC4245A). **2 points signalés** : `gp/gn[16]` (XCVR_DIR//OE)
  tombent dans la zone ADC « évitée » (N16/M17 = AIN5/AIN4) ; commentaire
  « TXS0108E » obsolète dans l'en-tête de `rtl/expansion_port.v`. Mapping du berceau
  à aligner sur `top_ulx3s.v` (référence).
- **Modem WiFi Hayes sur l'ESP32 interne — INSTALLÉ ET FONCTIONNEL**
  (bmarty, 2026-08-13) : `firmware/esp32_modem/main.py` (MicroPython,
  jeu de commandes COMPATIBLE PicoWiFiModemUSB de ~/picowifi : AT$SSID=,
  AT$PASS=, ATC1, AT&W, ATDT host[:port], +++/ATO/ATH, ATGET http(s),
  ATI, ATZ), installé par le raw-REPL (`tools/esp32/install_main.py`,
  aucun flash esptool), persistant (main.py + wifi.txt dans la flash de
  l'ESP32). Testé via le passthru : AT→OK, ATI→bannière, AT?→aide.
  Reste : config WiFi réelle (AT$SSID/AT$PASS/ATC1/AT&W) et terminal
  côté Oric via le 6551 $031C (US-MODEM.3).

### Ajouté
- **ESP32 interne : REPL MicroPython découvert fonctionnel** (bmarty,
  2026-08-13) : le firmware d'usine MicroPython 1.14 répond sur l'UART
  (115200, passthru officiel), `network.WLAN` opérationnel, flash 4 Mo,
  `boot.py` = stub par défaut. Le blocage « ESP32 non flashable » (GPIO0,
  2026-08-02) ne condamne que le remplacement du firmware par esptool —
  l'injection de code par le REPL (paste mode → `main.py` persistant)
  contourne tout : le modem WiFi (US-MODEM.2) redevient réalisable sans
  matériel externe, en MicroPython. Sondé par script série (tests :
  version, listdir, WLAN, boot.py lu avant toute modification).

### Ajouté
- **US-SD-SPEED : SPI rapide après init + seek FAT32 incrémental** (bmarty,
  2026-08-13, **VALIDÉ SUR CARTE** — boot Sedoric rapide, Citadelle OK,
  cassette/Atmos sans régression ; gravé en flash SPI avec l'OSD
  ouvert/fermé, le reset auto et les broches XCVR) : (1) `spi_byte.v`/`sd_spi.v` — l'init SD reste à ~390 kHz
  (norme), puis tous les transferts passent à `HALF_FAST` (6,25 MHz à
  25 MHz, ×16 — la FSM SPI exige une demi-période ≥ 2 cycles : mosi doit
  précéder le front montant de sck) dès `ready` ; la vitesse est figée au lancement de chaque
  octet (pas de glitch). (2) `fat32.v` — `cur_base` suit l'offset fichier
  du début du cluster courant ; une réouverture du même fichier à un offset
  en aval repart du cluster courant au lieu de re-suivre la chaîne depuis
  le début (chargements de pistes .dsk successives en O(1) ; un seek en
  amont re-parcourt — rare et désormais rapide). Cache invalidé au
  re-listing. Validation : suite complète + `tb_side1` byte-exact.

### Ajouté
- **US-DISK.4 : boot Sedoric VALIDÉ SUR CARTE + OSD ouvert/fermé + reset
  auto** (bmarty, 2026-08-13, « cela fonctionne » — menu Sedoric au boot) :
  `rtl/top_ulx3s.v` — (1) l'OSD a un état ouvert/fermé : BTN4 charge/insère
  ET ferme l'OSD ; fermé, BTN3/BTN4 ne font que le rouvrir. `Citadelle.dsk`
  validé aussi (choix du menu OK — l'« erreur de syntaxe » venait de la
  course de piste, les données servies étaient fausses). Motif : l'OSD
  restait affiché pendant le boot disquette et les appuis « pour fermer »
  lançaient un chargement cassette qui volait le bus SD (READ FAULT sur le
  répertoire) et enclenchait le turbo ×4 (touches répétées, curseur rapide).
  L'OSD ne se rouvre pas sur reset (pas de recouvrement du boot).
  (2) Insertion d'un .dsk = reset automatique : on attend le front de
  `dsk_inserted` (la disquette survit au soft reset) puis ~5 ms de reset —
  la machine reboote sur l'EPROM Microdisc qui trouve la disquette ; plus
  besoin de BTN1. Lenteur connue : chaque piste refait le seek FAT32 depuis
  le début du fichier à la vitesse SPI d'init → chantier « SPI haute
  vitesse » au backlog.

### Corrigé
- **Boot Sedoric : gel après la bannière (US-DISK.4) — deux causes racines**
  (bmarty, 2026-08-13, validé en sim `tb_sedboot` : la séquence FDC suit la
  référence sans divergence, plus de tempête d'IRQ ni de READ FAULT) :
  1. `rtl/oric_ram.v` : la BRAM démarrait toute à zéro ; or le boot Sedoric
     (`$B932`) checksomme la RAM haute `$C980-$FFFF` — tout-zéro est pris
     pour un boot à chaud → **mini-loader 4 secteurs** au lieu des 60 de
     SYSTEM.DOS → vecteur IRQ posé sur `$D0A5` vide → tempête BRK. La RAM
     est maintenant initialisée au motif Oricutron (rampattern=0) : par page
     de 256 octets, 128×`$00` puis 128×`$FF` (même init sim et synthèse).
  2. `rtl/dsk_track.v` : course seek/rechargement — un seek arrivant PENDANT
     un rechargement de piste (cas réel : le noyau écrit ctl side=1 puis
     seek 4 cycles plus tard) étiquetait le buffer avec la NOUVELLE cible
     (`loaded <= wanted` échantillonné en fin de scan) → piste 20 face 1
     servie comme « piste 13 face 1 », secteurs pleins d'espaces `$20` →
     « TRACK:20 SECTOR:20 READ FAULT ». La cible est maintenant capturée au
     début du chargement (`load_tgt`) : si la demande change en cours de
     route, le mismatch persiste et la bonne piste est rechargée aussitôt.
  Bancs : `sim/tb_side1.v` (diagnostic ciblé face 1, hors suite) ;
  `sim/tb_dsk.v` scénario 3 = non-régression de la course (deux seeks
  enchaînés sans attendre, la piste servie doit être celle du second).
  `tools/gen_sed_test.py` : SEDBOOT.DSK n'est plus tronqué à 62 pistes
  face 0 — le boot lit aussi la **face 1** (piste `$80|n` dans les messages
  d'erreur Sedoric), l'image embarque les 2 faces × 80 pistes.

### Ajouté
- **Deux banques ROM (US-ULA-NG.1, première tranche) — VALIDÉ SUR CARTE**
  (bmarty, 2026-08-11, **Citadel chargé jusqu'au « Choix des couleurs »**) :
  `rtl/oric_rom.v` héberge 2 banques de 16 Ko en BRAM — banque 0 = BASIC
  1.1b (défaut), banque 1 = **BASIC 1.0** (`roms/basic10.hex`, généré depuis
  la ROM de l'émulateur). **BTN5 (gauche)** bascule la banque et déclenche
  un reset (~5 ms) ; vérification de la banque active : `PRINT PEEK(#FFF9)`
  (1 = 1.1b). Décidé après le diagnostic Citadel : les jeux à loader protégé
  vérifient la révision exacte de la ROM et sautent dans ses entrailles —
  la 1.0 est un des deux chemins supportés par Citadel, et sur carte les
  4 blocs s'enchaînent grâce à l'amorce inter-blocs. Testbenches : `tb_boot`
  boote les deux banques (`+bank=1`). Limitation connue : la bascule fait
  un warm-boot silencieux (pas de bannière — la RAM n'est pas effacée) ;
  nettoyage de la signature à prévoir pour un vrai boot à froid.

### Ajouté
- **Interface Microdisc (US-DISK.2) — VALIDÉE SUR CARTE** (bmarty,
  2026-08-12 : SW1 ON → « insert system disc », SW1 OFF → Atmos intact) :
  `rtl/microdisc.v` fidèle à `~/Oric1/src/io/microdisc.c` — registres
  `$0310-$0313` (WD1793), `$0314` W = contrôle (b0 INTENA, b1 /ROMDIS,
  b4 side, b6:5 drive, b7 /EPROM), `$0314`/`$0318` R = /INTRQ//DRQ
  (bit 7 actif bas, b6:0 = 1), EPROM `microdis.rom` 8 Ko en overlay
  `$E000-$FFFF` ($C000-$DFFF = RAM overlay, sémantique /ROMDIS combinée
  avec le port d'extension), IRQ 6502 gouvernée par INTENA. Au boot :
  ROMDIS + EPROM actifs (la machine démarre sur l'EPROM, comme le vrai
  matériel). **SW1 (DIP) = interface « branchée »** — à OFF, l'Atmos est
  strictement inchangé (comme débrancher le Microdisc). Décodage
  `$0310-$031B` (l'ACIA garde `$031C-$031F`). Testbenches :
  `tb_microdisc` (registres, flags, EPROM, transparence) et `tb_boot
  +microdisc=1` — **la machine boote l'EPROM et affiche « insert system
  disc »** (pas encore de disquette : fournisseur de secteurs en bouchon
  jusqu'à US-DISK.3, pistes depuis la SD). 19/19 tests.
- **Cœur FDC WD1793 (US-DISK.1) — validé en simulation** (2026-08-12) :
  `rtl/wd1793.v`, fidèle à `~/Oric1/src/storage/disk.c` (modèle
  FDC_TIMING_REAL) : registres command/track/sector/data, type I
  (restore/seek/step, délais r1r0 6-30 ms + settling V 30 ms), type II
  (read sector simple/multiple, latence rotationnelle 300 RPM, DRQ par
  octet différé), type III (read address), type IV (force interrupt),
  status type I « vivant » (index pulse par tour, TRK0), RNF après
  5 tours d'index. **v1 lecture seule** (écritures → write protect,
  comportement disquette protégée). Interface fournisseur de secteurs
  (piste en BRAM + table d'IDs, à venir en US-DISK.3) avec gel des
  délais pendant un chargement SD (`trk_loading`). Testbench
  `tb_wd1793` (timings réduits) : 8 familles de scénarios. Épopée
  US-DISK démarrée : plan révisé source = carte SD (cf. backlog).
- **Mode turbo chargement (US-ULA-NG.8) — RÉSOLU, VALIDÉ SUR CARTE**
  (bmarty, 2026-08-12) : pendant un chargement cassette (`tape_active`),
  tout le domaine `cen1` (CPU+VIA+AY) passe de 1 MHz à ~4,17 MHz
  (`TURBO_DIV=6`, bascule à chaud sûre) et l'injecteur réduit ses
  demi-périodes du même ratio — chargement effectif ~3×, retour 1 MHz
  automatique dès la fin (y compris jeux autorun qui coupent le moteur).
  L'enquête (banc bout-en-bout `sim/tb_cload.v` : boot ROM réel + frappe
  `CLOAD""` + cassette, traces VIA/RAM, **désassemblage de GetTapeByte
  `$E6C9`**) a livré trois correctifs :
  1. **Stops supplémentaires** (trame 14→18 bits, données seulement) : la
     fenêtre inter-octets de la ROM (traitement + IRQ T1 100 Hz) dépassait
     les 4 stop bits → fronts manqués → raccrochage 2 bits trop tard
     (octet faux, signature `$41`→`$D0`) → « Errors found ». La ROM brûle
     un front puis saute les périodes courtes : des '1' en plus sont
     transparents. (Un gap silencieux ne convient PAS : son front terminal
     — le vrai start — se fait manger par le brûleur.) Course d'ailleurs
     LATENTE à 1 MHz (reproduite en tb), jamais vue sur carte avec les
     vrais jeux — comportement 1 MHz inchangé.
  2. **Phase vidéo dédiée `tphase_v`** (toujours 1 MHz) pour l'ULA et le
     port d'extension : sinon l'ULA ne voit plus les phases 6..24 en turbo
     → image figée (le chargement marchait, l'écran restait sur
     « Searching » — diagnostic décisif : reset → l'écran chargé apparaît).
  3. **Fin de bande moteur coupé** : les jeux autorun stoppent le moteur
     dès leur dernier octet lu ; l'injecteur conclut (S_DONE) s'il ne
     reste que des stop bits gelés — sinon `tape_active`/turbo/OSD
     restaient bloqués (jeu à 3×).
  Bancs : `tb_tape` scénarios turbo + moteur-coupé, `tb_cload`
  (`ALL TESTS PASSED turbo=1`, données `$0501-0504` exactes),
  `tb_cload_sd` (chaîne SD complète) disponible ; image de test
  `gen_fat_test.py` enrichie d'un `VALID.TAP`. 17/17 tests, timing 50 MHz.

### Corrigé
- **`.tap` multi-parties : amorce ré-insérée entre les blocs — VALIDÉ SUR
  CARTE** (bmarty, 2026-08-10, Defense Force — 4 blocs, 59 Ko — chargé et
  fonctionnel) : le format `.tap` ne conserve que ~3 octets de sync `0x16`
  entre les parties (la longue amorce de la vraie bande est supprimée). Or
  entre deux parties l'Oric traite le bloc chargé moteur actif : les ~20 ms
  de sync partaient dans le vide et le `CLOAD` suivant restait en
  « Searching... ». `rtl/tape_injector.v` parse désormais la structure des
  blocs (sync → `0x24` → en-tête 9 octets avec adresses fin/début → nom →
  données de fin−début+1 octets) et ré-insère `INTER_SYNCS` (255, ~1,8 s)
  trames d'amorce à chaque frontière de bloc — comme la vraie cassette.
  Sans risque : des `0x16` devant une amorce sont transparents pour la ROM,
  le parsing garantit de ne jamais insérer dans les données (structure
  vérifiée sur DEFENDER.TAP : les 4 frontières tombent exactement), pas
  d'insertion après le dernier octet, et un flux non conforme désactive
  simplement l'insertion. Testbench `tb_tape` : scénario multi-parties
  (2 blocs complets) — amorce initiale + bloc 1 + amorce inter-blocs +
  bloc 2 vérifiés trame par trame. Bénéficie aussi au chargement UART
  (`send_tap.py`), même injecteur.
- **Chargement `.tap` depuis la SD — bug résolu, VALIDÉ SUR CARTE**
  (bmarty, 2026-08-10, BREAKOUT chargé et fonctionnel) : le point ouvert
  des sessions précédentes était un défaut de protocole du flux fichier.
  `fat32` émettait un octet à CHAQUE cycle où `fdata_ready` était haut,
  or `tape_loader` tenait ce signal haut 2-3 cycles par crédit → 2-3
  octets partaient en rafale par crédit, le compteur de crédits passait
  en underflow 16 bits (65535 crédits fantômes) → plus aucun contrôle de
  flux → débordement de la FIFO 256 du `tape_injector` → données
  corrompues, l'Oric coupait le moteur. `fat_dump` avait le bug inverse
  (impulsion `fdata_ready` d'un cycle, perdue si `fat32` lisait le
  secteur suivant → blocage aux frontières de secteur).
  - Correctif : handshake **valid/ready** standard dans `rtl/fat32.v`
    (FO_EMIT : octet présenté, `fdata_valid` tenu jusqu'au cycle où
    valid ET ready sont hauts — exactement un octet par transfert),
    `rtl/tape_loader.v` (transfert compté une seule fois, décrément
    exact des crédits) et `rtl/fat_dump.v` (`ready` en niveau).
  - Testbench `tb_tape_loader` durci : crédits espacés + détection des
    rafales (espacement < DELAY = échec) et des octets excédentaires.
    Vérifié : l'ancien RTL échoue (« rafale, espacement 1 cycle »), le
    nouveau passe. Suite complète : 17/17 testbenches verts, timing OK.

### Documenté
- **US-ULA-NG.8 : mode turbo 6502** au backlog : registre NG_TURBO
  (fenêtre ULA-NG) commutant l'horloge CPU 1 MHz fidèle → 8/16 MHz+
  (BRAM sans wait state) ; VIA/AY/cassette restent au 1 MHz réel ;
  retour 1 MHz sur reset. Retenu comme alternative au 65C816 dans ce
  projet (le 65C816 = territoire du workspace séparé `~/oric2`).
- **US-ULA-NG.5 : architecture DOS/BASIC actée** (bmarty, 2026-08-10) :
  banque 0 (boot, vecteur reset) = DOS cc65 (SD/FAT32, menu, hooks) qui
  fait ensuite le handover vers la banque 1 = BASIC 1.1b patché. Le DOS
  reste appelable depuis le BASIC façon Sedoric : hooks vecteurs page 2 +
  résident RAM basse, commandes `!DIR`/`!LOAD`, commutation NG_BANK
  aller-retour, échanges par la RAM basse (< `$C000`).
- **US-ULA-NG : expérience utilisateur + VRAM dédiée** (décisions bmarty,
  2026-08-10) : boot 100 % classique ; la commande **`HIRES 1`** (BASIC
  étendu, ROM 1.1b patchée en banque de boot) bascule en mode OCULA/NG,
  `HIRES` sans argument inchangé. Les modes vidéo étendus utilisent une
  **VRAM à part** (BRAM séparée de la RAM 6502, accès par port indexé
  style VDP) — nouveaux incréments US-ULA-NG.6 (BASIC étendu) et
  US-ULA-NG.7 (VRAM + texte haute qualité 8×16/14×18 + hires 640×400).
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
