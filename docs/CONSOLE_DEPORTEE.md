# Console déportée (écran + clavier sur PC, sans moniteur ni clavier)

Piloter l'Oric sur ULX3S **sans écran HDMI ni clavier USB** : le FPGA streame
le framebuffer par l'UART FTDI (US1) et reçoit les frappes par la même liaison.

## Principe

- `rtl/screen_stream.v` envoie en boucle le **framebuffer** 240×224×4 bits
  (le rendu final de la ULA → couvre **TEXT, HIRES et modes mixtes**).
  Trame : en-tête `AA 55 F0 0F` puis 26880 octets (2 pixels/octet).
- `rtl/framebuffer.v` : lecture par le **port d'écriture** aux cycles où la
  ULA n'écrit pas (`rd_valid`) → BRAM 2 ports, pas de duplication.
- Clavier : `rtl/key_injector.v` (déjà présent) injecte l'ASCII reçu.
- **UART FTDI à 1 Mbaud** (`FTDI_BAUD` dans `top_ulx3s.v`) : ~3-4 images/s
  en plein écran, texte fluide. Priorité UART : dump (BTN2) > cassette/
  chargeur > écran (l'écran ne streame qu'à l'idle).

## Outils PC

- **`tools/screen_gui.py`** (recommandé) : fenêtre Tkinter WYSIWYG, clavier
  capturé dans la fenêtre. `python3 tools/screen_gui.py [-z ZOOM]`.
- `tools/screen_view.py` : rendu ANSI dans le terminal (`-k` = clavier ;
  `--snap out.png` = capture fidèle). Sensible à la taille du terminal.

## À savoir

- Tous les outils PC sur le FTDI utilisent désormais **1 Mbaud**
  (`send_tap.py`/`dump_sd.py` : ajouter `--baud 1000000`).
- Ne pas ouvrir deux outils sur `/dev/ttyUSB0` en même temps (accès exclusif).
