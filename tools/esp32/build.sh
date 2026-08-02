#!/usr/bin/env bash
# Compile le firmware modem ESP32 (firmware/esp32_modem) avec arduino-cli.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
ACLI="$HERE/bin/arduino-cli"
FQBN="${FQBN:-esp32:esp32:esp32}"
SKETCH="$ROOT/firmware/esp32_modem"

if [ ! -x "$ACLI" ]; then
    echo "arduino-cli absent. Lance d'abord :  make esp32-setup" >&2
    exit 1
fi

"$ACLI" compile --fqbn "$FQBN" --warnings default "$SKETCH"
echo "OK — firmware compilé (build dans le cache arduino-cli du sketch)."
