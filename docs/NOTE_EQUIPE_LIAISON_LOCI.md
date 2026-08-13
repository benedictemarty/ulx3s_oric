# Note à l'équipe — liaison physique vers la LOCI (berceau ULX3S) + revue croisée

**De :** bmarty · **Date :** 2026-08-13 · **Objet :** convergence avec
`PORT_EXTENSION.md`, apport d'un **berceau PCBA**, et 2 points à corriger.

En marge du projet **NetMaze** (client Oric qui parle à l'ACIA `$0380`), j'ai
mené une étude indépendante de raccordement **Oric-émulé-sur-ULX3S ↔ LOCI réelle**
(dossier `~/NetMaze/ulx3s2Loci/`). Elle **recoupe très largement** notre
`docs/PORT_EXTENSION.md` et `rtl/expansion_port.v` déjà en place. Cette note fait
le point : ce qui se valide mutuellement, ce que j'apporte de neuf, et 2 détails
à corriger.

---

## 1. Validation croisée (rassurant : deux analyses indépendantes concordent)

- **Brochage du connecteur 34 points** : identique. Je l'ai reconstruit par
  connectivité du **schéma réel de la LOCI 1.3** (`sodiumlb/loci-hardware`,
  `SCH_loci-1.3.json`) → mêmes affectations que notre table (pins 33/34 = +5 V/GND).
- **Adaptation de niveau** : même conclusion — **74LVC (DIR//OE), TXS0108E
  proscrit** (auto-sens → contention avec le 74LVC4245A push-pull de la LOCI,
  sensible à la capacité). Confirmé aussi par la BOM réelle de la LOCI
  (U3 = 74LVC4245A, buffers Schmitt 5 V-tolérants en entrée).
- **`/OE` du transceiver data** : même piège identifié — `/OE = /IO` **ne suffit
  pas** (la LOCI sert sa ROM menu en `$C000–$FFFF` via /ROMDIS+/MAP, hors page
  I/O). Notre solution (`/XCVR_OE` passant pendant Φ2, ou masse) est la bonne.
- **Architecture d'inhibition** : `oric_atmos.v` gère déjà proprement le partage
  du bus — ACIA interne en **`$031C–$031F`**, microdisc `$0310–$031B`, et
  `sel_ext = sel_io & ~sel_via & ~sel_acia & ~sel_md`, le tout **inhibé par
  `ext_ioctl`**. Donc **aucune collision** avec la LOCI en `$0380` : elle tombe
  dans `sel_ext`, et /IOCTRL retire les périphériques internes. 👍

---

## 2. Apport nouveau : un **berceau PCBA** (au lieu du câblage Dupont)

`PORT_EXTENSION.md` cible le **câblage Dupont**. Pour fiabiliser (et « ne pas se
tromper » : une inversion 5 V→GPIO grille l'ECP5), je propose une **petite carte
berceau assemblée** (SMD monté en usine, type JLCPCB PCBA) sur laquelle **l'ULX3S
s'enfiche** et où la LOCI arrive par nappe IDC 34 — **zéro fil volant**.

**Cotes mécaniques relevées** (extraction du `.kicad_pcb` d'`emard/ulx3s`,
empreintes `Socket_Strip_Angled_2x20`, vérifiées dans le contour) :

| Cote | Valeur |
|---|---|
| Connecteurs J1/J2 | 2×20, **pas 2,54 mm**, rangées verticales |
| **Entraxe centre-à-centre J1↔J2** | **88,90 mm** (= 35 × 2,54, alignés en Y) |
| Rangées internes / externes | 86,36 / 91,44 mm |
| Longueur d'un connecteur | 48,26 mm |
| Carte ULX3S | ≈ 93,98 × 50,8 mm |

⚠️ **Piège mécanique** (note du schéma ULX3S) : la numérotation 1–40 vaut pour
l'embase **femelle coudée** ; pour une embase **mâle verticale** (berceau),
**échanger pairs/impairs** — ou câbler par **nom de net GPx/GNx**.

Le berceau reprend exactement notre schéma : **2× 74LVC4245A dual-supply**
(le même que la LOCI, réf LCSC **C6091**), pull-ups, découplage, cavaliers
(source 5 V, `/OE` masse↔`/XCVR_OE`). Détails et BOM à réfs LCSC :
`~/NetMaze/ulx3s2Loci/docs/carte-interface-pcb.md`.

---

## 3. Deux points à corriger / clarifier (revue de `rtl/`)

1. **`gp[16]` / `gn[16]` = zone ADC « évitée »** — dans `top_ulx3s.v` le
   transceiver data est piloté par `pin_xcvr_dir = gp[16]` et
   `pin_xcvr_oe_n = gn[16]`, or le commentaire juste au-dessus dit
   « gp/gn[11..17] évitées : partagées avec l'ESP32 et l'ADC », et le `.lpf`
   confirme **gp[16]=N16 (ADC AIN5)**, **gn[16]=M17 (ADC AIN4)**.
   → Est-ce intentionnel (ADC non utilisé, broches libres) ? Sinon, déplacer
   `xcvr_dir`/`xcvr_oe_n` vers 2 nets hors 11..17 (p. ex. `gp/gn[23]`, libres).
   À trancher **avant** de figer le typon du berceau.

2. **Commentaire obsolète dans `expansion_port.v`** — l'en-tête mentionne encore
   « câblage Dupont + **TXS0108E** » (lignes ~10 et ~ chronologie), ce qui
   contredit la décision **anti-TXS0108E** de `PORT_EXTENSION.md`. À aligner pour
   éviter qu'un contributeur reparte sur le TXS0108E.

---

## 4. Mapping GPIO — `top_ulx3s.v` fait foi

Ma proposition initiale (côté `ulx3s2Loci`) plaçait les signaux différemment ;
**la référence est le HDL réel** (`top_ulx3s.v`) :

- `pin_a = {gp[22:18], gp[10:0]}` → **A0..A10** = gp[0..10], **A11..A15** = gp[18..22]
- `pin_d = gn[7:0]` → **D0..D7**
- `gn[8]=R/W`, `gn[9]=Φ2`, `gn[10]=/IO`
- `gn[18]=/RESET`, `gn[19]=/IRQ`, `gn[20]=/ROMDIS`, `gn[21]=/MAP`, `gn[22]=/IOCTRL`
- `gp[16]=XCVR_DIR`, `gn[16]=/XCVR_OE` (cf. point 3.1)

→ J'**aligne** `ulx3s2Loci/docs/mapping-gpio-contraintes.md` et le typon du berceau
sur cette table (et non l'inverse).

---

## 5. Livrables disponibles (dossier `~/NetMaze/ulx3s2Loci/`)

- `docs/etude-liaison-physique.md` — signaux/directions, **brochage CN1** reconstruit
  du schéma LOCI, niveaux, timing.
- `docs/carte-interface-pcb.md` — **berceau PCBA** (cotes, BOM LCSC, fichiers PCBA).
- `docs/mapping-gpio-contraintes.md` — mapping signal→GPIO→**bille ECP5** + `.lpf`.
- `docs/plan-physique-fils-volants.md` — variante breadboard (validation rapide).

---

## 6. Proposition de suite

1. Trancher le **point 3.1** (gp/gn[16] vs ADC).
2. Aligner le mapping `ulx3s2Loci` sur `top_ulx3s.v` (**§4**).
3. Router le **berceau** (EasyEDA → PCBA) avec l'entraxe 88,90 mm.
4. Bring-up : ULX3S enfiché + nappe LOCI, Φ2 nominal (marges OK à 1 MHz, la LOCI
   ayant son ADJ_SCAN).

Retours bienvenus, surtout sur le point 3.1.

— bmarty
