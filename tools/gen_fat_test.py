#!/usr/bin/env python3
# Génère une petite image FAT32 de test (avec table de partition MBR) pour le
# testbench du parseur (sim/tb_fat32.v). Partition FAT32 à LBA=64, FAT d'un
# secteur (suffisant pour le test), répertoire racine avec quelques entrées
# .TAP/.DSK/.TXT. Usage : gen_fat_test.py <sortie.img>
import struct, sys

PART_LBA = 64
RESERVED = 32
NFAT     = 2
FATSZ    = 1                      # 1 secteur/FAT (minimal, suffit pour le test)
ROOT_CLU = 2
SPC      = 1
SEC      = 512

root_dir_lba = PART_LBA + RESERVED + NFAT * FATSZ      # = 98
total_sec    = root_dir_lba + 4                         # marge après le root dir
img = bytearray(total_sec * SEC)

# --- MBR (secteur 0) ---
# code de boot laissé à 0 (l'octet 0 != 0xEB/0xE9 => détecté comme MBR)
mbr = img  # vue
part = 446
img[part+0]   = 0x00                       # non amorçable
img[part+4]   = 0x0C                        # type = FAT32 LBA
img[part+8:part+12]  = struct.pack('<I', PART_LBA)
img[part+12:part+16] = struct.pack('<I', total_sec - PART_LBA)
img[510], img[511] = 0x55, 0xAA

# --- BPB (secteur PART_LBA) ---
b = PART_LBA * SEC
img[b+0:b+3] = bytes([0xEB, 0x58, 0x90])   # jump (marque de VBR)
img[b+3:b+11] = b'MSWIN4.1'
img[b+11:b+13] = struct.pack('<H', SEC)
img[b+13] = SPC
img[b+14:b+16] = struct.pack('<H', RESERVED)
img[b+16] = NFAT
img[b+21] = 0xF8
img[b+36:b+40] = struct.pack('<I', FATSZ)
img[b+44:b+48] = struct.pack('<I', ROOT_CLU)
img[b+510], img[b+511] = 0x55, 0xAA

# --- Répertoire racine (secteur root_dir_lba) ---
def entry(n83, attr, clus, size):
    e = bytearray(32)
    e[0:11] = n83.encode('ascii')
    e[11] = attr
    e[20:22] = struct.pack('<H', (clus >> 16) & 0xFFFF)
    e[26:28] = struct.pack('<H', clus & 0xFFFF)
    e[28:32] = struct.pack('<I', size)
    return e

ents = [
    entry('DEFENDERTAP', 0x20, 3, 58683),
    entry('CITADEL TAP', 0x20, 4, 49767),
    entry('ORICCHESDSK', 0x20, 5, 141056),
    entry('README  TXT', 0x20, 6, 100),      # ignoré (extension TXT)
]
d = root_dir_lba * SEC
for i, e in enumerate(ents):
    img[d + i*32 : d + i*32 + 32] = e

with open(sys.argv[1], 'wb') as f:
    f.write(img)
print(f"image {sys.argv[1]} : part_lba={PART_LBA} root_dir_lba={root_dir_lba} "
      f"total_sec={total_sec} files={len(ents)}")
