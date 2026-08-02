#!/usr/bin/env bash
# Flashe l'ESP32 en le forçant EN MODE DOWNLOAD par un bitstream maison
# (download_esp32 : GPIO0 tenu bas + impulsion EN), puis esptool --before
# no_reset (la puce est déjà en attente, plus besoin du reset DTR/RTS).
#   Usage : tools/esp32/flash-download.sh [port]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ACLI="$HERE/bin/arduino-cli"
FQBN="${FQBN:-esp32:esp32:esp32}"
SKETCH="$ROOT/firmware/esp32_modem"
OUT="$HERE/out"
VENV="$HERE/venv"
PORT="${1:-/dev/ttyUSB0}"
DLBIT="$ROOT/build/download_esp32.bit"

[ -f "$DLBIT" ] || { echo "build/download_esp32.bit manquant -> make build/download_esp32.bit" >&2; exit 1; }
ESPTOOL="$VENV/bin/esptool.py"; [ -e "$ESPTOOL" ] || ESPTOOL="$VENV/bin/esptool"
[ -e "$ESPTOOL" ] || { echo "esptool (venv) absent -> make esp32-flash-classic une fois" >&2; exit 1; }
BOOTAPP0="$(ls ~/.arduino15/packages/esp32/hardware/esp32/*/tools/partitions/boot_app0.bin 2>/dev/null | head -1)"

echo "==> 1/2 chargement du bitstream download (ESP32 -> mode download)"
openFPGALoader -b ulx3s "$DLBIT"
sleep 2

echo "==> 2/2 flash esptool (--before no_reset)"
"$ACLI" compile --fqbn "$FQBN" --output-dir "$OUT" "$SKETCH"
BL="$(ls "$OUT"/*.bootloader.bin | head -1)"
PT="$(ls "$OUT"/*.partitions.bin | head -1)"
APP="$(ls "$OUT"/*.ino.bin | head -1)"

ok=0
for n in 1 2 3 4; do
    echo "  -- tentative $n/4 --"
    if "$ESPTOOL" --chip esp32 --port "$PORT" --baud 115200 \
        --before no_reset --after hard_reset \
        write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect \
        0x1000 "$BL" 0x8000 "$PT" 0xe000 "$BOOTAPP0" 0x10000 "$APP"; then
        ok=1; break
    fi
    sleep 1
done
[ "$ok" = "1" ] || { echo "ÉCHEC. L'ESP32 n'était peut-être pas en download (LED0 doit être allumée)." >&2; exit 1; }
echo "OK — ESP32 flashé. Restaure l'Oric :  make oric-flash  (puis rebranche l'USB)."
