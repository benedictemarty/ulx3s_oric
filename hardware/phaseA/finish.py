#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Finalisation : purge des pistes, import de la session R2 complète,
remplissage des zones, bilan de connectivité. À lancer après fr_r2."""
import pcbnew
import import_ses_lib as lib  # noqa: F401  (si factorisé un jour)

BOARD = "phaseA.kicad_pcb"
SES = "phaseA_r2.ses"

import re
import importlib.util
spec = importlib.util.spec_from_file_location("imp", "import_ses.py")

# On réutilise import_ses.py mais en purgeant d'abord et en visant SES R2 :
b = pcbnew.LoadBoard(BOARD)
for t in list(b.GetTracks()):
    b.Remove(t)
pcbnew.SaveBoard(BOARD, b)
print("pistes purgees")

src = open("import_ses.py").read().replace('SES = "phaseA.ses"',
                                           'SES = "phaseA_r2.ses"')
exec(compile(src, "import_ses_r2", "exec"))
