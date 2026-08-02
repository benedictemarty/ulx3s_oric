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
