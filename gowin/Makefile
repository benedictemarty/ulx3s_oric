# Portage Tang Nano 20K (Gowin GW2AR-18) — chaîne libre
# yosys synth_gowin -> nextpnr-himbaechel (apicula) -> gowin_pack
# Prérequis : oss-cad-suite dans le PATH (ou outils équivalents).

DEVICE  = GW2AR-LV18QN88C8/I7
FAMILY  = GW2A-18C
TOP     = top_tangnano20k
CST     = tangnano20k.cst

CORE = ../rtl/oric_atmos.v ../rtl/oric_ula.v ../rtl/oric_ram.v \
       ../rtl/oric_rom.v ../rtl/via6522.v ../rtl/oric_keyboard.v \
       ../rtl/uart_rx.v ../rtl/key_injector.v ../rtl/tmds_encoder.v \
       ../third_party/jt49/hdl/jt49_bus.v ../third_party/jt49/hdl/jt49.v \
       ../third_party/jt49/hdl/jt49_cen.v ../third_party/jt49/hdl/jt49_div.v \
       ../third_party/jt49/hdl/jt49_eg.v ../third_party/jt49/hdl/jt49_exp.v \
       ../third_party/jt49/hdl/jt49_noise.v

GOWIN_RTL = top_tangnano20k.v rtl/video_576p.v rtl/hdmi_tx_gowin.v \
            rtl/gowin_rpll.v

all: build/oric_tn20k.fs

build/oric_tn20k.json: $(GOWIN_RTL) $(CORE) ../roms/basic11b.hex
	mkdir -p build
	cp ../roms/basic11b.hex build/
	# ALU d'Arlet renomme : collision avec la primitive ALU de Gowin
	sed 's/\bALU\b/M6502_ALU/g' ../third_party/verilog-6502/cpu.v > build/cpu_gowin.v
	sed 's/\bALU\b/M6502_ALU/g' ../third_party/verilog-6502/ALU.v > build/alu_gowin.v
	cd build && /usr/local/bin/yosys -q -p "synth_gowin -top $(TOP) -json oric_tn20k.json" \
	  cpu_gowin.v alu_gowin.v $(addprefix ../,$(GOWIN_RTL)) $(addprefix ../,$(CORE))

build/oric_tn20k_pnr.json: build/oric_tn20k.json $(CST)
	nextpnr-himbaechel --device "$(DEVICE)" \
	  --vopt family=$(FAMILY) --vopt cst=$(CST) \
	  --json build/oric_tn20k.json --write build/oric_tn20k_pnr.json \
	  2> build/nextpnr.log || (tail -30 build/nextpnr.log; false)
	@grep -E "Max frequency" build/nextpnr.log | tail -4 || true

build/oric_tn20k.fs: build/oric_tn20k_pnr.json
	gowin_pack -d $(FAMILY) -o build/oric_tn20k.fs build/oric_tn20k_pnr.json

prog: build/oric_tn20k.fs
	openFPGALoader -b tangnano20k build/oric_tn20k.fs

flash: build/oric_tn20k.fs
	openFPGALoader -b tangnano20k -f build/oric_tn20k.fs

clean:
	rm -rf build

.PHONY: all prog flash clean
