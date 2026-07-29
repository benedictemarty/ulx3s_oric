# Clavier série depuis le PC (port US1)

Le câble USB de programmation (US1) transporte aussi une liaison série
FTDI ↔ FPGA. Le core écoute cette liaison à **115200 bauds, 8N1** et injecte
chaque caractère ASCII reçu dans la matrice clavier de l'Oric comme une vraie
frappe (~45 ms pressée, ~25 ms de pause, Shift automatique pour `!"#$%…`).

## Utilisation interactive

```sh
picocom -b 115200 /dev/ttyUSB0     # quitter : Ctrl-A Ctrl-X
# ou
screen /dev/ttyUSB0 115200         # quitter : Ctrl-A k
```

Tout ce que vous tapez arrive sur l'Oric. `Entrée` = RETURN, `Échap` = ESC,
`Retour arrière` = DEL.

## Coller / envoyer un programme BASIC

L'Oric absorbe ~14 caractères/s (frappe réaliste). Le tampon FPGA fait
256 octets : limitez le débit à l'envoi d'un fichier :

```sh
stty -F /dev/ttyUSB0 115200 raw
pv -qL 10 monprog.bas > /dev/ttyUSB0     # 10 octets/s, sûr
```

Sans `pv` : `while read -r l; do printf '%s\r' "$l"; sleep 3; done < monprog.bas > /dev/ttyUSB0`

## Correspondance des touches

Table positionnelle dérivée des tables ROM $FF70/$FFB0 (via la référence
`~/Oric1/src/io/keyboard.c`) : lettres, chiffres, ponctuation US, CR/LF
(dédupliqués), ESC, BS/DEL. Caractères non mappés (accents, tabulation…) :
ignorés silencieusement.

## Limites connues

- Pas de contrôle de flux matériel : au-delà de 256 caractères en attente,
  les suivants sont perdus (d'où la limitation de débit).
- CTRL+lettre n'est pas transmissible par ce canal en v1 (le terminal envoie
  des codes < 0x20 non mappés). Le clavier USB sur US2 reste la référence.
