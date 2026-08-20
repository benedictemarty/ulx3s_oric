#!/usr/bin/env python3
# Vérifie, dans une image FAT32 de test, la taille de l'entrée de répertoire
# du fichier SAVE.TAP (US-CSAVE.3 refinement). Sert de post-check au banc
# tb_tape_saver : le modèle SD écrit réellement dans le .img, donc après le RMW
# du secteur de répertoire le champ taille (octets 28-31 de l'entrée) doit valoir
# la taille sauvegardée. Vérifie aussi que le début des données a bien été écrasé
# (plus de 0xEE au tout début du contenu).
#   check_save_tap.py <image.img> <taille_attendue>
import struct, sys

def main():
    img = open(sys.argv[1], 'rb').read()
    want = int(sys.argv[2])
    SEC = 512
    # MBR : 1re entrée de partition à 446, LBA de début à +8
    part_lba = struct.unpack('<I', img[446+8:446+12])[0]
    b = part_lba * SEC
    reserved = struct.unpack('<H', img[b+14:b+16])[0]
    nfat     = img[b+16]
    fatsz    = struct.unpack('<I', img[b+36:b+40])[0]
    root_clus= struct.unpack('<I', img[b+44:b+48])[0]
    root_lba = part_lba + reserved + nfat*fatsz + (root_clus-2)  # spc=1
    # balaie le répertoire racine (1 secteur suffit pour l'image de test)
    d = root_lba * SEC
    found = None
    for i in range(SEC // 32):
        e = img[d+i*32 : d+i*32+32]
        if e[0] in (0x00, 0xE5):
            continue
        if e[0:11] == b'SAVE    TAP':
            found = e
            break
    if not found:
        sys.exit("FAIL check_save_tap: entree SAVE.TAP introuvable")
    size = struct.unpack('<I', found[28:32])[0]
    if size != want:
        sys.exit(f"FAIL check_save_tap: taille SAVE.TAP={size}, attendu {want}")
    # début des données : le cluster de SAVE.TAP ne doit plus commencer par 0xEE
    clus = (struct.unpack('<H', found[20:22])[0] << 16) | struct.unpack('<H', found[26:28])[0]
    first_data = part_lba + reserved + nfat*fatsz  # cluster 2 -> root
    data_lba = first_data + (clus - 2)
    if img[data_lba*SEC] == 0xEE:
        sys.exit("FAIL check_save_tap: 1er octet de donnees encore 0xEE (pas ecrase)")
    print(f"OK check_save_tap: SAVE.TAP taille={size}, 1er octet donnees=0x{img[data_lba*SEC]:02x}")

if __name__ == '__main__':
    main()
