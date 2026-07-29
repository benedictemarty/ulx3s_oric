# QUESTIONS / points à vérifier avant commande (Phase A)

Incohérences ou ambiguïtés relevées dans SPEC_NETLIST.md, avec
l'interprétation retenue (la plus sûre). AUCUNE modification de netlist
n'a été faite : chaque net/broche/valeur vient de la spec.

## 1. J_EXP — sens de numérotation le long du bord
La spec définit « position k (1..17) : avant = 2k, arrière = 2k-1 » mais
ne dit pas si k=1 est en HAUT ou en BAS du bord droit.
**Retenu : k=1 en haut (y minimal), k=17 en bas.** Si la LOCI réelle est
numérotée dans l'autre sens, il faut miroiter le peigne (1 ligne à changer
dans gen_pcb.py : `y0` / signe du pas). ⚠️ À CONFIRMER par mesure sur la
LOCI réelle (la spec elle-même l'exige), ainsi que le pas de 2,54 mm.

## 2. J_EXP — retrait de 0,05 mm par rapport au bord
Les doigts font 6,00 mm de long mais s'arrêtent à 0,05 mm du bord
théorique (demi-épaisseur du trait Edge.Cuts) pour satisfaire le DRC.
Sans effet pratique : le biseau 45° de JLCPCB entame de toute façon le
bord sur ~0,5 mm.

## 3. K1 — « AQY212GH (DIP-4 CMS) » : contradiction THT/CMS
AQY212GH est un boîtier DIP-4 traversant ; les variantes CMS sont
AQY212GHA (pattes coupées) / AQY212GHAX (gull-wing, LCSC C719739).
La spec demande « DIP-4 CMS » avec l'empreinte
`Package_DIP:DIP-4_W7.62mm (ou SOP-4)`.
**Retenu : DIP-4_W7.62mm traversant (1er choix explicite de la spec).**
Conséquence : K1 n'est PAS assemblable par JLC en « assemblage top SMD »
(à souder à la main, ou passer sur AQY212GHAX + empreinte SMD).

## 4. J_CAS — empreinte DIN-7 femelle 270° créée par script
Aucune empreinte DIN 41524 7 broches dans les bibliothèques KiCad.
Créée par script : 7 pastilles THT Ø2,6 mm / perçage 1,4 mm sur un arc de
270°, cercle de broches Ø7,0 mm (DIN 45329), 45° entre broches, ordre
physique 6-1-4-2-5-3-7
(broche 2 au centre de l'arc), ouverture vers le bord haut de la carte.
**À VALIDER mécaniquement contre le connecteur réellement acheté**
(position des pattes de fixation, sens avant/arrière du brochage vu côté
soudure, diamètre des broches). Aucun trou de fixation ajouté faute de
référence constructeur dans la spec.

## 5. J_SND — broche 2 non spécifiée
La spec ne définit que J_SND.1 = SOUND (vers DIN4). **Retenu :
J_SND.2 = GND** (retour audio), interprétation la plus sûre.

## 6. J_PWR — 3e contact du jack (coupure) non spécifié
L'empreinte BarrelJack_Horizontal a 3 pastilles (1=centre, 2=manchon,
3=contact de coupure). La spec ne mentionne que centre=+5V et GND.
**Retenu : pastille 3 laissée non connectée** (le manchon reste GND en
permanence). Vérifier la mécanique du jack acheté (5,5/2,1) vs empreinte
générique KiCad.

## 7. LM393 — comparateur 2 : « entrées (5,6) à GND »
Appliqué tel quel (5 et 6 à GND, 7 NC). Remarque (non corrigée, netlist
respectée) : avec IN+=IN-=0 V la sortie du comparateur inutilisé est
indéterminée ; sans conséquence car la broche 7 est NC. Aucun découplage
100 nF dédié au LM393 dans la spec (C3..C14 réservés aux TXS) ; C16
(10 µF, 3V3) est placé à proximité relative.

## 8. Références LCSC
Vérifiées en ligne (07/2026) :
- TXS0108EPWR (TSSOP-20) = **C17206** (le « C17197? » de la spec ne
  correspond pas : C17206 confirmé sur jlcpcb.com/lcsc.com).
- LM393DR (TI, SOIC-8) = **C67470**.
- AQY212GHAX (CMS) = C719739 ; AQY212GHA = C135778 ; le AQY212GH DIP
  exact n'a pas de code C confirmé → **TBD** dans la BOM.
- Passifs : voir BOM (C25804, C21190, C25803, C23179, C14663, C15849,
  C15850) — codes « basic parts » usuels, à re-vérifier au moment de la
  commande (stock/statut basic évolutif).
- Connecteurs THT (headers, jack, DIN) : non assemblés par JLC → TBD.

## 9. CPL / rotations JLCPCB
Les rotations du CPL sont les angles KiCad. JLCPCB ré-oriente parfois les
TSSOP/SOIC de ±90°/180° : vérifier l'aperçu de placement (rendu 3D) sur
le site JLC avant de valider la commande d'assemblage.

## 10. Peigne et « pas à confirmer »
La spec exige elle-même la confirmation du pas (2,54 mm) et de la
géométrie des doigts par mesure sur la LOCI réelle avant envoi en
fabrication. Fichiers générés avec : pas 2,54 mm, doigts 1,6 × 6 mm,
masque ouvert des deux côtés, ENIG + biseau 45° en option de commande.
