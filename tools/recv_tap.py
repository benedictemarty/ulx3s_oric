#!/usr/bin/env python3
# Réception d'un .tap SAUVEGARDÉ par l'Oric (CSAVE) via le démodulateur FPGA.
#
# Chaîne (cf. rtl/tape_demod.v) : la ROM CSAVE bit-bange PB7 -> le FPGA
# démodule la forme d'onde en octets .tap et les émet sur l'UART FTDI. Ce
# script les reçoit et reconstruit le fichier .tap.
#
# Le flux .tap est reconnaissable : amorce d'octets 0x16 puis un marqueur 0x24,
# en-tête de 9 octets (adresses fin/début), nom terminé par 0x00, puis
# (fin - début + 1) octets de données. On se RESYNCHRONISE sur 0x16…0x24 (ce
# qui écarte tout octet parasite reçu avant la sauvegarde) et on parse la
# structure des blocs — MÊME logique que le parseur de tape_injector.v — pour
# savoir exactement quand le fichier est complet.
#
# Usage :
#   1) Sur le PC  :   ./recv_tap.py sortie.tap [/dev/ttyUSB0]
#   2) Sur l'Oric :   CSAVE"NOM"        (démarre la sauvegarde)
# Le script attend l'amorce, capture les blocs, puis écrit le .tap dès qu'un
# silence (aucun octet pendant --idle secondes) suit un ou plusieurs blocs.

import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial requis :  pip install pyserial")

SYNC = 0x16
MARK = 0x24
IDLE_DEFAULT = 2.0     # silence (s) qui clôt la réception après >=1 bloc


def parse_stream(read_byte, idle):
    """Reconstruit le .tap depuis un flux d'octets. `read_byte()` renvoie un
    int (0..255) ou None sur timeout de lecture. Retourne le bytearray .tap."""
    out = bytearray()
    state = "SYNC"       # SYNC -> MARK -> HDR -> NAME -> DATA -> (SYNC | fin)
    hdr = bytearray()
    end_a = start_a = 0
    dcnt = 0
    blocks = 0
    last_rx = time.time()

    while True:
        b = read_byte()
        now = time.time()
        if b is None:
            # Silence : on conclut si au moins un bloc complet a été capturé.
            if blocks > 0 and (now - last_rx) >= idle:
                return out
            if (now - last_rx) >= 30:
                sys.exit("Timeout : aucune donnée .tap reçue. "
                         "CSAVE lancé ? Bon port ? Le moteur cassette tourne-t-il ?")
            continue
        last_rx = now

        if state == "SYNC":
            # On accumule l'amorce (0x16) ; le marqueur 0x24 ouvre un bloc.
            if b == SYNC:
                out.append(b)
            elif b == MARK:
                if not out or out[-1] != SYNC:
                    # 0x24 sans amorce devant : parasite, on ignore.
                    continue
                out.append(b)
                hdr = bytearray()
                state = "HDR"
            else:
                # octet parasite (bruit écran avant la sauvegarde) : on jette
                # tout tant qu'aucune amorce valable n'a commencé un fichier.
                if blocks == 0:
                    out.clear()
        elif state == "HDR":
            out.append(b)
            hdr.append(b)
            if len(hdr) == 9:
                end_a = (hdr[4] << 8) | hdr[5]
                start_a = (hdr[6] << 8) | hdr[7]
                state = "NAME"
        elif state == "NAME":
            out.append(b)
            if b == 0x00:
                dcnt = (end_a - start_a + 1) & 0x1FFFF
                if dcnt <= 0:
                    dcnt = 0
                state = "DATA" if dcnt > 0 else "SYNC"
                if dcnt == 0:
                    blocks += 1
        elif state == "DATA":
            out.append(b)
            dcnt -= 1
            if dcnt <= 0:
                blocks += 1
                state = "SYNC"      # amorce inter-blocs ou fin de fichier


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: recv_tap.py <sortie.tap> [port] [--idle S]")
    path = sys.argv[1]
    port = "/dev/ttyUSB0"
    idle = IDLE_DEFAULT
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--idle":
            idle = float(args[i + 1]); i += 2
        else:
            port = args[i]; i += 1

    ser = serial.Serial(port, 115200, timeout=0.2,
                        bytesize=8, parity="N", stopbits=1,
                        rtscts=False, dsrdtr=False, xonxoff=False)

    print(f"En attente d'un CSAVE sur l'Oric… (port {port})")
    print("  Sur l'Oric :  CSAVE\"NOM\"")

    def read_byte():
        c = ser.read(1)
        return c[0] if c else None

    data = parse_stream(read_byte, idle)
    ser.close()

    with open(path, "wb") as f:
        f.write(data)
    print(f"Écrit {len(data)} octets -> {path}")


if __name__ == "__main__":
    main()
