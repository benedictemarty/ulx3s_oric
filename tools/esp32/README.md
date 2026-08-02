# Outillage ESP32 (ULX3S) — compiler & flasher l'ESP32 embarqué

Chaîne complète pour compiler `firmware/esp32_modem` et le flasher sur
l'**ESP32 embarqué** de l'ULX3S, sans matériel externe.

## Méthode (officielle emard)

L'ESP32 se flashe *à travers* le FPGA : on charge un **bitstream passthru**
qui relie le FTDI (US1) à l'UART0 de l'ESP32 et gère EN/GPIO0 pour le
bootloader, puis on téléverse avec esptool (via arduino-cli). On recharge
ensuite le bitstream Oric.

## Installation (une fois)

```sh
make esp32-setup
```
Installe, en local (`tools/esp32/bin`, ignoré par git) :
- **arduino-cli** (installeur officiel Arduino) ;
- le **core Arduino esp32** d'Espressif (inclut esptool) — gros téléchargement ;
- le **passthru 85F officiel** (`emard/ulx3s-bin`) dans `tools/esp32/passthru/`.

> ⚠️ `make esp32-setup` télécharge et exécute l'installeur arduino-cli
> (`curl | sh`) et récupère plusieurs centaines de Mo (toolchain xtensa). À
> lancer toi-même en connaissance de cause. En environnement restreint,
> exécute-le directement : `! make esp32-setup`.

## Compiler / flasher

```sh
make esp32-build              # compile le firmware
make esp32-flash              # passthru -> flash ESP32 -> recharge l'Oric
make esp32-flash PORT=/dev/ttyUSB1   # port différent
```

`esp32-flash` :
1. charge `ulx3s_85f_passthru.bit` en SRAM (`openFPGALoader -b ulx3s`) ;
2. `arduino-cli upload` sur le port série (esptool entre en bootloader) ;
3. recharge `build/oric_ulx3s.bit`.

## Après le flash — config WiFi

Depuis un terminal côté Oric (écriture sur le 6551 `$031C`), en mode commande :
```
AT$SSID=MonReseau
AT$PASS=monMotDePasse
AT$C          -> WIFI OK
ATDT bbs.exemple.com:23
```

## Dépannage

- **PCB v3.1.x** : si le flash échoue avec le passthru, relie **TMS et GND**
  au connecteur JTAG et réessaie (cf. doc ULX3S).
- L'ESP32 ne doit pas piloter **wifi_gpio5** (LED bleue / TMS) en sortie les
  premières secondes — notre sketch n'y touche pas.
- Mappage UART ESP32↔FPGA à confirmer (cf. `firmware/esp32_modem/README.md`).

## Sources
- Passthru & méthode : `emard/ulx3s-passthru`, `emard/ulx3s-bin`
  (`fpga/passthru/passthru-v20-85f/`).
- Core Arduino : `espressif/arduino-esp32`.
