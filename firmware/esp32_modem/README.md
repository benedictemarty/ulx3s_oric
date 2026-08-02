# esp32_modem — modem WiFi Hayes pour l'Oric (US-MODEM phase 2)

Firmware pour l'**ESP32 embarqué de l'ULX3S**. Il ponte l'UART venant du
**6551 ACIA** émulé dans le FPGA (`$031C-$031F`, phase 1) vers une connexion
**TCP/telnet en WiFi**, en interprétant les commandes **Hayes AT**. L'Oric
« croit » parler à un modem RS-232.

> **Statut : scaffold.** À compiler et flasher par bmarty. Non compilé ni
> testé dans ce dépôt (pas de toolchain ESP32 ici). Les points marqués ⚠️
> demandent une vérification matérielle.

## Câblage FPGA ↔ ESP32

Côté FPGA (déjà en place, cf. `rtl/top_ulx3s.v` + LPF) :

| FPGA | Sens | ESP32 |
|------|------|-------|
| `wifi_rxd` (K3) | FPGA → ESP32 | RX (le 6551 émet) |
| `wifi_txd` (K4) | ESP32 → FPGA | TX (le 6551 reçoit) |
| `wifi_en`       | FPGA → ESP32 | EN (maintenu haut) |

⚠️ **À vérifier sur le schéma ULX3S** : le mappage GPIO exact de cet UART côté
ESP32. Le firmware utilise par défaut `Serial` (**UART0**, GPIO1/3), qui est la
liaison standard ESP32↔FPGA de l'ULX3S. Si UART0 entre en conflit avec la
console/programmation, basculer sur un UART secondaire dans le sketch :
```cpp
HardwareSerial Link(2);
// dans setup(): Link.begin(LINK_BAUD, SERIAL_8N1, RX_PIN, TX_PIN);
```
Le débit **doit rester 115200** (identique aux `uart_tx`/`uart_rx` du FPGA).

## Compilation

Arduino IDE (paquet **esp32** d'Espressif) ou `arduino-cli` :
```sh
arduino-cli compile --fqbn esp32:esp32:esp32 firmware/esp32_modem
```
Carte : « ESP32 Dev Module » (l'ESP32 de l'ULX3S est un module WROOM).
Dépendances : `WiFi`, `Preferences` (fournies par le core esp32).

## Flash de l'ESP32 sur l'ULX3S ⚠️

Sur l'ULX3S, l'ESP32 se flashe **via le FPGA** qui fait passerelle FTDI↔ESP32
et pilote EN/GPIO0 pour le bootloader. Procédure de principe (à confirmer avec
la doc ULX3S / le dépôt `ulx3s-examples`) :
1. Charger un **bitstream « passthru »** ULX3S (relie l'FTDI à l'UART0 de
   l'ESP32 et gère EN/IO0), p.ex. depuis les exemples ULX3S.
2. Flasher avec `esptool.py --chip esp32 --port /dev/ttyUSB0 write_flash ...`
   (ou `arduino-cli upload`), l'esptool gère l'entrée en bootloader.
3. Recharger notre bitstream Oric (`make prog`) pour rétablir le modem.

> Tant que ce point n'est pas rôdé, tester le firmware sur un **ESP32 de
> dev externe** relié à K3/K4/GND est le plus simple.

## Configuration WiFi (une fois)

Depuis un terminal côté Oric (ou tout ce qui écrit sur le 6551), en mode
commande :
```
AT$SSID=MonReseau
AT$PASS=monMotDePasse
AT$C            (connexion WiFi ; réponse WIFI OK / WIFI FAIL)
AT$W            (affiche SSID + IP)
```
SSID/mot de passe sont **persistés en NVS** (Preferences).

## Commandes AT gérées

| Commande | Effet |
|----------|-------|
| `AT` | OK |
| `ATDT host[:port]` / `ATD ...` | connexion TCP (port 23 telnet par défaut) → `CONNECT` |
| `+++` | échappement vers le mode commande (connexion maintenue) |
| `ATO` | retour en ligne |
| `ATH` | raccroche → `NO CARRIER` |
| `ATE0/ATE1` | écho off/on |
| `ATV0/ATV1` | réponses numériques / texte |
| `ATI` | bannière d'identification |
| `ATZ` | reset léger (raccroche) |
| `AT$SSID= / AT$PASS= / AT$C / AT$W` | config/état WiFi (custom) |

Réponses : `OK`, `ERROR`, `CONNECT`, `NO CARRIER`.

## Points ouverts (à traiter en phase 2/3)

- ⚠️ **UART ESP32↔FPGA** : confirmer le GPIO/UART exact (voir plus haut).
- ⚠️ **Procédure de flash ULX3S** de l'ESP32 (passthru + esptool).
- **DCD matériel** : la porteuse est signalée **en bande** (`CONNECT` / `NO
  CARRIER`). Pour un vrai bit **DCD** (`$031D` bit5), router un `wifi_gpio`
  (p.ex. `wifi_gpio5`) depuis l'ESP32 vers l'entrée `acia_dcd` du FPGA (câblée
  à 0 aujourd'hui) — petite retouche RTL à faire quand le firmware pilote la
  porteuse.
- **Contrôle de flux** : pas de RTS/CTS câblé ; le 6551 régule via
  `TDRE`/`RDRF`. Aux débits BBS (≤ 9600 « virtuels ») c'est large ; surveiller
  aux gros transferts.
- **Telnet** : négociations IAC refusées en minimal (`telnetStrip`) ; suffit
  pour la plupart des BBS. PETSCII/ANSI = côté terminal Oric (phase 3).
- **Partage du lien** avec US-NETFS : à terme ce même UART portera aussi le
  contrôle du navigateur de fichiers → prévoir un protocole à canaux
  (cf. `docs/NETFS_WIFI.md`).
