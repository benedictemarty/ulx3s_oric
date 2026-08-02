#!/usr/bin/env python3
# Envoi d'un fichier .tap à l'Oric sur ULX3S via l'injecteur cassette FPGA.
#
# Protocole (cf. rtl/tape_injector.v) :
#   PC -> FPGA : 0x01, len_lo, len_hi, puis les octets .tap
#   FPGA -> PC : un octet de crédit (0x5A) par octet que le FPGA peut absorber
#                -> on envoie exactement un octet .tap par crédit reçu.
# Le contrôle de flux évite tout débordement quelle que soit la taille du .tap.
#
# Usage :
#   1) Sur l'Oric :   CLOAD""            (lance le moteur, la ROM attend l'amorce)
#   2) Sur le PC  :   ./send_tap.py monjeu.tap [/dev/ttyUSB0]
#
# L'ordre est indifférent : le FPGA tamponne l'amorce jusqu'à ce que le moteur
# démarre. La LED5 de la carte s'allume pendant le chargement.

import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial requis :  pip install pyserial")


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: send_tap.py <fichier.tap> [port]")
    path = sys.argv[1]
    port = sys.argv[2] if len(sys.argv) > 2 else "/dev/ttyUSB0"

    with open(path, "rb") as f:
        data = f.read()
    n = len(data)
    if n == 0:
        sys.exit("fichier .tap vide")
    if n > 0xFFFF:
        sys.exit(f".tap trop gros ({n} o) : la ROM Oric ne dépasse pas 65535 o")

    ser = serial.Serial(port, 115200, timeout=30,
                        bytesize=8, parity="N", stopbits=1,
                        rtscts=False, dsrdtr=False, xonxoff=False)

    # En-tête : 0x01, longueur (LSB, MSB)
    ser.write(bytes([0x01, n & 0xFF, (n >> 8) & 0xFF]))
    ser.flush()

    print(f"Envoi de {path} ({n} octets). Tapez CLOAD\"\" sur l'Oric si ce n'est fait.")
    sent = 0
    t0 = time.time()
    while sent < n:
        credit = ser.read(1)          # attend un crédit (timeout 30 s)
        if not credit:
            sys.exit(f"\nTimeout : aucun crédit reçu ({sent}/{n}). "
                    "Le moteur cassette tourne-t-il (CLOAD\"\") ? Bon port ?")
        ser.write(data[sent:sent + 1])
        ser.flush()
        sent += 1
        if sent % 64 == 0 or sent == n:
            pct = 100 * sent // n
            print(f"\r  {sent}/{n} o  ({pct}%)", end="", flush=True)

    dt = time.time() - t0
    print(f"\nTerminé : {n} octets en {dt:.1f} s. L'Oric affiche 'LOADING' puis 'READY'.")
    ser.close()


if __name__ == "__main__":
    main()
