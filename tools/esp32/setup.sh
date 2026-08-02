#!/usr/bin/env bash
# Installe l'outillage pour compiler/flasher l'ESP32 embarqué de l'ULX3S :
#   - arduino-cli (local, dans tools/esp32/bin)
#   - le core Arduino esp32 (inclut esptool)
#   - le bitstream passthru officiel 85F (emard/ulx3s-bin), en SRAM au flash
# Idempotent : relançable sans risque.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
BINDIR="$HERE/bin"
ACLI="$BINDIR/arduino-cli"
PASSTHRU_DIR="$HERE/passthru"
PASSTHRU_BIT="$PASSTHRU_DIR/ulx3s_85f_passthru.bit"
ESP32_URL="https://espressif.github.io/arduino-esp32/package_esp32_index.json"
PASSTHRU_URL="https://raw.githubusercontent.com/emard/ulx3s-bin/master/fpga/passthru/passthru-v20-85f/ulx3s_85f_passthru.bit"

echo "==> arduino-cli"
if [ ! -x "$ACLI" ]; then
    mkdir -p "$BINDIR"
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$BINDIR" sh
fi
"$ACLI" version

echo "==> core esp32 (Arduino) — gros téléchargement (toolchain xtensa)"
"$ACLI" config init --overwrite >/dev/null
"$ACLI" config add board_manager.additional_urls "$ESP32_URL"
"$ACLI" core update-index
"$ACLI" core install esp32:esp32

echo "==> bitstream passthru 85F (officiel emard/ulx3s-bin)"
mkdir -p "$PASSTHRU_DIR"
if [ ! -f "$PASSTHRU_BIT" ]; then
    curl -fsSL -o "$PASSTHRU_BIT" "$PASSTHRU_URL"
fi
ls -la "$PASSTHRU_BIT"

echo
echo "OK. Étapes suivantes :"
echo "  make esp32-build            # compile firmware/esp32_modem"
echo "  make esp32-flash            # passthru -> flash ESP32 -> recharge l'Oric"
