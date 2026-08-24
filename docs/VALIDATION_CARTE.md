# Procédure de validation carte — ulx3s_oric

Checklist de tests **matériels** (carte ULX3S 85F) pour les fonctionnalités
actuellement marquées « sim OK, validation carte à faire » dans
[BACKLOG.md](BACKLOG.md) :

| # | Fonctionnalité | US | Statut carte |
|---|----------------|----|--------------|
| 1 | LEDs d'activité (IRQ/VSYNC/USB) | US2.3 | ⬜ à valider |
| 2 | Joystick USB → IJK | US3.3 | ⬜ à valider |
| 3 | Sauvegarde cassette → UART/PC | US-CSAVE.2 | ⬜ à valider |
| 4 | **Sauvegarde cassette → création SD** | US-CSAVE.4 | ⬜ à valider |

> Coche chaque case et note la date/observations au fil de l'eau. En cas
> d'échec, reporte le symptôme précis (LEDs, écran, sortie PC) — c'est ce qui
> permet de diagnostiquer.

---

## 0. Préparation commune

### Matériel
- Carte **ULX3S 85F** + câble USB (port **US1**, côté FPGA/FTDI) vers le PC.
- Écran **HDMI** branché.
- **Clavier USB** sur le port USB hôte de la carte.
- Pour les tests SD : une **micro-SD formatée FAT32** (voir §4).
- Pour le test joystick : un **gamepad USB HID**.

### Build + flash du bitstream
```bash
cd ~/ulx3s_oric
make                 # synthèse -> build/oric_ulx3s.bit (déjà à jour si non modifié)
make prog            # flash volatile (openFPGALoader -b ulx3s)
# ou : make prog-fujprog
```
> `make prog` charge en SRAM (volatile, perdu à la coupure). Pour un flash
> **permanent** en SPI, se référer à la procédure `--unprotect-flash` déjà
> utilisée (cf. historique v1.1.0). Pour la validation, le flash volatile suffit.

### Critère de bon départ
Après flash + reset (**BTN1**), l'écran HDMI affiche le **BASIC Oric** (« Atmos »
/ prompt `Ready`). Le clavier USB permet de taper. Si ce n'est pas le cas,
inutile d'aller plus loin — vérifier alimentation, HDMI, flash.

---

## 1. US2.3 — LEDs d'activité (IRQ / VSYNC / USB)

**But** : vérifier l'overlay d'activité sur les 8 LEDs, activé par **SW4** (`sw[3]`).

### Étapes
1. Boot normal (BASIC affiché).
2. Basculer **SW4** (4ᵉ interrupteur) sur **ON**.
3. Observer les LEDs **hautes** :
   - **LED7 (IRQ)** et **LED6 (VSYNC)** : allumées ~en continu tant que le cœur
     tourne (heartbeat — l'IRQ ~100 Hz et le VSYNC 50 Hz rechargent en
     permanence le monostable).
   - **LED5 (USB)** : **flashe** à chaque frappe clavier / événement gamepad.
4. Repasser **SW4** sur **OFF** : les LEDs reviennent à la **vue diagnostic**
   SD/FAT/sélection habituelle (inchangée).

### ✓ Succès
- SW4=ON → LED7 et LED6 allumées, LED5 clignote quand on tape au clavier.
- SW4=OFF → affichage diagnostic normal restauré.

### Dépannage
- LED7/LED6 éteintes alors que l'écran vit → problème d'horloge/IRQ, à investiguer.
- LED5 ne flashe pas à la frappe → chaîne USB HID (mais le clavier fonctionne
  déjà si on voit les caractères ; vérifier que SW4 est bien lu).

---

## 2. US3.3 — Joystick USB → interface IJK

**But** : un gamepad USB pilote le port joystick **IJK** (VIA Port A, côté
imprimante) vu par un programme Oric.

### Pré-requis
- Un **gamepad USB HID** reconnu (`typ==3`). Il se branche sur le **même port
  USB** que le clavier (hub si besoin de garder le clavier).
- Un programme Oric qui **lit l'IJK** (jeu compatible interface Jasmin/IJK, ou
  petit programme BASIC de lecture du port A imprimante). Réf. mapping :
  [JOYSTICK.md](JOYSTICK.md).

### Étapes
1. Boot, brancher le gamepad USB.
2. Charger/lancer un jeu compatible IJK (via SD/OSD ou cassette).
3. Actionner la croix directionnelle et les boutons **A/B** (= FIRE).

### ✓ Succès
- Les **directions** (haut/bas/gauche/droite) et le **feu** (A ou B) répondent
  dans le jeu.
- Mapping attendu (actif bas sur Port A) : bit0=RIGHT, 1=LEFT, 2=FIRE, 3=DOWN,
  4=UP ; présence signalée dès reconnaissance du gamepad.

### Dépannage
- Rien ne répond → vérifier que le gamepad est bien en `typ==3` (certains
  manettes s'énumèrent autrement). Tester d'abord qu'il est reconnu (une action
  fait flasher **LED5** en mode SW4=ON, §1).
- Un seul stick est émulé (stick A ; stick B non câblé) — conforme à la réf.

---

## 3. US-CSAVE.2 — Sauvegarde cassette → UART / PC

**But** : un `CSAVE` de l'Oric est reçu sur le PC via l'UART FTDI et reconstruit
en `.tap`.

### Étapes
1. Sur le **PC**, lancer le récepteur **avant** de sauvegarder :
   ```bash
   tools/recv_tap.py monprog.tap /dev/ttyUSB0
   ```
   (`pip install pyserial` si besoin.)
2. Sur l'**Oric**, entrer un petit programme puis le sauvegarder :
   ```basic
   10 PRINT "HELLO"
   CSAVE"TEST"
   ```
3. Attendre la fin (le script clôt le `.tap` après un silence).

### ✓ Succès
- `recv_tap.py` écrit `monprog.tap` sans erreur.
- Relecture : renvoyer le fichier à l'Oric le recharge correctement —
  ```bash
  tools/send_tap.py monprog.tap /dev/ttyUSB0
  ```
  puis sur l'Oric `CLOAD""` → `RUN` doit afficher `HELLO`. (Ou vérifier avec un
  émulateur type Oricutron.)

### Dépannage
- Rien reçu → l'écran cède l'UART pendant la capture (`sav_capturing`) ; vérifier
  le bon port `/dev/ttyUSB*` et qu'aucun autre process ne l'occupe.
- `.tap` corrompu → noter la taille reçue et l'octet de divergence.

---

## 4. US-CSAVE.4 — Sauvegarde cassette → **création SD** (nouveau)

**But** : un `CSAVE"NOM"` **crée de zéro** un fichier `NOM.TAP` sur la micro-SD
(allocation FAT + entrée de répertoire + écriture + taille), **sans** placeholder
pré-existant. C'est la fonctionnalité la plus neuve — à tester en priorité.

### Pré-requis micro-SD
- Carte **micro-SD** formatée **FAT32** (MBR **ou** superfloppy ; les deux sont
  gérés). Idéalement quelques fichiers `.tap`/`.dsk` déjà présents pour que l'OSD
  ait un listing — mais **aucun `SAVE.TAP` n'est requis** (placeholder supprimé).
- Insérer la carte dans le lecteur SD de l'ULX3S **avant** le boot.

### Étapes
1. Boot. Vérifier via l'OSD (BTN3/BTN4) que la carte est **lue** (listing des
   `.tap`/`.dsk`). Fermer l'OSD.
2. Sur l'Oric, entrer un programme identifiable puis :
   ```basic
   10 PRINT "SD SAVE OK"
   CSAVE"MONJEU"
   ```
3. Attendre la fin de la sauvegarde (bande « jouée », puis silence).
4. **Éteindre la carte**, retirer la micro-SD, la monter sur le **PC**.

### ✓ Succès
- Un fichier **`MONJEU.TAP`** (nom réel du `CSAVE`, tronqué 8.3, majuscules)
  est présent à la racine de la SD, avec une **taille non nulle et cohérente**.
- `fsck.vfat -n /dev/sdXn` (carte non montée) **ne signale aucune incohérence
  FAT** (correctif multi-FAT : les 2 copies sont écrites).
- Relecture : le fichier est un `.tap` valide —
  ```bash
  tools/send_tap.py MONJEU.TAP /dev/ttyUSB0   # rejoue vers l'Oric
  ```
  puis `CLOAD""` + `RUN` → affiche `SD SAVE OK`. (Ou ouvrir dans Oricutron.)
- Nom vide (`CSAVE""`) → fichier créé sous le nom **`NONAME.TAP`**.

### Points de vérification spécifiques (issus de la revue)
- **Multi-fichiers** : faire **deux** `CSAVE` de noms différents → deux fichiers
  distincts créés, tous deux relisibles, FAT cohérente.
- **Capture interrompue** : lancer un `CSAVE` puis couper (reset **BTN1**) avant
  la fin → au reboot, un nouveau `CSAVE` doit **toujours fonctionner** (pas de
  blocage résiduel ; correctif anti-blocage `had_file`).
- La voie **UART (§3)** fonctionne **simultanément** : on peut lancer
  `recv_tap.py` en parallèle du `CSAVE` qui écrit sur SD.

### Dépannage
- Fichier absent → vérifier que la SD était bien lue au boot (OSD non vide) ;
  la création est inhibée si la FAT n'a pas été parsée.
- Taille = 0 ou fichier tronqué → noter la taille et l'état FAT (`fsck.vfat -v`).
- `fsck` signale une divergence FAT → régression du correctif multi-FAT, à
  remonter.
- Aucune sauvegarde ne marche après une capture coupée → régression du correctif
  anti-blocage, à remonter.

---

## Journal de validation

| # | Test | Date | Résultat | Observations |
|---|------|------|----------|--------------|
| 1 | LEDs d'activité (SW4) | | ⬜ | |
| 2 | Joystick IJK | | ⬜ | |
| 3 | CSAVE → UART | | ⬜ | |
| 4 | CSAVE → création SD | | ⬜ | |
| 4b | Multi-fichiers SD | | ⬜ | |
| 4c | Capture coupée → pas de blocage | | ⬜ | |
