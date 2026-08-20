# Joystick USB → interface IJK (US3.3)

L'ULX3S accepte un **gamepad USB HID** et le présente à l'Oric comme une
**interface joystick IJK** — l'adaptateur le plus courant sur Oric. Les jeux qui
lisent l'IJK (via le port imprimante) voient directement le gamepad.

## Utilisation

Branche un gamepad USB (même port que le clavier USB). Dès qu'il est reconnu
(`typ==3` côté HID), la présence IJK est signalée et les directions/boutons sont
actifs. Pas de bascule à faire : clavier et joystick coexistent.

- **Directions** : croix/pad → RIGHT/LEFT/UP/DOWN.
- **Feu** : bouton **A** ou **B**.

## Comment ça marche

L'IJK vit sur le **port imprimante = VIA Port A**. Il tire des lignes de Port A
vers le bas (actif bas) quand il est activé et sélectionné :

- **Activation** : PB4 (strobe imprimante) piloté en sortie et à l'état bas.
  Comme `pb_out = orb | ~ddrb`, cela équivaut à `pb_out[4] == 0`.
- **Sélection du stick** : bits 6-7 de la valeur pilotée sur Port A
  (`joysel = ora | ~ddra` = `pa_out` du VIA). bit6=1 → stick A ; bits 6 et 7 = 1
  → aucun ; bit6=0 → présence seule (stick B non câblé).
- **État** (actif bas) : bit0=RIGHT, 1=LEFT, 2=FIRE, 3=DOWN, 4=UP.
- **Présence** : bit 5 (0 = interface présente).

`rtl/joystick_ijk.v` (portage RTL de `oric_joystick_port_a_pins()` de
`~/Oric1/src/io/joystick.c`) produit la contribution `pins` de l'IJK, **combinée
par ET** avec l'entrée normale de Port A dans `oric_atmos.v` (pull-downs à
collecteur ouvert ; `0xFF` = neutre hors lecture joystick).

Côté entrée, le core `usb_hid_host` décode déjà le gamepad (`game_u/d/l/r`,
`game_a/b`). `top_ulx3s.v` câble ces sorties, dérive `fire = A|B` et
`present = (typ==3)`, les synchronise du domaine USB (12 MHz) vers le domaine
système (24 MHz) par double bascule, puis les passe à `oric_atmos`.

## Limites

- Un seul stick émulé (stick A ; stick B non câblé, conforme à la référence).
- Mapping fixe (croix + A/B). Pas de configuration des boutons pour l'instant.

## Tests

`make test-joystick` : `sim/tb_joystick_ijk.v` vérifie la contribution Port A
contre le comportement de référence — absence de gamepad, activation par PB4,
sélection de stick (aucun / stick A / présence seule), chaque direction et le
feu, puis toutes les entrées appuyées simultanément.
