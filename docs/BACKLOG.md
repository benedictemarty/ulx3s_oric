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

## Sprint 3 — « Confort »
- [ ] US3.1 OSD de sélection de fichiers .tap
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
