# Gestion multibank « voie Telestrat fidèle » — conception

Objectif : remplacer le `oric_rom.v` à 2 banques figées par un **gestionnaire
multibank unifié** (`bank_window.v`) modelé sur le **Telestrat réel** : la fenêtre
`$C000-$FFFF` (16 Ko) commute entre **8 banques** hétérogènes (ROM **et** RAM),
sélectionnées par un **2ᵉ VIA** à `$0320`. Ce même mécanisme sert la roadmap
ULA-NG (US-ULA-NG.1/.5), la future ROM menu type LOCI, et le soft Telestrat
moderne (ORIX 2025+).

> Statut : **conception seule** (2026-08-17). Décision prise avec bmarty :
> **voie Telestrat fidèle** (pas le simple registre `NG_BANK`). Clean-room à
> partir de la spec confirmée (sources §7) — **pas** de reprise du code GPL-2.0
> de BigMist, utilisé seulement en validation croisée conceptuelle.

---

## 1. Spec Telestrat confirmée (sources faisant autorité, §7)

- Fenêtre commutée : **`$C000-$FFFF`, 16 Ko**, **8 banques** (0..7).
- **Sélecteur** : **3 bits de poids faible du port A d'un 2ᵉ VIA 6522**
  (`PA0-PA2`), mappé **`$0320-$032F`**. Écrire le n° de banque → cette banque
  apparaît en lecture à `$C000`.
- **Banque 0 = overlay RAM** = les **16 Ko hauts de la RAM interne 64 Ko**.
  C'est là que tourne **STRATSED** (le DOS, chargé depuis disquette).
- Banques 1..7 = **ROM ou RAM**. Affectations standard :
  - **Bank 7 = TELEMON** (moniteur/OS, **obligatoire pour booter**, porte le
    vecteur reset `$FFFC`).
  - Bank 6 = HYPERBASIC · Bank 5 = TeleAss · Bank 3 = Telematic.
  - Cartouche = concaténation **BANK7+BANK6+BANK5+BANK4**.
- **Bootstrap** : rend **`/MAP` actif** → bascule en overlay RAM (bank 0), y
  déplace l'essentiel du DOS.
- `$0000-$BFFF` (48 Ko) = **RAM fixe**, jamais commutée.

### Réponse à « si ROM, alors RAM aussi ? » → OUI
La RAM **est** dans le même mécanisme : bank 0 = RAM (overlay), et d'autres
banques peuvent être de la RAM. Le core FPGA Telestrat de référence (BigMist)
embarque **128 Ko de RAM** → RAM bankée au-delà de 64 Ko. Une seule fenêtre,
banques hétérogènes.

---

## 2. Le module unifié `bank_window.v`

Idée : les 8 banques ne sont **pas** homogènes. Chaque banque a un **type**
(`ROM` ou `RAM`) qui décide la **source de lecture**. Les **écritures** dans
`$C000-$FFFF` vont **toujours en RAM** (overlay), quelle que soit la banque lue.

| Banque | Type | Lecture `$C000` | Écriture `$C000` |
|---|---|---|---|
| 0 | **RAM** (overlay) | RAM overlay | RAM overlay |
| 7 (TELEMON) | ROM | ROM BRAM | → RAM overlay |
| 6/5/3 (HYPERBASIC/…) | ROM | ROM BRAM | → RAM overlay |
| autres | RAM ou ROM | selon type | → RAM overlay |

Interface pressentie :
```
module bank_window #(
    parameter NBANKS = 8,
    parameter ROM_INIT_7 = "telemon.hex",   // boot
    parameter ROM_INIT_6 = "hyperbasic.hex",
    // ... init $readmemh par banque ROM
)(
    input             clk,
    input      [2:0]  bank_sel,    // <- PA0-PA2 du VIA-2 ($0320)
    input      [13:0] addr,        // A0..A13 dans la fenêtre 16 Ko
    input             we,          // écriture CPU dans $C000-$FFFF
    input      [7:0]  din,
    input             map_n,       // /MAP (bootstrap overlay)
    output     [7:0]  dout
);
```
- Table `is_ram[NBANKS]` : décrit quelles banques sont RAM.
- Lecture : `dout = is_ram[bank_sel] ? ram_bank[bank_sel][addr] : rom_bank[bank_sel][addr]`.
- Écriture : toujours vers `ram_overlay[addr]` (bank 0) — sémantique overlay
  Telestrat/Atmos, déjà modélisée `cpu|ram|rom|overlay` dans `~/Oric1`.
- `/MAP` : force la lecture sur l'overlay RAM pendant le bootstrap.

---

## 3. Intégration dans l'existant (changement minimal)

- **Remplace** `oric_rom.v` (2 banques 1.1b/1.0) par `bank_window.v`. Les 2 ROM
  actuelles deviennent 2 banques parmi 8 (compat ascendante : bank BASIC = défaut).
- **Ajoute un 2ᵉ VIA** (`via6522.v` déjà présent, réinstancier) décodé à
  **`$0320-$032F`** dans `oric_atmos.v` ; exporter `PA[2:0]` → `bank_sel`.
- Décodage `sel_rom`/overlay de `oric_atmos.v` **conservé** (la spec ULA-NG le
  demandait déjà) ; on branche la source ROM/RAM sur `bank_window`.
- Vecteur reset : au boot, `bank_sel = 7` (TELEMON) — ou banque BASIC en mode
  Atmos-compat. **À trancher** : boot Telestrat (bank 7) vs boot Atmos actuel.

### Réconciliation avec `NG_BANK $03E0` (épopée ULA-NG)
La décision antérieure (US-ULA-NG.1) logeait le sélecteur dans `NG_BANK
$03E0-$03EF`. **La voie Telestrat fidèle le remplace par le VIA-2 `$0320`
(PA0-2)** — c'est le registre historique, requis pour la compat binaire avec
STRATSED/HYPERBASIC/ORIX. `$03E0` peut rester un **alias/extension** NG optionnel,
mais le sélecteur **primaire** devient le VIA-2. *(décision à acter dans BACKLOG)*

---

## 4. Budget mémoire (à VÉRIFIER sur la 85F)

- 8 × 16 Ko = **128 Ko** d'espace bankable à `$C000`, en plus des 48 Ko de RAM
  fixe basse et de la RAM/vidéo/track-buffer déjà instanciés.
- L'ECP5-85F a ~**468 Ko d'EBR** (BRAM). Mettre 128 Ko de banques **entièrement
  en BRAM** en plus de l'existant est **probablement trop juste** → non vérifié.
- Pistes : ROM banks (init `$readmemh`) en BRAM ; **banques RAM en SDRAM**
  (l'ULX3S a 32 Mo SDRAM, non utilisée aujourd'hui — le design met la RAM Oric
  en BRAM). Migrer la RAM vers la SDRAM est un chantier à part. **À chiffrer.**

---

## 5. Ce que je ne sais pas encore (à lever, pas inventer)

1. **Détail des bits VIA-2** au-delà de PA0-2 (DDR, autres lignes de PA/PB pour
   MINITEL/MIDI). La sélection de banque = PA0-2 est confirmée ; le reste du VIA-2
   Telestrat (joysticks, périphériques) est hors périmètre banking.
2. **Séquence de boot exacte** (état de `/MAP` et `bank_sel` au reset matériel
   Telestrat, ordre du handover overlay). Confirmé qualitativement (/MAP actif →
   overlay), pas cycle-à-cycle.
3. **Budget BRAM/SDRAM réel** (§4) — mesure de synthèse requise.
4. Faut-il **plus de 8 banques** (extensions >128 Ko) ? Hors spec Telestrat de base.

---

## 6. Jalons proposés (sous l'épopée ULA-NG — voir BACKLOG)

- **US-MBANK.0** — cette note. **FAIT.**
- **US-MBANK.1** — `bank_window.v` (8 banques, `is_ram`, overlay write, `/MAP`)
  + testbench (lecture par banque, écriture→overlay, bascule `/MAP`). Remplace
  `oric_rom.v` en gardant le boot Atmos actuel (bank BASIC par défaut).
- **US-MBANK.2** — 2ᵉ VIA `$0320`, `PA0-2 → bank_sel`, décodage `oric_atmos.v`.
- **US-MBANK.3** — banques réelles : TELEMON (bank 7) + boot Telestrat optionnel,
  vecteur reset commuté. Nécessite les ROM Telestrat (droits/usage à cadrer).
- **US-MBANK.4** — banques RAM (overlay + RAM haute) ; décision BRAM vs SDRAM (§4).
- **US-MBANK.5** — validation carte : booter TELEMON/ORIX, `!DIR` STRATSED.

**Critère d'arrêt honnête** : si §4 montre que 128 Ko bankés ne tiennent pas sans
migrer la RAM en SDRAM, on livre d'abord le sous-ensemble ROM-only (banques ROM +
overlay 16 Ko), et la RAM haute suit après le chantier SDRAM.

---

## 7. Sources (état de l'art 2026, faisant autorité)

- **cc65 — Telestrat** : https://cc65.github.io/doc/telestrat.html
  (8 banques `$C000`, bank 0 = overlay RAM, banques ROM/RAM).
- **BigMist/Oric_Telestrat** (FPGA, GPL-2.0, VIA×2, ULA HCS, WD1793, **128 Ko
  RAM**) : https://github.com/BigMist/Oric_Telestrat — *validation croisée
  uniquement, clean-room, pas de reprise de code*.
- **Core MiSTer Telestrat** : https://forum.defence-force.org/viewtopic.php?t=2468
- **ORIX v2025.3** (OS Oric/Telestrat moderne) : https://orix-software.github.io/
- **OSDK memory map** : http://osdk.defence-force.org/index.php?page=documentation&subpage=memorymap
- Interne : `docs/LOCI_EMULATION.md` (banques LOCI `oric_bank0..3`, même idée),
  `~/Oric1` (modèle `cpu|ram|rom|overlay`).
