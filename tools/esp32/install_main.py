#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
install_main.py — installe un fichier sur l'ESP32 interne de l'ULX3S via le
raw-REPL MicroPython (AUCUN flash esptool : contourne le blocage GPIO0).

Prérequis : le bitstream passthru chargé (make esp32-passthru ou
openFPGALoader tools/esp32/passthru/ulx3s_85f_passthru.bit).

Usage : install_main.py <fichier_local> [nom_distant=main.py] [port=/dev/ttyUSB0]
        install_main.py --rm <nom_distant>       (supprime, ex. main.py)
"""
import sys
import time
import serial

PORT = "/dev/ttyUSB0"


def raw_repl(s):
    s.write(b"\x03\x03")          # Ctrl-C x2 : interrompt main.py éventuel
    time.sleep(0.4)
    s.reset_input_buffer()
    s.write(b"\x01")              # Ctrl-A : raw REPL
    time.sleep(0.3)
    out = s.read(1024)
    if b"raw REPL" not in out and b">" not in out:
        raise RuntimeError("raw REPL inaccessible : %r" % out[-80:])


def raw_exec(s, code, timeout=10.0):
    s.reset_input_buffer()
    s.write(code.encode() + b"\x04")   # Ctrl-D : exécute
    deadline = time.time() + timeout
    out = b""
    while time.time() < deadline:
        out += s.read(256)
        if out.endswith(b">"):
            break
    if b"Traceback" in out:
        raise RuntimeError(out.decode("utf-8", "replace"))
    return out


def main():
    args = [a for a in sys.argv[1:]]
    port = PORT
    for a in list(args):
        if a.startswith("/dev/"):
            port = a
            args.remove(a)
    s = serial.Serial(port, 115200, timeout=0.3)
    raw_repl(s)

    if args and args[0] == "--rm":
        raw_exec(s, "import os; os.remove(%r)" % args[1])
        print("supprimé :", args[1])
    else:
        local = args[0]
        remote = args[1] if len(args) > 1 else "main.py"
        data = open(local, "rb").read()
        raw_exec(s, "f = open(%r, 'wb')" % remote)
        for i in range(0, len(data), 256):
            chunk = data[i:i + 256]
            raw_exec(s, "f.write(%r)" % chunk)
        raw_exec(s, "f.close()")
        out = raw_exec(s, "import os; print(os.stat(%r))" % remote)
        print("installé :", remote, out.decode("utf-8", "replace").strip())

    s.write(b"\x02")              # Ctrl-B : REPL normal
    time.sleep(0.2)
    s.write(b"\x04")              # Ctrl-D : soft reboot -> boot.py + main.py
    time.sleep(0.2)
    s.close()
    print("soft reboot envoyé — le programme installé démarre.")


if __name__ == "__main__":
    main()
