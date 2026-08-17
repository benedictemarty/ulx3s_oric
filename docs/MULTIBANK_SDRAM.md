# Banques ORIX en SDRAM — investigation budget (US-MBANK.4 amont)

Objectif : lever le **verrou budget** identifié dans `docs/MULTIBANK.md` §4 et
`docs/BACKLOG.md` (épopée MULTIBANK) — faire tenir les **7 banques ROM d'ORIX**
(112 Ko) + banques RAM, hors de la BRAM saturée, en s'appuyant sur la **SDRAM**
de l'ULX3S. Investigation demandée par bmarty (« budget/SDRAM d'abord »).

> Statut : **conception seule** (2026-08-17). Aucun RTL SDRAM ajouté à
> `ulx3s_oric`. Prérequis de l'épopée ORIX (boot bank 7 + CH376, cf. plus bas).

---

## 1. Le besoin (rappel, faits confirmés)

ORIX = **TELEMON 3.0**, réparti en **7 banques ROM de 16 Ko** (`orixbank1..7.rom`,
présentes dans `~/oricutron/roms/`), bank 7 = noyau bootable, appels par
`BRK_TELEMON` (cf. `~/cc65/asminc/telestrat.inc`). Plus bank 0 = overlay RAM.

Budget : 7×16 = **112 Ko** de ROM + 64 Ko RAM Oric + vidéo + track buffer.
L'EBR de la 85F (~468 Ko) est déjà bien entamée → mettre 112 Ko de banques **en
BRAM** est le point de rupture annoncé. **La SDRAM est la sortie.**

---

## 2. Actif réutilisable : le SDRAM d'oric2 (même carte)

`~/oric2/hdl/rtl/` fournit un sous-système SDRAM **mûr et validé au bring-up**
sur la **même ULX3S** (auteur **bmarty**, licence **EUPL-1.2**) :

| Fichier | Rôle |
|---|---|
| `sdram_ctrl.v` | contrôleur SDR JEDEC closed-page, 16-bit, adresse mot **25 bits (32 Mo)**, init + auto-refresh, timings paramétrables |
| `sdram_arbiter.v` / `_arbiter3.v` | arbitre multi-maîtres (priorité écran, verrou de rafale) |
| `ulx3s_sdram.lpf` | brochage SDR 16-bit ULX3S (F19 clk, P20 csn, …) |

Interface contrôleur : `cmd_valid/cmd_we/cmd_addr[24:0]/cmd_wdata[15:0]/
cmd_blen[9:0]` → `cmd_ready/cmd_accept/rd_valid/rd_data[15:0]`.

**Réutilisable tel quel** (c'est de l'infra ULX3S, pas la « chimère » 65C816/GPU
que la frontière `oric2`↔`ulx3s_oric` interdit de dupliquer). ⚠️ **Mixage de
licence** : ce(s) fichier(s) resteraient **EUPL-1.2** dans `ulx3s_oric` — à
assumer/documenter (en-têtes conservés).

---

## 2bis. MESURE DÉCISIVE (2026-08-17) — les banques tiennent en BRAM

⚠️ **Cette note part d'une hypothèse (« 112 Ko ne tiennent pas en BRAM ») qui
s'est révélée FAUSSE à la mesure.** Synthèse yosys du design complet :

- Occupation actuelle : **121 / 208 EBR** (120 DP16KD + 1 PDPW16KD) → **87 libres**.
- Une banque ROM 16 Ko octet = **8 EBR** → 7 banques ORIX = **56 EBR**.
- **121 + 56 = 177 / 208** → **ÇA TIENT**, ~31 EBR de marge.

**Conséquences :**
- **Toutes les banques ORIX vont en BRAM** → switch = changer quelle BRAM on lit
  = **instantané et fidèle** (trampolines TELEMON OK). Comme le vrai LOCI/Telestrat.
- L'architecture « banque active + DMA refill » des §3-4 ci-dessous est
  **ABANDONNÉE** pour les banques ROM (son défaut : switch trop lent pour les
  trampolines). `bank_backing.v` **n'est pas écrit**.
- La SDRAM (US-MBANK.4b, portée et testée) **reste disponible pour la RAM haute /
  banques RAM** futures qui dépasseraient la BRAM, mais **sort du chemin critique**
  des banques ROM ORIX.
- **Vrai prochain pas** : étendre `bank_window.v` à 8 banques BRAM + ROM ORIX
  (MBANK.3), switch instantané par `bank_sel`.

Les §3-7 ci-dessous sont **conservés pour mémoire** (raisonnement DMA/SDRAM), mais
ne sont plus le plan retenu pour les banques ROM.

## 3. Décision d'architecture — PAS de lecture SDRAM au fil de l'eau

Le bus 6502 à **1 MHz** exige la donnée `$C000` **dans le cycle** (échantillon à
t4, cf. `oric_atmos.v`). La SDRAM a une **latence variable** (ACTIVE→tRCD→CAS +
**collisions refresh**). Lire une banque directement en SDRAM à chaque accès =
risque de rater la fenêtre t4 (régression type bug `$0380` de la LOCI).

**Architecture retenue — banque active en BRAM, adossée SDRAM :**

```
   $C000-$FFFF lecture 6502  ─────►  BRAM « banque active » (16 Ko, 1 cycle)
                                          ▲  remplissage DMA (8192 mots)
   écriture bank_sel (VIA-2 $0320) ──► déclenche un refill depuis la SDRAM
                                          │
                        SDRAM  [bank0 | bank1 | ... | bank7 | RAM haute...]
                         (sdram_ctrl, 32 Mo — 8 banques = 128 Ko, négligeable)
```

- **Lecture** : toujours BRAM (vitesse pleine, zéro latence sur le bus).
- **Changement de banque** (écriture VIA-2 PA) : DMA recopie les 16 Ko de la
  banque SDRAM demandée → BRAM active. Coût payé **une fois par switch** (rare,
  piloté logiciel : trampolines TELEMON), pas à chaque accès.
- **Overlay/écritures `$C000`** : la banque active BRAM est aussi write-back vers
  SDRAM (banque RAM), ou reste l'overlay 64 Ko existant selon le type de banque.
- C'est **exactement** le modèle du firmware LOCI (`oric_bankN` = overlays 16 Ko
  swappés) — validé conceptuellement.

Compromis : un **switch de banque coûte ~8192 accès SDRAM** (~des µs). Acceptable
si les trampolines TELEMON ne swappent pas des milliers de fois/s. À mesurer.

---

## 4. Intégration dans `ulx3s_oric` — travaux identifiés

1. **Horloge SDRAM** : ajouter le domaine/pin `sdram_clk` (F19) + phase (le
   `ulx3s_sdram.lpf` d'oric2 donne le brochage). `top_ulx3s.v` n'est pas
   SDRAM-aware → ajout non trivial (PLL, contraintes).
2. **Porter** `sdram_ctrl.v` (+ éventuellement l'arbitre si plusieurs maîtres),
   en-têtes EUPL conservés.
3. **`bank_backing.v`** (neuf) : FSM DMA SDRAM→BRAM déclenchée par un changement
   de `bank_sel`, + BRAM « banque active » 16 Ko. Remplace/enveloppe le stockage
   de `bank_window.v` (dont l'interface de lecture ne change pas côté bus).
4. **Chargement initial** des 8 banques en SDRAM : depuis la carte SD (fat32
   existant) au boot, ou `$readmemh` en sim. Les ROM ORIX ne sont **pas**
   commitées (droits — comme `locirom`).

---

## 5. Ce que je ne sais pas encore (à lever, pas inventer)

1. **Timing réel du refill vs fréquence de swap TELEMON** : combien de bascules
   de banque/seconde ORIX fait-il ? Non mesuré. Si trop élevé, revoir (garder
   2-3 banques « chaudes » en BRAM ?).
2. **Collision refresh pendant un refill** : géré par `sdram_ctrl` (refresh à
   IDLE) mais impact sur la durée de refill à chiffrer.
3. **Fréquence SDRAM sûre** sur la carte (paramètres CAS/tRCD au bring-up oric2 —
   à reprendre, pas à deviner).
4. **Coexistence horloges** : le design vidéo/HDMI a ses PLL ; ajouter le domaine
   SDRAM sans casser le timing HDMI. Non évalué.

---

## 6. Prérequis amont (rappel épopée ORIX)

Cette note ne traite que le **budget mémoire**. Pour ORIX il reste, en parallèle :
- **Boot Telestrat (bank 7)** = mode commutable (US-MBANK.3, décidé par la cible ORIX).
- **CH376** : ORIX 3.0 lit le stockage via un **CH376** (FAT32 SD/USB, cf.
  `~/oricutron/UTILISATION_ORIX.md`) — périphérique neuf à émuler par-dessus le
  `fat32.v`/`sd_spi.v` existant ; **oricutron** en fournit un modèle de référence.

---

## 7. Jalons (raffine US-MBANK.4 + amorce l'épopée ORIX)

- **US-MBANK.4a** — ce doc : investigation SDRAM + architecture banque-active/DMA. **FAIT.**
- **US-MBANK.4b** — porter `sdram_ctrl.v` + `sdram_clk`/PLL + testbench SDRAM
  (réutiliser `~/oric2/hdl/sim/tb_sdram*.v` comme modèle) — **hors bus Oric**.
- **US-MBANK.4c** — `bank_backing.v` (BRAM active + DMA refill SDRAM) branché sous
  `bank_window`, testbench de swap ; boot Atmos inchangé (bank0 par défaut).
- **US-MBANK.4d** — charger les 8 banques en SDRAM depuis la SD (fat32) au boot.

Sources internes : `docs/MULTIBANK.md`, `docs/LOCI_EMULATION.md` (banques LOCI),
`~/oric2/hdl/rtl/sdram_ctrl.v` (EUPL, bmarty), `~/oricutron` (ORIX + CH376),
`~/oricutron/roms/orixbank*.rom`.
