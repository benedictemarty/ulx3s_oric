# COMMANDE JLCPCB — Phase A « Bandeau LOCI »

Fichiers à téléverser : archive zip du dossier `gerbers/`
(gerbers toutes couches + Edge.Cuts + perçage Excellon).

## Options PCB (obligatoires)

| Option | Valeur |
|---|---|
| Base Material | FR-4 |
| Layers | **2** |
| Dimensions | 160 × 50 mm |
| PCB Thickness | **1,6 mm** |
| Surface Finish | **ENIG** (obligatoire pour le peigne) |
| Gold Fingers | **Yes** |
| Bevel/Chamfer (gold fingers) | **45°** |
| Outer Copper Weight | 1 oz |
| Solder Mask / Silkscreen | au choix (vert/blanc par défaut) |
| Remove Order Number | conseillé : « Specify a location » impossible ici → « Yes » (payant) ou accepter le marquage |

Remarques :
- Le peigne (34 doigts, 2×17, pas 2,54 mm, doigts 1,6 × 6 mm sur F.Cu et
  B.Cu, masque ouvert) est au bord DROIT du contour. L'option « Gold
  Fingers + 45° bevel » s'applique à ce bord.
- ⚠️ Avant de payer : confirmer le pas de 2,54 mm et le sens de
  numérotation par mesure sur la LOCI réelle (voir QUESTIONS.md §1/§10).

## Options assemblage (SMT top uniquement)

| Option | Valeur |
|---|---|
| PCBA Type | Economic (si dispo) |
| Assembly Side | **Top** |
| BOM | `BOM.csv` |
| CPL (Pick & Place) | `CPL.csv` |

Composants assemblés (43 CMS top) : U1..U6 (TXS0108EPWR, C17206),
U7 (LM393DR, C67470), R_OE,R1..R7 (0603), C1..C14 (0603), C15,C16 (0805).

NON assemblés (à souder soi-même, lignes LCSC=TBD dans la BOM) :
- K1 AQY212GH (DIP-4 traversant — cf. QUESTIONS.md §3 ; variante CMS
  possible : AQY212GHAX = C719739 avec empreinte SOP/SMDIP),
- J_ULX_A (2×20), J_ULX_B (2×10), J_PRN (2×10), J_SND (1×2) : headers
  mâles 2,54 mm THT,
- J_PWR : jack alim 5,5/2,1 THT (type CUI PJ-102A ou équivalent),
- J_CAS : DIN-7 femelle 270° THT (valider l'empreinte mécanique du
  connecteur acheté avant commande, QUESTIONS.md §4).

## Vérifications au moment de la commande

1. Aperçu JLC : orientation des TSSOP/SOIC dans le rendu de placement
   (rotations CPL = angles KiCad ; corriger dans l'outil JLC si besoin).
2. Statut/stock des codes LCSC (vérifiés 07/2026) : C17206, C67470,
   C25804, C21190, C25803, C23179, C14663, C15849, C15850.
3. DRC de production JLC (min track/space 0,127 mm) : la carte est en
   0,25/0,2 mm — large marge.
