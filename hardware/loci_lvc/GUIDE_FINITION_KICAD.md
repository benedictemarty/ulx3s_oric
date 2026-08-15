# Guide de finition dans KiCad — `loci_lvc_6l2` (25 liaisons)

But : partir du board **`loci_lvc_6l2.kicad_pcb`** (routé à 90 %, 0 violation) et
finir à la main les **11 signaux + 14 masses** restants, pour obtenir un board
**0 non-connecté, 0 violation**, prêt à commander.

Temps estimé : 30–45 min. Aucune expérience KiCad préalable requise — suis les
étapes.

---

## 0. Ouvrir le board
1. Installer **KiCad 9** (kicad.org).
2. Ouvrir **`loci_lvc_6l2.kicad_pcb`** (double-clic, ou KiCad → *Éditeur de PCB*).
3. Menu **Affichage → repère** : tu vois la carte (120×50 mm), les 5 puces, le
   peigne à droite, le connecteur en bas à gauche.

Les liaisons **non finies** apparaissent comme de **fines lignes blanches**
(le « chevelu » / ratsnest). Il y en a 25.

---

## 1. Coudre les 14 masses (le plus simple — commence par ça)
Chaque masse manquante = un pad GND à relier aux plans internes.

Pour **chaque** fine ligne blanche qui part d'un pad **GND** :
1. Touche **`V`** (pose un via) **juste à côté du pad** (dans une zone dégagée,
   0,5–1 mm du pad), puis clique. Le via traverse les plans GND internes → le pad
   est relié.
2. Si le via est trop près d'autre chose, KiCad le refuse (croix rouge) : déplace-le
   d'un poil.

💡 Astuce : règle le via par défaut à **0,6 mm / perçage 0,3 mm**
(*Préférences → Règles de conception*), c'est conforme.

À la fin, **Édition → Remplir toutes les zones** (`B`) : les masses se connectent.

---

## 2. Router les 11 signaux (sur les couches internes libres In2/In3)
Nets concernés (approx.) : des `A5V*`, `D5V*`, `D*`, quelques contrôles.

Pour **chaque** fine ligne blanche entre **deux pads de signal** :
1. Sélectionne la couche **In2.Cu** (menu déroulant des couches, en haut, ou touche
   `+`/`-` pour changer de couche active).
2. Touche **`X`** (router une piste), clique sur le **premier pad**, tire la piste
   vers le **second pad**, double-clic pour finir.
3. Si ça bloque (pad recouvert d'une piste), pose un **via `V`** juste à côté du pad
   pour **descendre sur In2.Cu**, puis route sur In2 jusqu'à l'autre pad (remonte
   avec un via si besoin).
4. Si In2 est encombré à un endroit, utilise **In3.Cu** (change de couche en cours
   de route avec `V`).

Largeur de piste : **0,2 mm** suffit (les couches internes sont peu chargées).

---

## 3. Vérifier (DRC)
1. **Inspecter → Vérificateur de règles de conception (DRC)**.
2. Clique **Exécuter le DRC**.
3. Objectif : **0 élément non connecté** et **0 violation**.
   - S'il reste des non-connectés : une fine ligne blanche subsiste → route-la.
   - S'il reste des violations (clearance, etc.) : double-clic dessus, KiCad zoome
     sur le problème → écarte la piste/le via fautif.

---

## 4. Générer les fichiers de commande
Une fois **DRC propre** :
1. **Fichier → Fabrication → Gerbers** : coche toutes les couches cuivre + masque +
   sérigraphie + contour ; **Générer**. Puis **Générer les fichiers de perçage**.
2. **Fichier → Fabrication → Position des composants** (pour l'assemblage) :
   format CSV.
3. **BOM** : voir `SPEC_NETLIST.md` (composants + réfs LCSC).
4. Zippe les Gerbers + drill → upload sur **JLCPCB** (choisir **6 couches**),
   ajouter BOM + placement pour le service **PCBA**.

---

## En cas de blocage
- Un pad **vraiment inatteignable** : route-le sur **B.Cu** (couche du dessous) en
  posant un via à côté, puis remonte au pad destination par un autre via.
- Reviens vers moi avec une **capture d'écran** de la zone bloquée : je te dirai
  précisément où passer.

> Rappel : le fichier de départ `loci_lvc_6l2.kicad_pcb` est déjà routé à 90 % et
> **sans aucune erreur** — tu ne fais qu'ajouter les 25 dernières liaisons.
