# Modem WiFi Oric — 6551 ACIA + ESP32 Hayes (plan)

Objectif : donner à l'Oric un **modem WiFi** utilisable depuis un terminal
(connexion telnet/TCP à un BBS ou un serveur), via un **6551 ACIA émulé dans
le FPGA** relié au **firmware Hayes/WiFi de l'ESP32** embarqué de l'ULX3S.

Décisions (bmarty, 2026-08-02) :
- La logique **Hayes (AT) + WiFi/TCP vit dans le firmware ESP32** (éprouvé,
  type Zimodem) ; le FPGA ne fait que le 6551 + le pont UART.
- On **écrit ce plan complet d'abord**, puis exécution phase par phase.

## Architecture

```
   Oric 6502 ──$031C-$031F──► 6551 ACIA (FPGA)  ──octets──► uart_tx ─► wifi_rxd (K3)
                                   ▲  IRQ                                   │
                                   │                                        ▼
   IRQ 6502 ◄── via_irq|ext_irq|acia_irq                              ESP32 (WiFi)
                                   ▲                                   Hayes AT + TCP
   RX octets ◄── uart_rx ◄── wifi_txd (K4) ◄──────────────────────────────┘
                                        WiFi ──► BBS / serveur telnet
```

Le débit « bande » du 6551 (registre control) est **cosmétique** : le pont
FPGA↔ESP32 tourne à un débit fixe (115200), on transporte les octets 1:1.

---

## Phase 1 — Cœur 6551 dans le FPGA  (RTL, entièrement testable)

### 1.1 Module `rtl/acia6551.v`
Registres (fidèles à `~/Oric1/src/io/acia6551.c`, mappés `$031C-$031F`) :

| Offset | Adresse | Lecture | Écriture |
|--------|---------|---------|----------|
| 0 | `$031C` | RDR (données reçues) — efface RDRF | TDR (données à émettre) — efface TDRE |
| 1 | `$031D` | STATUS — la lecture efface le bit IRQ | (écriture = reset programmé) |
| 2 | `$031E` | COMMAND | COMMAND |
| 3 | `$031F` | CONTROL | CONTROL |

Bits STATUS : `PE 0x01, FE 0x02, OVRN 0x04, RDRF 0x08, TDRE 0x10, DCD 0x20,
DSR 0x40, IRQ 0x80`.
Bits COMMAND : `DTR 0x01, IRD 0x02 (1=RX IRQ off), TIC 0x0C, ECHO 0x10,
PME 0x20, PMC 0xC0`.
Bits CONTROL : `BAUD 0x0F, RXCLK 0x10, WL 0x60, SBN 0x80` (word length / stop
bits — cosmétiques ici).

Comportement :
- **TX** : écriture en `$031C` → octet poussé vers le pont UART, `TDRE`
  retombe puis remonte quand `uart_tx` est libre.
- **RX** : octet reçu du pont → RDR, `RDRF=1`, IRQ si `IRD=0`. Lecture de
  `$031C` → `RDRF=0`. Deuxième octet avant lecture → `OVRN=1`.
- **IRQ** : `RDRF && !IRD` (RX) ou `TDRE && TIC==01` (TX) → `STATUS.IRQ=1` et
  ligne `acia_irq` haute ; **lecture de STATUS efface l'IRQ**. Mode WDC
  optionnel (IRQ re-déclenché tant que RDRF) plus tard si besoin.
- **DCD/DSR** (porteuse / modem prêt) : reflètent l'état de connexion fourni
  par l'ESP32 — voir 1.3.
- Reset (`rst` ou écriture STATUS) : `TDRE=1, RDRF=0`, IRQ effacé.

### 1.2 Intégration `oric_atmos.v`
- Décodage : `sel_acia = sel_io & (bus_addr_q[7:2]==6'h07) & ~ext_ioctl`
  (soit `$031C-$031F`). **Le carver hors de `sel_ext`** (aujourd'hui toute la
  page 3 hors VIA part au bus d'extension) : `sel_ext = sel_io & ~sel_via &
  ~sel_acia | …`.
- Mux data CPU : renvoyer `acia_dout` quand `sel_acia`.
- IRQ : `.IRQ(via_irq | ext_irq | acia_irq)`.
- Registre de l'offset = `bus_addr_q[1:0]`.

### 1.3 Pont UART FPGA↔ESP32 (`top_ulx3s.v`)
- Réutiliser `uart_tx`/`uart_rx` (115200) :
  - 6551 TX → `uart_tx` → **`wifi_rxd` (K3)**.
  - **`wifi_txd` (K4)** → `uart_rx` → 6551 RX.
- `wifi_en` (F1) piloté haut pour activer l'ESP32 ; attention au bootstrap
  `wifi_gpio0` (déjà forcé à 1 pour l'alim — vérifier la cohérence du mode de
  boot ESP32).
- **DCD/DSR** : v1 simple = DCD suit un `wifi_gpio` d'état côté ESP32 (ex.
  `wifi_gpio5`/LED) ou, plus simple encore, un caractère de contrôle en bande
  (l'ESP32 signale « CONNECT »/« NO CARRIER »). À trancher en phase 2.
- Contraintes LPF à ajouter : `wifi_rxd`, `wifi_txd`, `wifi_en` (les SITE
  existent déjà commentés dans le LPF).

### 1.4 Tests (`sim/tb_acia.v`)
- Écriture/lecture des 4 registres, sémantique `TDRE`/`RDRF`/`OVRN`.
- Génération et effacement de l'IRQ (lecture STATUS).
- Boucle : TX → (pont bouclé) → RX, octet identique.
- Non-régression 8/8 + synthèse ECP5 timing.

Livrable phase 1 : le 6551 répond à `PEEK/POKE $031C…$031F` depuis l'Oric, et
tout octet écrit ressort sur `wifi_rxd` (vérifiable à l'oscillo / en bouclant
K3→K4).

---

## Phase 2 — Firmware modem WiFi sur l'ESP32  (hors FPGA, bmarty flashe)

- **Firmware** : Zimodem (ou équivalent ESP32 WiFi-modem) — commandes `AT`,
  `ATDT host:port` (telnet/TCP), `+++`/`ATH`, `ATI`, S-registres, `CONNECT` /
  `NO CARRIER`.
- **Liaison** : UART ESP32 ↔ FPGA à 115200 8N1 sur les pins reliés à
  `wifi_rxd`/`wifi_txd`. Vérifier le mapping GPIO ESP32 (K3/K4 côté FPGA).
- **DCD/porteuse** : le firmware doit exposer l'état de connexion au FPGA →
  soit via un GPIO ESP32 câblé, soit en bande (le FPGA/Oric lit « CONNECT ».)
  Choix à figer ici, puis retour éventuel en phase 1 pour DCD.
- **WiFi** : SSID/mot de passe configurés par AT (`AT+...`) ou en dur au build.
- **Flash de l'ESP32** : procédure ULX3S (esptool via le pont série /
  séquence `wifi_en`+`wifi_gpio0` pour le mode boot). ⚠️ Ne pas casser
  l'alim/boot de la carte (`wifi_gpio0`).

Points ouverts (à lever avant/pendant la phase 2) :
- Confirmer que l'ESP32 est libre (on flashe le FPGA via FTDI/openFPGALoader,
  pas via l'ESP32).
- Interplay `wifi_gpio0` (alim vs mode boot ESP32).
- Contrôle de flux UART (RTS/CTS non câblés → s'appuyer sur XON/XOFF ou débit
  maîtrisé ; le 6551 côté Oric régule via RDRF/TDRE de toute façon).

---

## Phase 3 — Terminal côté Oric

- Un programme qui pilote le 6551 : polling `RDRF` (STATUS `$031D`), lecture
  `$031C`, écriture `$031C`, affichage/saisie clavier. La référence
  `~/Oric1` exerce déjà `$031C` → réutiliser sa logique.
- v0 de test : quelques `POKE/PEEK $031C/$031D` en BASIC pour envoyer `AT` et
  lire `OK`.
- v1 : petit terminal ML (VT52/ANSI minimal) pour se connecter à un BBS.
- À décider : écrire le terminal, ou porter un terminal Oric existant.

---

## Ordre d'exécution
1. **Phase 1** (RTL 6551 + pont + tests + flash) — je la mène entièrement.
2. **Phase 2** (firmware ESP32) — je scaffolde/guide, bmarty flashe et teste.
3. **Phase 3** (terminal Oric) — au choix, après validation du pont.

## Suivi agile
Nouvelle épopée **US-MODEM** au backlog (phases 1→3). Chaque phase : RTL/tests
+ doc + CHANGELOG, non-régression maintenue.
