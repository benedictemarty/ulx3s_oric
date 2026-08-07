#!/usr/bin/env python3
# Génère roms/font8x8.hex : police 8x8 (128 caractères ASCII, 8 octets/caractère,
# bit 7 = colonne gauche) rendue depuis DejaVu Sans Mono. Usage : gen_font.py
from PIL import Image, ImageFont, ImageDraw
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
font = ImageFont.truetype(FONT, 11)
rows_all = []
for c in range(128):
    img = Image.new("L", (8, 8), 0)
    if 32 <= c < 127:
        d = ImageDraw.Draw(img)
        d.text((-1, -2), chr(c), fill=255, font=font)
    for y in range(8):
        b = 0
        for x in range(8):
            if img.getpixel((x, y)) > 96:
                b |= (1 << (7 - x))
        rows_all.append(b)
with open("roms/font8x8.hex", "w") as f:
    for b in rows_all:
        f.write("%02x\n" % b)
print("roms/font8x8.hex :", len(rows_all), "octets")
