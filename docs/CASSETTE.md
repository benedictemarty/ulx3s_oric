# Chargement de programmes `.tap` (cassette)

L'ULX3S charge un fichier `.tap` Oric via un **injecteur cassette dans le
FPGA** : le PC envoie le `.tap` sur l'UART (US1, le câble de programmation),
le FPGA génère la forme d'onde cassette exacte et la présente à la ROM comme
une vraie lecture de bande. Fonctionne pour le **BASIC et le code machine**,
quelle que soit la taille du fichier (contrôle de flux par crédits).

## Utilisation

1. Sur l'Oric, lance la lecture :
   ```
   CLOAD""
   ```
   (le moteur cassette démarre, la ROM attend l'amorce). La **LED5** de la
   carte s'allume pendant le chargement.

2. Sur le PC, envoie le fichier :
   ```sh
   tools/send_tap.py monjeu.tap /dev/ttyUSB0
   ```
   (`pip install pyserial` si besoin ; le port par défaut est `/dev/ttyUSB0`.)

L'ordre est indifférent : le FPGA tamponne l'amorce jusqu'au démarrage du
moteur. À la fin, l'Oric affiche le nom du programme puis `Ready`. Lance-le
avec `RUN` (BASIC) — le code machine démarre souvent tout seul.

## Comment ça marche

- **Chemin de lecture** (déjà présent) : `tape_in` → **VIA CB1** → routine
  `CLOAD` de la ROM, qui mesure l'intervalle entre fronts (Timer 2).
- **Injecteur** (`rtl/tape_injector.v`) : modulation strictement conforme au
  générateur de référence `~/Oric1/src/io/cassette.c` :
  - trame de **14 bits**, LSB d'abord : start(0), 8 data, **parité impaire**,
    4 stop(1) ;
  - **amorce** de 64 trames de synchro `0x16`, puis les données ;
  - chaque bit = 2 demi-pulses, front montant toujours à +208 µs ; période
    bit `1` = 416 µs (courte), bit `0` = 624 µs (longue), seuil ROM 512 µs ;
  - la bande n'avance que quand le **moteur** (VIA PB6) est actif.
- **Contrôle de flux par crédits** : l'Oric consomme la bande à ~137 o/s,
  bien plus lentement que l'UART (115200). Le FPGA renvoie un octet de crédit
  (`0x5A`) sur `ftdi_rxd` pour chaque octet qu'il peut absorber ; le script PC
  envoie exactement un octet `.tap` par crédit → jamais de débordement, même
  pour un jeu de 48 Ko.

## Sauvegarde `CSAVE` → `.tap` (épopée CSAVE)

Le chemin inverse : l'Oric **sauvegarde** un programme sur cassette (`CSAVE`),
le FPGA **démodule** la forme d'onde et renvoie le `.tap` reconstruit au PC.

1. Sur le PC, arme la réception :
   ```sh
   tools/recv_tap.py monprog.tap /dev/ttyUSB0
   ```
2. Sur l'Oric :
   ```
   CSAVE"NOM"
   ```
   (le moteur démarre, la ROM bit-bange la forme d'onde sur **PB7**). Quand la
   sauvegarde se termine, le script écrit `monprog.tap` (relisible ensuite par
   `send_tap.py` ou un émulateur).

### Comment ça marche

- **Chemin d'écriture** (ROM) : `CSAVE` génère la forme d'onde sur **PB7** via le
  Timer 1 — mêmes trames 14 bits, amorce `0x16`, pulses 416/624 µs que la
  lecture.
- **Démodulateur** (`rtl/tape_demod.v`, miroir de `tape_injector.v` et portage
  du décodeur de référence `~/Oric1/src/io/cassette.c`) : ne compte que les
  **fronts montants** de PB7, mesure la période front-à-front, applique le seuil
  512 µs (< → `1`, > → `0`), puis réassemble l'octet par **chasse au start**
  (saute les stops `1`, premier `0` long = start, 8 bits data LSB d'abord, brûle
  une période de parité) — exactement comme `GetTapeByte` (`$E6C9`).
- **Sortie UART** : les octets décodés partent sur `ftdi_rxd` (priorité
  dump > SAVE > écran > crédits) ; `sav_capturing` coupe le streamer écran
  pendant la capture. Débit bande (~137 o/s) très inférieur à l'UART → aucun
  tampon.
- **Réception PC** (`tools/recv_tap.py`) : se resynchronise sur l'amorce
  `0x16…0x24` (écarte tout octet écran reçu avant), parse la structure des blocs
  (en-tête 9 o → adresses fin/début → nom → `fin-début+1` octets de données)
  pour connaître la fin exacte, puis écrit le `.tap`.

### Sauvegarde sur la carte SD (SAVE.TAP)

En parallèle de la voie UART, le FPGA peut écrire le `.tap` directement sur la
carte, dans un fichier **placeholder pré-créé** `SAVE.TAP` (racine de la carte,
taille max fixe — l'allocation FAT32 / la création d'entrée n'est pas faite,
seul le contenu est écrasé).

- `rtl/tape_saver.v` consomme les octets du démodulateur, les accumule dans un
  **double buffer ping-pong** (512 o) et les écrit bloc par bloc via
  `fat32.wblk` (même chemin que le write-back disque). Le dernier bloc est
  complété par des `0x00`.
- Le top **localise `SAVE.TAP`** par son nom 8.3 (balayage du listing fat32) et
  mux `fat32.wblk` entre le write-back disque et le saver. Si `SAVE.TAP` est
  absent, la save SD est simplement inhibée (la voie UART reste disponible).
- La taille de l'entrée de répertoire n'est pas encore mise à jour : `SAVE.TAP`
  conserve sa taille placeholder, mais le `.tap` reste auto-délimité par la
  structure de ses blocs (un lecteur conforme s'arrête au bon endroit).

### Tests

`make test-tape-demod` : boucle `tape_injector` → `tape_demod`, vérifie que les
octets décodés == amorce `0x16` + données envoyées, sur flux simple et
multi-blocs. (La modulation de l'injecteur est déjà validée sur carte contre la
vraie ROM CLOAD, ce qui fait de la boucle un test de fidélité du démodulateur.)

`make test-tape-saver` : chaîne complète `tape_injector → tape_demod →
tape_saver → fat32.wblk → sd_card_file`, joue une charge > 512 o (2 blocs,
exerce le ping-pong), relit `SAVE.TAP` et vérifie amorce + données + padding.

## Protocole UART

```
PC  -> FPGA : 0x01, len_lo, len_hi, <len octets .tap>
FPGA -> PC  : 0x5A  (un crédit par octet acceptable ; le PC répond 1 octet)
```
Pendant le mode cassette (`tape_active`), l'UART entrant est aiguillé vers
l'injecteur `.tap` et **non** vers le clavier série — les deux ne se marchent
pas dessus.

## Tests

`make test-tape` : le testbench redécode la forme d'onde produite (périodes
front-à-front → bits → trames) et vérifie l'amorce `0x16`, le framing
(start/parité/stop) et l'égalité données décodées = données envoyées, ainsi
que le nombre de crédits.

## Limites

- Taille ≤ 65535 octets (limite ROM Oric).
- Un seul fichier à la fois ; relance `CLOAD""` + le script pour le suivant.
- **Jeux à loader protégé/maison** (ex. `citadel.tap`, Loriciels 84 : bloc 1
  autorun qui recharge la suite via des points d'entrée INTERNES de la ROM,
  après vérification d'empreinte `$FFF9`/`$E4B6`) : ces jeux sont sensibles à
  la **révision exacte de la ROM**. Citadel connaît la 1.0 et la 1.1
  d'origine (`$E4B6=$A2`) mais PAS notre 1.1b (code décalé, `$E4B6=$8E`) →
  « Errors found » quel que soit le flux. **Vérifié en émulateur
  (2026-08-11)** : avec la ROM **1.0** ET l'amorce inter-blocs (celle que
  notre RTL insère — l'émulateur ne l'a pas, il a fallu la simuler dans le
  fichier), Citadel charge et tourne. → Prise en charge = **banque ROM 1.0
  sélectionnable sur BTN5** (US-ULA-NG.1) — **VALIDÉ SUR CARTE le
  2026-08-11** : Citadel charge ses 4 blocs jusqu'au « Choix des couleurs »
  sur la banque 1.0. Vérifier la banque active : `PRINT PEEK(#FFF9)`
  (1 = 1.1b, autre = 1.0 ; la bascule fait un warm-boot silencieux, pas de
  bannière). NB : le mode signal de la référence `~/Oric1` bénéficierait
  aussi de l'insertion d'amorce inter-blocs (amélioration à reporter).
