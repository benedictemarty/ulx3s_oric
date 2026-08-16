#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
screen_view.py — console déportée pour l'Oric sur ULX3S (aucun moniteur ni
clavier requis). Reçoit le framebuffer streamé par le FPGA (rtl/screen_stream.v)
sur l'UART FTDI à 1 Mbaud et le rend en direct dans le terminal (ANSI vraies
couleurs, demi-blocs ▀). Couvre TEXT, HIRES et modes mixtes (on transporte le
rendu final de la ULA). Option -k : renvoie les frappes du terminal vers l'Oric
(clavier série) — un vrai terminal déporté.

Trame FPGA : en-tête AA 55 F0 0F puis 26880 octets = 53760 pixels empaquetés
2/octet (nibble bas = pixel pair). Couleur 3 bits b0=R b1=G b2=B.

Usage :
    screen_view.py [-p /dev/ttyUSB0] [-b 1000000] [-s SCALE] [-k]
      -s SCALE : sous-échantillonnage (défaut 2 -> 120x56 caractères)
      -k       : mode clavier (stdin brut -> Oric). Quitter : Ctrl-]
Sans -k : Ctrl-C pour quitter.
"""
import argparse
import sys
import termios
import threading
import tty

import serial

W, H = 240, 224
FRAME = W * H // 2                 # 26880 octets
MAGIC = b"\xAA\x55\xF0\x0F"

# Palette Oric 8 couleurs (b0=R, b1=G, b2=B)
PAL = [((v & 1) * 255, (v >> 1 & 1) * 255, (v >> 2 & 1) * 255)
       for v in range(8)]

_stop = threading.Event()


def read_exact(ser, n):
    buf = bytearray()
    while len(buf) < n and not _stop.is_set():
        chunk = ser.read(n - len(buf))
        if chunk:
            buf += chunk
    return bytes(buf)


def resync(ser):
    """Aligne le flux sur le prochain en-tête MAGIC."""
    window = bytearray()
    while not _stop.is_set():
        b = ser.read(1)
        if not b:
            continue
        window += b
        if len(window) > 4:
            del window[0]
        if window == bytearray(MAGIC):
            return


def unpack(frame):
    """26880 octets -> liste de 53760 valeurs 0..15 (couleur 3 bits utiles)."""
    px = bytearray(W * H)
    for i, byte in enumerate(frame):
        px[2 * i] = byte & 0x0F
        px[2 * i + 1] = byte >> 4
    return px


def render(px, scale, out):
    at = "\033[H"                  # curseur en haut à gauche
    lines = [at]
    for cy in range(0, H - 2 * scale + 1, 2 * scale):
        row = []
        for cx in range(0, W, scale):
            tv = px[cy * W + cx] & 7
            bv = px[(cy + scale) * W + cx] & 7
            tr, tg, tb = PAL[tv]
            br, bg, bb = PAL[bv]
            row.append("\033[38;2;%d;%d;%d;48;2;%d;%d;%dm▀"
                       % (tr, tg, tb, br, bg, bb))
        lines.append("".join(row) + "\033[0m")
    out.write("\n".join(lines))
    out.flush()


def screen_loop(ser, scale):
    sys.stdout.write("\033[2J\033[?25l")     # efface + cache curseur
    sys.stdout.flush()
    try:
        while not _stop.is_set():
            resync(ser)
            frame = read_exact(ser, FRAME)
            if len(frame) == FRAME:
                render(unpack(frame), scale, sys.stdout)
    finally:
        sys.stdout.write("\033[?25h\033[0m\n")
        sys.stdout.flush()


def keyboard_loop(ser):
    """stdin brut -> Oric. \\n devient CR (13). Ctrl-] (0x1D) quitte."""
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while not _stop.is_set():
            ch = sys.stdin.buffer.read(1)
            if not ch:
                continue
            if ch == b"\x1d":                 # Ctrl-]
                _stop.set()
                break
            if ch == b"\n":
                ch = b"\r"
            ser.write(ch)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB0")
    ap.add_argument("-b", "--baud", type=int, default=1_000_000)
    ap.add_argument("-s", "--scale", type=int, default=2)
    ap.add_argument("-k", "--keyboard", action="store_true")
    a = ap.parse_args()

    ser = serial.Serial(a.port, a.baud, timeout=0.2)

    if a.keyboard:
        t = threading.Thread(target=screen_loop, args=(ser, a.scale),
                             daemon=True)
        t.start()
        try:
            keyboard_loop(ser)
        except KeyboardInterrupt:
            _stop.set()
        t.join(timeout=1)
    else:
        try:
            screen_loop(ser, a.scale)
        except KeyboardInterrupt:
            _stop.set()
    ser.close()


if __name__ == "__main__":
    main()
