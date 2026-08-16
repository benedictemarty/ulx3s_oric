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


def fit_scale(user_scale):
    """Choisit un pas qui tient dans le terminal (évite le repli = cisaillement).
    Un caractère = 1 pixel large x 2 pixels haut (demi-bloc ▀)."""
    if user_scale:
        return user_scale
    import shutil
    cols, rows = shutil.get_terminal_size((120, 40))
    sx = -(-W // max(1, cols))              # ceil(240/cols)
    sy = -(-H // max(1, 2 * (rows - 1)))    # ceil(224/(2*(rows-1)))
    return max(1, sx, sy)


def cell_color(px, x0, y0, scale, bg):
    # Réduction d'un bloc scale x scale : si UN pixel est de l'encre (!= fond),
    # la cellule prend cette encre (préserve les traits fins de 1 px), sinon fond.
    for dy in range(scale):
        base = (y0 + dy) * W + x0
        for dx in range(scale):
            v = px[base + dx] & 7
            if v != bg:
                return v
    return bg


def render(px, scale, out, bg):
    # Positionnement ABSOLU par ligne (\033[row;1H) : immunisé contre le mode
    # raw où \n ne fait pas de retour chariot (sinon cisaillement diagonal).
    out_rows = []
    r = 1
    for cy in range(0, H - 2 * scale + 1, 2 * scale):
        row = ["\033[%d;1H" % r]
        r += 1
        prev = None
        for cx in range(0, W - scale + 1, scale):
            tv = cell_color(px, cx, cy, scale, bg)
            bv = cell_color(px, cx, cy + scale, scale, bg)
            if (tv, bv) != prev:            # ne réémet la couleur que si elle change
                tr, tg, tb = PAL[tv]
                br, bgc, bb = PAL[bv]
                row.append("\033[38;2;%d;%d;%d;48;2;%d;%d;%dm" % (tr, tg, tb, br, bgc, bb))
                prev = (tv, bv)
            row.append("▀")
        row.append("\033[0m\033[K")         # efface fin de ligne
        out_rows.append("".join(row))
    out.write("".join(out_rows))
    out.flush()


def screen_loop(ser, scale):
    scale = fit_scale(scale)
    sys.stdout.write("\033[2J\033[?25l")     # efface + cache curseur
    sys.stdout.flush()
    try:
        from collections import Counter
        while not _stop.is_set():
            resync(ser)
            frame = read_exact(ser, FRAME)
            if len(frame) == FRAME:
                px = unpack(frame)
                bg = (Counter(px[i] & 7 for i in range(0, W * H, 7))
                      .most_common(1)[0][0])          # couleur de fond (papier)
                render(px, scale, sys.stdout, bg)
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


def write_png(px, path, zoom=3):
    import struct
    import zlib
    raw = bytearray()
    for y in range(H):
        for _ in range(zoom):
            raw.append(0)                      # filtre None
            for x in range(W):
                r, g, b = PAL[px[y * W + x] & 7]
                raw += bytes((r, g, b)) * zoom

    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c \
            + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W * zoom, H * zoom, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def snapshot(ser, path):
    resync(ser)
    frame = read_exact(ser, FRAME)
    if len(frame) == FRAME:
        write_png(unpack(frame), path)
        print("snapshot ->", path)



def find_port(pref):
    """Choisit le port : préférence explicite, sinon 1er /dev/ttyUSB* présent
    (la carte peut passer de ttyUSB0 à ttyUSB1 au rebranchement)."""
    import glob
    import os
    if pref and pref != "auto" and os.path.exists(pref):
        return pref
    cands = sorted(glob.glob("/dev/ttyUSB*"))
    if cands:
        return cands[0]
    return pref or "/dev/ttyUSB0"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="auto",
                    help="auto = 1er /dev/ttyUSB*")
    ap.add_argument("-b", "--baud", type=int, default=1_000_000)
    ap.add_argument("-s", "--scale", type=int, default=0,
                    help="0 = auto-ajuste au terminal")
    ap.add_argument("-k", "--keyboard", action="store_true")
    ap.add_argument("--snap", metavar="FICHIER.png",
                    help="capture une image PNG fidèle puis quitte")
    a = ap.parse_args()

    ser = serial.Serial(find_port(a.port), a.baud, timeout=0.2)

    if a.snap:
        snapshot(ser, a.snap)
        ser.close()
        return

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
