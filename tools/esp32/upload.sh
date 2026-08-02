#!/usr/bin/env bash
# Téléverse SEULEMENT le firmware sur l'ESP32 (sans toucher au bitstream FPGA).
# À utiliser quand le passthru est déjà en FLASH et la carte rebranchée
# (autoexec ESP32 neutralisé via BTN0). cf. tools/esp32/README.md.
#   Usage : tools/esp32/upload.sh [port]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ACLI="$HERE/bin/arduino-cli"
FQBN="${FQBN:-esp32:esp32:esp32}"
UPFQBN="${UPFQBN:-esp32:esp32:esp32:UploadSpeed=115200}"
SKETCH="$ROOT/firmware/esp32_modem"
PORT="${1:-/dev/ttyUSB0}"

[ -x "$ACLI" ] || { echo "arduino-cli absent -> make esp32-setup" >&2; exit 1; }

"$ACLI" compile --fqbn "$FQBN" "$SKETCH"
ok=0
for n in 1 2 3 4 5 6; do
    echo "  -- tentative $n/6 --"
    if "$ACLI" upload --fqbn "$UPFQBN" -p "$PORT" "$SKETCH"; then ok=1; break; fi
    sleep 1
done
[ "$ok" = "1" ] || { echo "ÉCHEC. Refais la séquence BTN0 (README) puis relance." >&2; exit 1; }
echo "OK — ESP32 flashé."
