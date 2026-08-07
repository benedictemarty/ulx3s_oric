#!/usr/bin/env python3
# Capture le "dump debug" d'un fichier de la carte SD envoyé par le FPGA sur
# l'UART (BTN2 sur l'ULX3S). Écrit les octets reçus dans un fichier, puis (si
# un .tap de référence est fourni) compare octet par octet.
#
# Usage :
#   1) Lancer :  ./dump_sd.py sortie.bin [/dev/ttyUSB0] [reference.tap]
#   2) Sur la carte : sélectionner le fichier (BTN3) puis appuyer BTN2 (dump).
#   3) Le script s'arrête après ~2 s sans nouvel octet, puis compare.
import sys, time

try:
    import serial
except ImportError:
    sys.exit("pyserial requis : pip install pyserial")

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: dump_sd.py <sortie.bin> [port] [reference.tap]")
    out = sys.argv[1]
    port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB0"
    ref  = sys.argv[3] if len(sys.argv) > 3 else None

    ser = serial.Serial(port, 115200, timeout=0.2,
                        bytesize=8, parity="N", stopbits=1)
    time.sleep(0.3)
    ser.reset_input_buffer()          # vider tout résidu (crédits, etc.)
    print(f"En écoute sur {port}. Appuie BTN2 (FIRE2) sur la carte pour lancer le dump…")
    data = bytearray()
    last = time.time()
    started = False
    while True:
        chunk = ser.read(4096)
        if chunk:
            data += chunk
            last = time.time()
            if not started:
                started = True
            print(f"\r  reçu {len(data)} octets…", end="", flush=True)
        elif started and (time.time() - last) > 2.0:
            break
    ser.close()
    print()

    with open(out, "wb") as f:
        f.write(data)
    print(f"Écrit {len(data)} octets dans {out}")

    if ref:
        r = open(ref, "rb").read()
        print(f"Référence {ref} : {len(r)} octets")
        n = min(len(data), len(r))
        first_diff = next((i for i in range(n) if data[i] != r[i]), -1)
        if first_diff < 0 and len(data) == len(r):
            print("✅ IDENTIQUE — fat32 lit correctement le fichier.")
        elif first_diff < 0:
            print(f"⚠️  Préfixe identique sur {n} octets, mais tailles différentes "
                  f"(dump={len(data)}, ref={len(r)}).")
        else:
            print(f"❌ Première différence à l'octet {first_diff} :")
            lo = max(0, first_diff - 4)
            print(f"   dump[{lo}:{first_diff+4}] = {bytes(data[lo:first_diff+4]).hex(' ')}")
            print(f"   ref [{lo}:{first_diff+4}] = {bytes(r[lo:first_diff+4]).hex(' ')}")
            # secteur (512 o) concerné
            print(f"   -> secteur du fichier ~ {first_diff // 512}, offset {first_diff % 512}")

if __name__ == "__main__":
    main()
