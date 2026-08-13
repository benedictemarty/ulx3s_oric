#!/usr/bin/env python3
# Banc « replay Sedoric » (diagnostic US-DISK) : génère
#   1. une image FAT32 (spc=8) contenant SEDBOOT.DSK = sedoric3.dsk tronqué
#      aux pistes face 0 utiles au boot (en-tête patché 1 face) ;
#   2. sim/out/sed_replay.hex : la séquence d'écritures WD/Microdisc extraite
#      d'un trace FDC_TRACE de boot RÉUSSI dans l'émulateur de référence —
#      le testbench tb_sedoric la rejoue contre notre RTL avec la sémantique
#      IRQ de Sedoric et signale le premier point de blocage.
# Usage : gen_sed_test.py <image.img> <fdc_trace.log>
import struct, sys, os, re

SEC = 512
SPC = 8
PART_LBA = 64
RESERVED = 32
NFAT = 2
FATSZ = 8
TRACKS = 80                       # image complète : 2 faces x 80 pistes

fat_lba = PART_LBA + RESERVED
root_lba = fat_lba + NFAT * FATSZ
first_data = root_lba

def clus_lba(c): return first_data + (c - 2) * SPC

src = os.path.expanduser('~/Oric1/disks/sedoric3.dsk')
d = open(src, 'rb').read()
# Image complète, en-tête intact : le boot Sedoric lit aussi la face 1
# (piste affichée $80|n dans les messages d'erreur).
dsk = bytearray(d)

CLUS0 = 3
nclus = (len(dsk) + SPC*SEC - 1) // (SPC*SEC)
total = clus_lba(CLUS0 + nclus) + SPC
img = bytearray(total * SEC)

p = 446
img[p+4] = 0x0C
img[p+8:p+12] = struct.pack('<I', PART_LBA)
img[p+12:p+16] = struct.pack('<I', total - PART_LBA)
img[510:512] = b'\x55\xaa'

b = PART_LBA * SEC
img[b:b+3] = bytes([0xEB, 0x58, 0x90])
img[b+3:b+11] = b'MSWIN4.1'
img[b+11:b+13] = struct.pack('<H', SEC)
img[b+13] = SPC
img[b+14:b+16] = struct.pack('<H', RESERVED)
img[b+16] = NFAT
img[b+21] = 0xF8
img[b+36:b+40] = struct.pack('<I', FATSZ)
img[b+44:b+48] = struct.pack('<I', 2)
img[b+510:b+512] = b'\x55\xaa'

f = fat_lba * SEC
def set_fat(c, v): img[f + c*4 : f + c*4 + 4] = struct.pack('<I', v & 0x0FFFFFFF)
set_fat(0, 0x0FFFFFF8); set_fat(1, 0x0FFFFFFF); set_fat(2, 0x0FFFFFFF)
for c in range(CLUS0, CLUS0 + nclus - 1): set_fat(c, c + 1)
set_fat(CLUS0 + nclus - 1, 0x0FFFFFFF)

e = bytearray(32)
e[0:11] = b'SEDBOOT DSK'
e[11] = 0x20
e[26:28] = struct.pack('<H', CLUS0)
e[28:32] = struct.pack('<I', len(dsk))
img[root_lba*SEC : root_lba*SEC + 32] = e

c = clus_lba(CLUS0) * SEC
img[c : c + len(dsk)] = dsk
open(sys.argv[1], 'wb').write(img)

# ---- Séquence de replay depuis le trace ----
seq = []
for line in open(sys.argv[2]):
    m = re.search(r'write \$(03[0-9a-fA-F]{2}) = ([0-9a-fA-F]{2})', line)
    if m:
        seq.append((int(m.group(1), 16) & 0xF, int(m.group(2), 16)))
outdir = os.path.dirname(sys.argv[1]) or '.'
with open(os.path.join(outdir, 'sed_replay.hex'), 'w') as fh:
    for a, v in seq:
        fh.write(f'{a:01x}{v:02x}\n')
print(f'image {sys.argv[1]} : {total} secteurs, SEDBOOT.DSK {len(dsk)} o, '
      f'replay {len(seq)} écritures')
