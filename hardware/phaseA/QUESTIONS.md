# QUESTIONS / points à vérifier avant commande (Phase A)

Incohérences ou ambiguïtés relevées dans SPEC_NETLIST.md, avec
l'interprétation retenue (la plus sûre). AUCUNE modification de netlist
n'a été faite : chaque net/broche/valeur vient de la spec.

## 1. J_EXP — sens de numérotation le long du bord
La spec définit « position k (1..17) : avant = 2k, arrière = 2k-1 » mais
ne dit pas si k=1 est en HAUT ou en BAS du bord droit.
**Retenu : k=1 en haut (y minimal), k=17 en bas.** Si la LOCI réelle est
numérotée dans l'autre sens, il faut miroiter le peigne (1 ligne à changer
dans gen_pcb.py : `y0` / signe du pas). ⚠️ Sens à CONFIRMER face au
connecteur Amphenol de la LOCI (le pas 2,54 mm et l'épaisseur 1,6 mm ont
été confirmés par bmarty le 2026-07-29 — note dans la spec révisée).

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
Créée par script : 7 pastilles THT Ø2,4 mm / perçage 1,3 mm sur un arc de
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

## 10. Révisions de spec intégrées en cours de génération (2026-07-29)
- **R8 1 MΩ (hystérésis LM393, OUT→IN+)** : intégré. R8 avait été ajouté
  directement dans phaseA.kicad_pcb à (55,5;13,2), en court-circuit sur
  U7 pad 8 (+3V3) : replacé en (59;21) par gen_pcb.py.
- **J_ULX_A ordre révisé** (1..8=contrôle, 9=OE_EN, 10..17=D0..D7,
  18..33=A0..A15) : intégré dans gen_pcb.py, carte re-routée.
- **Pas du peigne confirmé** (Amphenol 34 pts, 2,54 mm) : la question ne
  reste ouverte que pour le SENS de numérotation (§1).

## 11. Largeur des pistes d'alimentation : 0,4 mm (au lieu de 0,5)
Le guide de routage indiquait 0,5 mm pour +5V/+3V3. Une piste de 0,5 mm
ne peut pas entrer dans un pad TSSOP-20 au pas 0,65 mm en respectant
l'isolation de 0,2 mm (0,65-0,25-0,2 = 0,20 mm : limite exacte, refusée
par le routeur). Les pistes d'alim sont donc routées à **0,4 mm**
(chutes de tension négligeables : TXS0108E ≈ quelques mA par rail).
La netclass « Power » du board reste déclarée à 0,5 mm.
