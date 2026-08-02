#!/usr/bin/env bash
# Flashe l'ESP32 embarqué de l'ULX3S, puis rétablit le bitstream Oric.
#   1) charge le passthru en SRAM (FPGA fait passerelle FTDI <-> ESP32)
#   2) compile + téléverse le firmware modem via arduino-cli (esptool)
#   3) recharge le bitstream Oric
#
# Usage :  tools/esp32/flash.sh [port]     (port par défaut : /dev/ttyUSB0)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ACLI="$HERE/bin/arduino-cli"
FQBN="${FQBN:-esp32:esp32:esp32}"
SKETCH="$ROOT/firmware/esp32_modem"
PASSTHRU_BIT="$HERE/passthru/ulx3s_85f_passthru.bit"
ORIC_BIT="$ROOT/build/oric_ulx3s.bit"
PORT="${1:-/dev/ttyUSB0}"

[ -x "$ACLI" ]        || { echo "arduino-cli absent -> make esp32-setup" >&2; exit 1; }
[ -f "$PASSTHRU_BIT" ] || { echo "passthru absent -> make esp32-setup" >&2; exit 1; }

echo "==> 1/3 passthru en SRAM (FTDI <-> ESP32)"
openFPGALoader -b ulx3s "$PASSTHRU_BIT"
sleep 1

echo "==> 2/3 téléversement du firmware sur l'ESP32 ($PORT)"
"$ACLI" compile --fqbn "$FQBN" "$SKETCH"
# Baud d'upload réduit (plus fiable à travers le passthru) + retry : la doc
# ULX3S officielle recommande de réessayer jusqu'à « Hash of data verified ».
UPFQBN="${UPFQBN:-esp32:esp32:esp32:UploadSpeed=115200}"
ok=0
for n in 1 2 3 4 5 6; do
    echo "  -- tentative $n/6 --"
    if "$ACLI" upload --fqbn "$UPFQBN" -p "$PORT" "$SKETCH"; then ok=1; break; fi
    sleep 1
done
if [ "$ok" != "1" ]; then
    echo "ÉCHEC après 6 tentatives." >&2
    echo "Parade autoexec ESP32 (firmware d'usine websvf qui bavarde) :" >&2
    echo "  débranche l'USB, MAINTIENS BTN0 enfoncé, rebranche l'USB ;" >&2
    echo "  quand la LED bleue D22 clignote une fois (~0,5 s), relâche BTN0 ;" >&2
    echo "  puis relance 'make esp32-flash'." >&2
    echo "  (⚠️ le rebranchement efface le passthru en SRAM : il faut alors" >&2
    echo "   d'abord le mettre en FLASH — voir tools/esp32/README.md.)" >&2
    exit 1
fi

echo "==> 3/3 rechargement du bitstream Oric"
if [ -f "$ORIC_BIT" ]; then
    openFPGALoader -b ulx3s "$ORIC_BIT"
else
    echo "  ($ORIC_BIT absent — fais 'make prog' pour recharger l'Oric)"
fi

echo "OK — ESP32 flashé. Configure le WiFi via AT\$SSID=.../AT\$PASS=.../AT\$C."
echo "Note ULX3S PCB v3.1.x : si le flash échoue, relie TMS et GND au connecteur JTAG et réessaie."
