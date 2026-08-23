#!/usr/bin/env python3
# Vérifie l'allocateur FAT32 (US-CSAVE.4 phase 1) sur l'image écrite par le
# testbench : lit les clusters c1/c2/c3 alloués (ligne "ALLOC c1 c2 c3" du log)
# et contrôle la chaîne dans la FAT : FAT[c1]=c2, FAT[c2]=c3, FAT[c3]=EOC.
# Contrôle aussi que c1 était bien la 1re entrée libre (toutes les entrées
# 2..c1-1 sont occupées).
#   Usage : check_fat_alloc.py <image.img> <log>
import struct, sys

def le32(b, o): return struct.unpack('<I', b[o:o+4])[0]

def main():
    img_path, log_path = sys.argv[1], sys.argv[2]
    img = open(img_path, 'rb').read()

    c1 = c2 = c3 = None
    for line in open(log_path):
        if line.startswith('ALLOC '):
            _, a, b, c = line.split()
            c1, c2, c3 = int(a), int(b), int(c)
    if c1 is None:
        print("CHECK FAIL: ligne ALLOC absente du log"); return 1

    # --- localiser le BPB (MBR partition 1) puis la FAT ---
    if img[0] in (0xEB, 0xE9):
        part_lba = 0
    else:
        part_lba = le32(img, 446 + 8)
    b = part_lba * 512
    spc      = img[b + 13]
    reserved = struct.unpack('<H', img[b+14:b+16])[0]
    nfat     = img[b + 16]
    fatsz    = le32(img, b + 36)
    fat_lba  = part_lba + reserved

    f = fat_lba * 512
    def fat(c):
        return le32(img, f + c*4) & 0x0FFFFFFF

    errors = 0
    def check(cond, msg):
        nonlocal errors
        if not cond:
            print("CHECK FAIL:", msg); errors += 1
        else:
            print("ok  :", msg)

    EOC = 0x0FFFFFF8
    check(fat(c1) == c2, f"FAT[{c1}] = {fat(c1)} (attendu {c2})")
    check(fat(c2) == c3, f"FAT[{c2}] = {fat(c2)} (attendu {c3})")
    check(fat(c3) >= EOC, f"FAT[{c3}] = {fat(c3):#x} (attendu EOC >= {EOC:#x})")

    # c1 = 1re entrée libre : 2..c1-1 toutes occupees (!= 0)
    first_hole = next((c for c in range(2, c1) if fat(c) == 0), None)
    check(first_hole is None, f"c1={c1} est bien la 1re entree libre"
          + (f" (trou en {first_hole})" if first_hole is not None else ""))

    if errors == 0:
        print("CHECK PASSED (check_fat_alloc)")
        return 0
    return 1

sys.exit(main())
