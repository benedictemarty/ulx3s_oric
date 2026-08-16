#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
screen_gui.py — console déportée Oric/ULX3S en FENÊTRE graphique (Tkinter,
stdlib). Affiche le framebuffer streamé par le FPGA (rtl/screen_stream.v) sur
l'UART FTDI à 1 Mbaud, à sa résolution native (240x224, zoom x3 -> 720x672),
et renvoie le clavier de la fenêtre vers l'Oric. Aucun artefact de terminal
(pas de scaling/repli/mode raw). Couvre TEXT, HIRES et modes mixtes.

Usage : screen_gui.py [-p /dev/ttyUSB0] [-b 1000000] [-z ZOOM]
Fermer la fenêtre pour quitter.
"""
import argparse
import base64
import struct
import threading
import zlib

import serial
import tkinter as tk

W, H = 240, 224
FRAME = W * H // 2
MAGIC = b"\xAA\x55\xF0\x0F"
PAL = [((v & 1) * 255, (v >> 1 & 1) * 255, (v >> 2 & 1) * 255) for v in range(8)]

_stop = threading.Event()


def read_exact(ser, n):
    buf = bytearray()
    while len(buf) < n and not _stop.is_set():
        c = ser.read(n - len(buf))
        if c:
            buf += c
    return bytes(buf)


def resync(ser):
    win = bytearray()
    while not _stop.is_set():
        b = ser.read(1)
        if not b:
            continue
        win += b
        if len(win) > 4:
            del win[0]
        if win == bytearray(MAGIC):
            return


def frame_to_png(frame, zoom):
    # dépaquette 2 pixels/octet et fabrique un PNG (P6->RGB) zoomé, sans dépendance
    raw = bytearray()
    for y in range(H):
        line = bytearray()
        base = y * W
        for x in range(0, W, 2):
            byte = frame[(base + x) // 2]
            for v in (byte & 0x0F, byte >> 4):
                line += bytes(PAL[v & 7]) * zoom
        for _ in range(zoom):
            raw.append(0)                # filtre None
            raw += line

    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", W * zoom, H * zoom, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    return png


class Console:
    def __init__(self, ser, zoom):
        self.ser = ser
        self.zoom = zoom
        self.root = tk.Tk()
        self.root.title("Oric ULX3S — console déportée")
        self.canvas = tk.Canvas(self.root, width=W * zoom, height=H * zoom,
                                highlightthickness=0, bg="black")
        self.canvas.pack()
        self.img = None
        self.item = self.canvas.create_image(0, 0, anchor="nw")
        self.latest = None
        self.root.bind("<Key>", self.on_key)
        self.root.protocol("WM_DELETE_WINDOW", self.quit)
        self.root.after(50, self.refresh)

    def on_key(self, e):
        ch = e.char
        if not ch:
            # touches spéciales -> codes Oric usuels
            m = {"Return": "\r", "BackSpace": "\x7f", "Escape": "\x1b",
                 "Left": "\x08", "Right": "\x09", "Up": "\x0b", "Down": "\x0a"}
            ch = m.get(e.keysym, "")
        if ch:
            if ch == "\n":
                ch = "\r"
            try:
                self.ser.write(ch.encode("latin-1", "ignore"))
            except Exception:
                pass

    def refresh(self):
        if _stop.is_set():
            self.root.destroy()
            return
        if self.latest is not None:
            png = self.latest
            self.latest = None
            self.img = tk.PhotoImage(data=base64.b64encode(png))
            self.canvas.itemconfig(self.item, image=self.img)
        self.root.after(60, self.refresh)

    def quit(self):
        _stop.set()

    def run(self):
        self.root.mainloop()


def reader(ser, console):
    while not _stop.is_set():
        resync(ser)
        frame = read_exact(ser, FRAME)
        if len(frame) == FRAME:
            console.latest = frame_to_png(frame, console.zoom)



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
    ap.add_argument("-z", "--zoom", type=int, default=3)
    a = ap.parse_args()
    ser = serial.Serial(find_port(a.port), a.baud, timeout=0.2)
    console = Console(ser, a.zoom)
    t = threading.Thread(target=reader, args=(ser, console), daemon=True)
    t.start()
    try:
        console.run()
    finally:
        _stop.set()
        ser.close()


if __name__ == "__main__":
    main()
