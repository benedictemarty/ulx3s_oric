# Clavier USB physique (port US2) et bascule QWERTY / AZERTY

Un clavier USB branché sur le port **US2** de l'ULX3S est décodé par
`usb_hid_host` (boot-protocol, low-speed), synchronisé, puis traduit en
positions de la matrice 8×8 de l'Oric par `rtl/oric_keyboard.v`.

État : **validé sur carte** (frappe réelle confirmée, 2026-08-02).

> ⚠️ `usb_hid_host` ne gère que les claviers *boot protocol* low-speed ;
> certains claviers ne répondent pas. `led[1]` s'allume quand un clavier est
> détecté, `led[2]` en cas d'erreur de connexion.

## Deux dispositions, un bouton

Le bouton **`BTN6` (RIGHT)** bascule la disposition à chaque appui
(anti-rebond ~10 ms + front). L'état est mémorisé jusqu'au prochain appui ou
reset.

| `led[4]` | Disposition | Décodage |
|----------|-------------|----------|
| éteinte  | **QWERTY** (défaut) | positionnel : le scancode HID → position matrice |
| allumée  | **AZERTY** français | `(scancode, Shift) → ASCII FR → matrice` |

Le core démarre toujours en QWERTY.

## Mode AZERTY — détails

En AZERTY, le Shift physique **choisit le glyphe** (il n'est plus reporté
directement) puis la table ASCII→Oric (`rtl/ascii2oric.vh`, la même que le
clavier série) décide du Shift Oric éventuel.

- **Lettres** permutées comme sur un clavier français : `A`↔`Q`, `Z`↔`W`, et
  `M` à sa place AZERTY.
- **Rangée du haut : chiffres directs** (choix pratique pour le BASIC) :
  sans Shift on obtient `1 2 3 4 5 6 7 8 9 0`, avec Shift les symboles
  (`& " ' ( - _ …`).
- **Symboles** générant un Shift Oric automatiquement : ex. `(` = Shift+9,
  `?` = Shift+/, `%`, `<` / `>` (touche ISO), etc. Le Shift synthétisé est
  séquencé (voir plus bas) pour être fiable.
- **Touches non alphanumériques** (Entrée, Échap, flèches, espace, Ctrl,
  Funct) : identiques dans les deux modes (repli positionnel).
- **Glyphes accentués / hors ASCII** (`é è à ç ù ° £ § µ`, accents morts) :
  indisponibles — l'Oric ne dispose pas de ces caractères, la touche ne
  produit rien dans cet état (aucun repli QWERTY parasite).

## Shift synthétisé : séquencement

Un Shift dérivé du même scancode que la touche monterait exactement en même
temps qu'elle ; le scan clavier de la ROM Oric attrape alors parfois la
touche sans le Shift (symptôme observé : `&` donnant par moments `7`). Les
glyphes AZERTY nécessitant un Shift Oric sont donc séquencés comme un vrai
doigt : le Shift **précède** la touche (LEAD ~20 ms), la **maintient**
(HOLD, minimum garanti), puis la **prolonge** au relâché (TAIL ~10 ms).
Durées réglables via les paramètres `LEAD_TICKS` / `HOLD_MIN_TICKS` /
`TAIL_TICKS` de `oric_keyboard`. Le Shift *physique* (QWERTY) et le clavier
série gardent leur comportement direct.

## Tests

`make test-azerty` vérifie les permutations de lettres, les chiffres en
Shift, les symboles à Shift Oric, la non-propagation du Shift physique sur
une lettre, le repli positionnel (Entrée) et la non-régression QWERTY.
`make test-keyboard` couvre la matrice QWERTY de base.
