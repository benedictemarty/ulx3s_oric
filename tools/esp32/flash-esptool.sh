#!/usr/bin/env bash
# Flashe l'ESP32 avec un esptool ANCIEN (reset « classique »), pour contourner
# la régression de reset d'esptool >= 4.6 (« UnixTightReset », impulsions trop
# courtes) qui empêche l'entrée en mode download via le passthru ULX3S.
# Prérequis : passthru actif (en flash + carte rebranchée, cf. README).
#   Usage : tools/esp32/flash-esptool.sh [port]
#   Version esptool pinnée : ESPTOOL_VERSION (défaut 4.5.1).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ACLI="$HERE/bin/arduino-cli"
FQBN="${FQBN:-esp32:esp32:esp32}"
SKETCH="$ROOT/firmware/esp32_modem"
OUT="$HERE/out"
VENV="$HERE/venv"
PORT="${1:-/dev/ttyUSB0}"
ESPTOOL_VERSION="${ESPTOOL_VERSION:-4.5.1}"

BOOTAPP0="$(ls ~/.arduino15/packages/esp32/hardware/esp32/*/tools/partitions/boot_app0.bin 2>/dev/null | head -1)"
[ -n "$BOOTAPP0" ] || { echo "boot_app0.bin introuvable (core esp32 installé ?)" >&2; exit 1; }

# venv + esptool pinné
if [ ! -e "$VENV/bin/esptool.py" ] && [ ! -e "$VENV/bin/esptool" ]; then
    echo "==> venv + esptool==$ESPTOOL_VERSION"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet "esptool==$ESPTOOL_VERSION"
fi
ESPTOOL="$VENV/bin/esptool.py"; [ -e "$ESPTOOL" ] || ESPTOOL="$VENV/bin/esptool"
"$ESPTOOL" version || true

# compile + export des binaires
"$ACLI" compile --fqbn "$FQBN" --output-dir "$OUT" "$SKETCH"
BL="$(ls "$OUT"/*.bootloader.bin | head -1)"
PT="$(ls "$OUT"/*.partitions.bin | head -1)"
APP="$(ls "$OUT"/*.ino.bin | head -1)"
echo "bootloader=$BL"; echo "partitions=$PT"; echo "app=$APP"; echo "boot_app0=$BOOTAPP0"

for n in 1 2 3 4 5 6; do
    echo "  -- tentative $n/6 (esptool $ESPTOOL_VERSION, reset classique, 115200) --"
    if "$ESPTOOL" --chip esp32 --port "$PORT" --baud 115200 \
        --before default_reset --after hard_reset \
        write_flash -z --flash_mode dio --flash_freq 80m --flash_size detect \
        0x1000 "$BL" 0x8000 "$PT" 0xe000 "$BOOTAPP0" 0x10000 "$APP"; then
        echo "OK — ESP32 flashé."; exit 0
    fi
    sleep 1
done
echo "ÉCHEC après 6 tentatives (esptool $ESPTOOL_VERSION)." >&2
echo "Essaie une autre version :  ESPTOOL_VERSION=3.3.4 make esp32-flash-classic" >&2
exit 1
