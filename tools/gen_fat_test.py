#!/usr/bin/env python3
# Génère une petite image FAT32 de test (avec table de partition MBR) pour les
# testbenches SD/FAT. Partition FAT32 à LBA=64, FAT d'un secteur (suffit pour le
# test). Répertoire racine avec quelques entrées .TAP/.DSK/.TXT, plus un fichier
# TEST.TAP au CONTENU réel (motif i&0xFF) réparti sur 2 clusters chaînés dans la
# FAT — pour valider la lecture de fichier (suivi de chaîne). Usage :
#   gen_fat_test.py <sortie.img>
import struct, sys

PART_LBA = 64
RESERVED = 32
NFAT     = 2
FATSZ    = 1
ROOT_CLU = 2
SPC      = 1
SEC      = 512

fat_lba      = PART_LBA + RESERVED                     # 96
root_dir_lba = PART_LBA + RESERVED + NFAT * FATSZ      # 98
first_data   = root_dir_lba                            # cluster 2 -> root dir

def clus_lba(c): return first_data + (c - 2) * SPC

# TEST.TAP : 600 octets sur 2 clusters chaînés (10 -> 11 -> EOC)
TEST_SIZE  = 600
TEST_CLUS  = 10
CLUS_NEXT  = 11
# VALID.TAP : un .tap VALIDE minimal (1 bloc, 4 octets 'ABCD' en $0501-$0504)
# pour le banc bout-en-bout tb_cload_sd (ROM réelle + chaîne SD complète).
VALID_TAP  = bytes([0x16,0x16,0x16,0x24, 0x00,0x00,0x80,0x00,
                    0x05,0x04, 0x05,0x01, 0x00, 0x00,
                    0x41,0x42,0x43,0x44])
VALID_CLUS = 12

# TESTMFM.DSK : image MFM_DISK synthétique (1 face, 3 pistes de 6400 octets,
# 17 secteurs/piste) pour le banc dsk_track/WD1793. Secteur (t,s) rempli du
# motif (t*32 + s) ^ offset. Structure fidèle à mfm_extract_track :
# A1A1A1FE + [track, side, sector, size=1] + CRC + gap + A1A1A1FB + 256 o.
MFM_TRACKS = 3
def build_mfm_dsk():
    out = bytearray(b'MFM_DISK')
    out += (1).to_bytes(4, 'little')            # sides
    out += (MFM_TRACKS).to_bytes(4, 'little')   # tracks
    out += (1).to_bytes(4, 'little')            # geometry
    out += bytes(256 - len(out))                # en-tête complet = 256 o
    for t in range(MFM_TRACKS):
        trk = bytearray()
        trk += b'\x4e' * 40                     # gap initial
        for s in range(1, 18):
            trk += b'\x00' * 12                 # sync
            trk += b'\xa1\xa1\xa1\xfe'
            trk += bytes([t, 0, s, 1])          # ID : track, side, sector, size
            trk += b'\xf7\xf7'                  # CRC (factice)
            trk += b'\x4e' * 22                 # gap 2
            trk += b'\x00' * 12                 # sync
            trk += b'\xa1\xa1\xa1\xfb'
            trk += bytes([((t*32 + s) ^ i) & 0xFF for i in range(256)])
            trk += b'\xf7\xf7'                  # CRC (factice)
            trk += b'\x4e' * 12                 # gap 3
        assert len(trk) <= 6400, len(trk)
        trk += b'\x4e' * (6400 - len(trk))
        out += trk
    return bytes(out)

MFM_DSK   = build_mfm_dsk()
MFM_CLUS  = 13                                  # chaîne 13..13+n-1
MFM_NCLUS = (len(MFM_DSK) + SEC - 1) // SEC
last_used  = clus_lba(MFM_CLUS + MFM_NCLUS - 1)         # dernier secteur écrit
total_sec  = last_used + 2
img = bytearray(total_sec * SEC)

# --- MBR (secteur 0) ---
part = 446
img[part+4]          = 0x0C                             # type FAT32 LBA
img[part+8:part+12]  = struct.pack('<I', PART_LBA)
img[part+12:part+16] = struct.pack('<I', total_sec - PART_LBA)
img[510], img[511]   = 0x55, 0xAA

# --- BPB (secteur PART_LBA) ---
b = PART_LBA * SEC
img[b+0:b+3]   = bytes([0xEB, 0x58, 0x90])
img[b+3:b+11]  = b'MSWIN4.1'
img[b+11:b+13] = struct.pack('<H', SEC)
img[b+13]      = SPC
img[b+14:b+16] = struct.pack('<H', RESERVED)
img[b+16]      = NFAT
img[b+21]      = 0xF8
img[b+36:b+40] = struct.pack('<I', FATSZ)
img[b+44:b+48] = struct.pack('<I', ROOT_CLU)
img[b+510], img[b+511] = 0x55, 0xAA

# --- FAT (secteur fat_lba) : entrées 32 bits little-endian ---
f = fat_lba * SEC
def set_fat(clus, val): img[f + clus*4 : f + clus*4 + 4] = struct.pack('<I', val & 0x0FFFFFFF)
set_fat(0, 0x0FFFFF00 | 0xF8)
set_fat(1, 0x0FFFFFFF)
set_fat(2, 0x0FFFFFFF)                                  # root dir (1 cluster)
set_fat(TEST_CLUS, CLUS_NEXT)                           # chaîne TEST.TAP
set_fat(CLUS_NEXT, 0x0FFFFFFF)
set_fat(VALID_CLUS, 0x0FFFFFFF)                         # VALID.TAP (1 cluster)
for c in range(MFM_CLUS, MFM_CLUS + MFM_NCLUS - 1):     # chaîne TESTMFM.DSK
    set_fat(c, c + 1)
set_fat(MFM_CLUS + MFM_NCLUS - 1, 0x0FFFFFFF)

# --- Données de TEST.TAP (motif i & 0xFF) ---
for i in range(TEST_SIZE):
    sec = i // SEC
    off = i % SEC
    clus = TEST_CLUS if sec == 0 else CLUS_NEXT
    img[clus_lba(clus)*SEC + off] = i & 0xFF

# --- Données de VALID.TAP ---
v = clus_lba(VALID_CLUS) * SEC
img[v : v + len(VALID_TAP)] = VALID_TAP

# --- Données de TESTMFM.DSK (clusters consécutifs) ---
m = clus_lba(MFM_CLUS) * SEC
img[m : m + len(MFM_DSK)] = MFM_DSK

# --- Répertoire racine (secteur root_dir_lba) ---
def entry(n83, attr, clus, size):
    e = bytearray(32)
    e[0:11]  = n83.encode('ascii')
    e[11]    = attr
    e[20:22] = struct.pack('<H', (clus >> 16) & 0xFFFF)
    e[26:28] = struct.pack('<H', clus & 0xFFFF)
    e[28:32] = struct.pack('<I', size)
    return e

ents = [
    entry('DEFENDERTAP', 0x20, 3, 58683),
    entry('CITADEL TAP', 0x20, 4, 49767),
    entry('ORICCHESDSK', 0x20, 5, 141056),
    entry('README  TXT', 0x20, 6, 100),                # ignoré (TXT)
    entry('TEST    TAP', 0x20, TEST_CLUS, TEST_SIZE),  # contenu réel
    entry('VALID   TAP', 0x20, VALID_CLUS, len(VALID_TAP)),  # .tap valide
    entry('TESTMFM DSK', 0x20, MFM_CLUS, len(MFM_DSK)),      # .dsk MFM valide
]
d = root_dir_lba * SEC
for i, e in enumerate(ents):
    img[d + i*32 : d + i*32 + 32] = e

with open(sys.argv[1], 'wb') as fh:
    fh.write(img)
print(f"image {sys.argv[1]} : part_lba={PART_LBA} fat_lba={fat_lba} "
      f"root_dir_lba={root_dir_lba} first_data={first_data} "
      f"total_sec={total_sec} files={len(ents)} TEST.TAP={TEST_SIZE}o@clus{TEST_CLUS}")
