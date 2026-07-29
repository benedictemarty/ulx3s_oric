# Phase A — Bandeau LOCI : régénération des fichiers de fabrication
# Cibles : pcb (génération + routage), drc, gerbers, fab (BOM/CPL), all

PCB      = phaseA.kicad_pcb
GEN      = gen_pcb.py
ROUTE    = route.py
JAR      = freerouting.jar

.PHONY: all pcb route drc gerbers fab clean

all: pcb drc gerbers fab

# Génère la carte non routée puis la route (freerouting + import SES,
# puis complément scripté si nécessaire) — voir route.py.
pcb:
	python3 $(GEN) $(PCB)
	python3 $(ROUTE) $(PCB)

drc:
	kicad-cli pcb drc --severity-error --exit-code-violations \
	  --format json -o drc.json $(PCB)
	@python3 -c "import json;d=json.load(open('drc.json'));\
e=[v for v in d['violations'] if v['severity']=='error'];\
print('DRC erreurs:',len(e),'; non connectés:',len(d['unconnected_items']))"

gerbers:
	rm -rf gerbers && mkdir -p gerbers
	kicad-cli pcb export gerbers -o gerbers/ \
	  -l F.Cu,B.Cu,F.Paste,B.Paste,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask,Edge.Cuts \
	  --subtract-soldermask $(PCB)
	kicad-cli pcb export drill -o gerbers/ --format excellon \
	  --drill-origin absolute --excellon-separate-th $(PCB)

fab:
	python3 make_fab.py $(PCB)

clean:
	rm -rf gerbers drc.json drc0.json phaseA.dsn phaseA_fr.dsn phaseA.ses \
	  freerouting*.log
