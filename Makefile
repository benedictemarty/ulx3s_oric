# ulx3s_oric — synthèse (yosys/nextpnr-ecp5) et simulation (iverilog)

PROJ      = oric_ulx3s
TOP       = top_ulx3s
FPGA_SIZE = 85k
PACKAGE   = CABGA381
LPF       = constraints/ulx3s_v20.lpf

RTL = rtl/oric_atmos.v rtl/oric_ula.v rtl/oric_ram.v rtl/oric_rom.v \
      rtl/via6522.v rtl/oric_keyboard.v rtl/framebuffer.v \
      rtl/tmds_encoder.v rtl/hdmi_out.v rtl/top_ulx3s.v \
      rtl/uart_rx.v rtl/key_injector.v \
      rtl/pll_video.v rtl/pll_sys.v

CPU = third_party/verilog-6502/cpu.v third_party/verilog-6502/ALU.v

JT49 = third_party/jt49/hdl/jt49_bus.v third_party/jt49/hdl/jt49.v \
       third_party/jt49/hdl/jt49_cen.v third_party/jt49/hdl/jt49_div.v \
       third_party/jt49/hdl/jt49_eg.v third_party/jt49/hdl/jt49_exp.v \
       third_party/jt49/hdl/jt49_noise.v

USB = third_party/usb_hid_host/src/usb_hid_host.v \
      third_party/usb_hid_host/src/usb_hid_host_rom.v

SRC = $(RTL) $(CPU) $(JT49) $(USB)

# Sources sans top ni HDMI ni USB ni PLL, pour la simulation
SIM_CORE = rtl/oric_atmos.v rtl/oric_ula.v rtl/oric_ram.v rtl/oric_rom.v \
           rtl/via6522.v rtl/oric_keyboard.v rtl/framebuffer.v \
           $(CPU) $(JT49)

all: build/$(PROJ).bit

build/$(PROJ).json: $(SRC) roms/basic11b.hex
	mkdir -p build
	cp roms/basic11b.hex build/
	cp third_party/usb_hid_host/src/usb_hid_host_rom.hex build/
	cd build && yosys -q -p "synth_ecp5 -noabc9 -top $(TOP) -json $(PROJ).json" $(addprefix ../,$(SRC))

build/$(PROJ).config: build/$(PROJ).json $(LPF)
	nextpnr-ecp5 --$(FPGA_SIZE) --package $(PACKAGE) --json build/$(PROJ).json \
	  --lpf $(LPF) --textcfg build/$(PROJ).config --randomize-seed 2> build/nextpnr.log \
	  || (tail -30 build/nextpnr.log; false)
	@grep -E "Max frequency|Info: Program finished" build/nextpnr.log | tail -8 || true

build/$(PROJ).bit: build/$(PROJ).config
	ecppack --compress build/$(PROJ).config build/$(PROJ).bit

prog: build/$(PROJ).bit
	openFPGALoader -b ulx3s build/$(PROJ).bit

prog-fujprog: build/$(PROJ).bit
	fujprog build/$(PROJ).bit

# ----------------------------------------------------------------------
# Tests
# ----------------------------------------------------------------------
TESTS = test-via test-keyboard test-injector test-ula test-boot

test: $(TESTS)
	@echo "== TOUS LES TESTS SONT PASSES =="

sim/out:
	mkdir -p sim/out

test-via: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_via.vvp sim/tb_via6522.v rtl/via6522.v
	vvp sim/out/tb_via.vvp | tee sim/out/tb_via.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_via.log

test-keyboard: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_kbd.vvp sim/tb_keyboard.v rtl/oric_keyboard.v
	vvp sim/out/tb_kbd.vvp | tee sim/out/tb_kbd.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_kbd.log

test-injector: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_inj.vvp sim/tb_injector.v \
	  rtl/uart_rx.v rtl/key_injector.v rtl/oric_keyboard.v
	vvp sim/out/tb_inj.vvp | tee sim/out/tb_inj.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_inj.log

test-ula: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_ula.vvp sim/tb_ula.v rtl/oric_ula.v rtl/oric_ram.v
	vvp sim/out/tb_ula.vvp | tee sim/out/tb_ula.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_ula.log

test-boot: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_boot.vvp sim/tb_boot.v $(SIM_CORE)
	vvp sim/out/tb_boot.vvp | tee sim/out/tb_boot.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_boot.log

clean:
	rm -rf build sim/out

.PHONY: all prog prog-fujprog test $(TESTS) clean
