# ulx3s_oric — synthèse (yosys/nextpnr-ecp5) et simulation (iverilog)

PROJ      = oric_ulx3s
TOP       = top_ulx3s
FPGA_SIZE = 85k
PACKAGE   = CABGA381
LPF       = constraints/ulx3s_v20.lpf

RTL = rtl/oric_atmos.v rtl/oric_ula.v rtl/oric_ram.v rtl/bank_window.v \
      rtl/via6522.v rtl/oric_keyboard.v rtl/joystick_ijk.v rtl/framebuffer.v \
      rtl/tmds_encoder.v rtl/hdmi_tmds_channel.v rtl/hdmi_packet_assembler.v \
      rtl/hdmi_audio_packets.v rtl/hdmi_data_island.v \
      rtl/hdmi_out.v rtl/top_ulx3s.v \
      rtl/uart_rx.v rtl/uart_tx.v rtl/key_injector.v rtl/tape_injector.v rtl/tape_demod.v rtl/tape_saver.v \
      rtl/acia6551.v rtl/expansion_port.v rtl/pll_video.v rtl/pll_sys.v \
      rtl/spi_byte.v rtl/sd_spi.v rtl/fat32.v rtl/tape_loader.v rtl/osd.v rtl/fat_dump.v \
      rtl/wd1793.v rtl/microdisc.v rtl/dsk_track.v rtl/screen_stream.v rtl/audio_dac_sd.v \
      rtl/led_activity.v

CPU = third_party/verilog-6502/cpu.v third_party/verilog-6502/ALU.v

JT49 = third_party/jt49/hdl/jt49_bus.v third_party/jt49/hdl/jt49.v \
       third_party/jt49/hdl/jt49_cen.v third_party/jt49/hdl/jt49_div.v \
       third_party/jt49/hdl/jt49_eg.v third_party/jt49/hdl/jt49_exp.v \
       third_party/jt49/hdl/jt49_noise.v

USB = third_party/usb_hid_host/src/usb_hid_host.v \
      third_party/usb_hid_host/src/usb_hid_host_rom.v

SRC = $(RTL) $(CPU) $(JT49) $(USB)

# Sources sans top ni HDMI ni USB ni PLL, pour la simulation
SIM_CORE = rtl/oric_atmos.v rtl/oric_ula.v rtl/oric_ram.v rtl/bank_window.v \
           rtl/via6522.v rtl/oric_keyboard.v rtl/joystick_ijk.v rtl/framebuffer.v rtl/acia6551.v \
           rtl/wd1793.v rtl/microdisc.v rtl/dsk_track.v \
           $(CPU) $(JT49)

all: build/$(PROJ).bit

build/$(PROJ).json: $(SRC) roms/basic11b.hex roms/basic10.hex roms/microdis.hex
	mkdir -p build
	cp roms/basic11b.hex build/
	cp roms/basic10.hex build/
	cp roms/microdis.hex build/
	cp roms/font8x8.hex build/
	cp third_party/usb_hid_host/src/usb_hid_host_rom.hex build/
	cd build && yosys -q -p "read_verilog -I../rtl $(addprefix ../,$(SRC)); synth_ecp5 -noabc9 -top $(TOP) -json $(PROJ).json"

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
TESTS = test-via test-keyboard test-azerty test-injector test-tape test-tape-demod test-tape-saver test-joystick test-audio-dac test-led test-acia test-expansion test-ula test-boot test-hdmi test-hdmi-packet test-hdmi-audio test-hdmi-island test-spi-byte test-sd test-fat test-tape-loader test-wd test-microdisc test-dsk test-sw1reset test-sd-write test-fat-write test-bank test-bank-sel test-sdram test-dsk-write test-dsk-wr-e2e

test: $(TESTS)
	@echo "== TOUS LES TESTS SONT PASSES =="

sim/out:
	mkdir -p sim/out

test-via: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_via.vvp sim/tb_via6522.v rtl/via6522.v
	vvp sim/out/tb_via.vvp | tee sim/out/tb_via.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_via.log

test-keyboard: sim/out
	iverilog -DSIM -g2005 -I rtl -o sim/out/tb_kbd.vvp sim/tb_keyboard.v rtl/oric_keyboard.v
	vvp sim/out/tb_kbd.vvp | tee sim/out/tb_kbd.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_kbd.log

test-azerty: sim/out
	iverilog -DSIM -g2005 -I rtl -o sim/out/tb_azerty.vvp sim/tb_azerty.v rtl/oric_keyboard.v
	vvp sim/out/tb_azerty.vvp | tee sim/out/tb_azerty.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_azerty.log

test-tape: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_tape.vvp sim/tb_tape.v rtl/tape_injector.v
	vvp sim/out/tb_tape.vvp | tee sim/out/tb_tape.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_tape.log

test-tape-demod: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_tape_demod.vvp sim/tb_tape_demod.v \
	    rtl/tape_injector.v rtl/tape_demod.v
	vvp sim/out/tb_tape_demod.vvp | tee sim/out/tb_tape_demod.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_tape_demod.log

test-audio-dac: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_adac.vvp sim/tb_audio_dac_sd.v rtl/audio_dac_sd.v
	vvp sim/out/tb_adac.vvp | tee sim/out/tb_adac.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_adac.log

test-led: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_led.vvp sim/tb_led_activity.v rtl/led_activity.v
	vvp sim/out/tb_led.vvp | tee sim/out/tb_led.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_led.log

test-joystick: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_joy.vvp sim/tb_joystick_ijk.v rtl/joystick_ijk.v
	vvp sim/out/tb_joy.vvp | tee sim/out/tb_joy.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_joy.log

test-tape-saver: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_tsv.vvp sim/tb_tape_saver.v \
	    rtl/tape_injector.v rtl/tape_demod.v rtl/tape_saver.v \
	    rtl/fat32.v rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_tsv.vvp | tee sim/out/tb_tsv.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_tsv.log
	python3 tools/check_save_tap.py sim/out/fat_test.img 604

test-acia: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_acia.vvp sim/tb_acia.v rtl/acia6551.v
	vvp sim/out/tb_acia.vvp | tee sim/out/tb_acia.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_acia.log

test-fat-write: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_fw.vvp sim/tb_fat_write.v rtl/fat32.v rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_fw.vvp | tee sim/out/tb_fw.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_fw.log

test-sd-write: sim/out
	python3 -c "open('sim/out/wr_test.img','wb').write(b'\\xEE'*65536)"
	iverilog -DSIM -g2005 -o sim/out/tb_sdw.vvp sim/tb_sd_write.v rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_sdw.vvp | tee sim/out/tb_sdw.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_sdw.log

test-sw1reset: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_sw1.vvp sim/tb_sw1reset.v
	vvp sim/out/tb_sw1.vvp | tee sim/out/tb_sw1.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_sw1.log

test-injector: sim/out
	iverilog -DSIM -g2005 -I rtl -o sim/out/tb_inj.vvp sim/tb_injector.v \
	  rtl/uart_rx.v rtl/key_injector.v rtl/oric_keyboard.v
	vvp sim/out/tb_inj.vvp | tee sim/out/tb_inj.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_inj.log

test-expansion: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_exp.vvp sim/tb_expansion.v rtl/expansion_port.v
	vvp sim/out/tb_exp.vvp | tee sim/out/tb_exp.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_exp.log

test-bank: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_bank.vvp sim/tb_bank_window.v rtl/bank_window.v
	vvp sim/out/tb_bank.vvp | tee sim/out/tb_bank.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_bank.log

test-bank-sel: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_bsel.vvp sim/tb_bank_sel.v rtl/via6522.v
	vvp sim/out/tb_bsel.vvp | tee sim/out/tb_bsel.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_bsel.log

# Bring-up SDRAM (US-MBANK.4b) : contrôleur SDR d'oric2 (EUPL, bmarty) +
# modèle comportemental. Hors bus Oric — prouve init JEDEC + W/R + refresh.
test-sdram: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_sdram.vvp sim/tb_sdram.v rtl/sdram_ctrl.v sim/sdram_model.v
	vvp sim/out/tb_sdram.vvp | tee sim/out/tb_sdram.log
	@grep -q "RESULT: PASS" sim/out/tb_sdram.log

test-dsk-write: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_dskw.vvp sim/tb_dsk_write.v \
	  rtl/dsk_track.v rtl/fat32.v rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_dskw.vvp | tee sim/out/tb_dskw.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_dskw.log

test-dsk-wr-e2e: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_dskwe.vvp sim/tb_dsk_wr_e2e.v \
	  rtl/dsk_track.v rtl/microdisc.v rtl/wd1793.v rtl/fat32.v rtl/sd_spi.v \
	  rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_dskwe.vvp | tee sim/out/tb_dskwe.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_dskwe.log

test-ula: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_ula.vvp sim/tb_ula.v rtl/oric_ula.v rtl/oric_ram.v
	vvp sim/out/tb_ula.vvp | tee sim/out/tb_ula.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_ula.log

test-boot: sim/out
	iverilog -DSIM -g2005 -I rtl -o sim/out/tb_boot.vvp sim/tb_boot.v $(SIM_CORE)
	vvp sim/out/tb_boot.vvp | tee sim/out/tb_boot.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_boot.log

test-hdmi: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_hdmi.vvp sim/tb_hdmi_tmds.v \
	  rtl/hdmi_tmds_channel.v rtl/tmds_encoder.v
	vvp sim/out/tb_hdmi.vvp | tee sim/out/tb_hdmi.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_hdmi.log

test-hdmi-packet: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_hdmi_packet.vvp sim/tb_hdmi_packet.v \
	  rtl/hdmi_packet_assembler.v
	vvp sim/out/tb_hdmi_packet.vvp | tee sim/out/tb_hdmi_packet.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_hdmi_packet.log

test-hdmi-audio: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_hdmi_audio.vvp sim/tb_hdmi_audio.v \
	  rtl/hdmi_audio_packets.v
	vvp sim/out/tb_hdmi_audio.vvp | tee sim/out/tb_hdmi_audio.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_hdmi_audio.log

test-hdmi-island: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_hdmi_island.vvp sim/tb_hdmi_island.v \
	  rtl/hdmi_data_island.v rtl/hdmi_audio_packets.v rtl/hdmi_packet_assembler.v
	vvp sim/out/tb_hdmi_island.vvp | tee sim/out/tb_hdmi_island.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_hdmi_island.log

test-spi-byte: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_spi_byte.vvp sim/tb_spi_byte.v rtl/spi_byte.v
	vvp sim/out/tb_spi_byte.vvp | tee sim/out/tb_spi_byte.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_spi_byte.log

test-sd: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_sd.vvp sim/tb_sd_spi.v \
	  rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_model.v
	vvp sim/out/tb_sd.vvp | tee sim/out/tb_sd.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_sd.log

test-fat: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_fat32.vvp sim/tb_fat32.v \
	  rtl/fat32.v rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_fat32.vvp | tee sim/out/tb_fat32.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_fat32.log

test-tape-loader: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_tl.vvp sim/tb_tape_loader.v \
	  rtl/tape_loader.v rtl/fat32.v rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_tl.vvp | tee sim/out/tb_tl.log

test-wd: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_wd.vvp sim/tb_wd1793.v rtl/wd1793.v
	vvp sim/out/tb_wd.vvp | tee sim/out/tb_wd.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_wd.log

test-dsk: sim/out
	python3 tools/gen_fat_test.py sim/out/fat_test.img
	iverilog -DSIM -g2005 -o sim/out/tb_dsk.vvp sim/tb_dsk.v \
	  rtl/dsk_track.v rtl/microdisc.v rtl/wd1793.v rtl/fat32.v \
	  rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_dsk.vvp | tee sim/out/tb_dsk.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_dsk.log

# Diagnostic (hors suite) : replay du boot Sedoric de référence
test-sedoric: sim/out
	python3 tools/gen_sed_test.py sim/out/sed_test.img sim/out/fdc_trace_ref.log
	iverilog -DSIM -g2005 -o sim/out/tb_sed.vvp sim/tb_sedoric.v \
	  rtl/dsk_track.v rtl/microdisc.v rtl/wd1793.v rtl/fat32.v \
	  rtl/sd_spi.v rtl/spi_byte.v sim/sd_card_file.v
	vvp sim/out/tb_sed.vvp | tee sim/out/tb_sed.log

test-microdisc: sim/out
	iverilog -DSIM -g2005 -o sim/out/tb_md.vvp sim/tb_microdisc.v \
	  rtl/microdisc.v rtl/wd1793.v
	vvp sim/out/tb_md.vvp | tee sim/out/tb_md.log
	@grep -q "ALL TESTS PASSED" sim/out/tb_md.log

# ----------------------------------------------------------------------
# ESP32 embarqué (modem WiFi) — compilation / flash
# ----------------------------------------------------------------------
esp32-setup:
	tools/esp32/setup.sh

esp32-build:
	tools/esp32/build.sh

esp32-flash:
	tools/esp32/flash.sh $(PORT)

# Flux robuste (passthru persistant en FLASH + rebranchement + BTN0) :
PASSTHRU_BIT = tools/esp32/passthru/ulx3s_85f_passthru.bit
esp32-passthru-flash:
	openFPGALoader -f --unprotect-flash -b ulx3s $(PASSTHRU_BIT)

esp32-upload:
	tools/esp32/upload.sh $(PORT)

# Contourne la régression de reset esptool >=4.6 (esptool ancien en venv) :
esp32-flash-classic:
	tools/esp32/flash-esptool.sh $(PORT)

# Force l'ESP32 en mode download par bitstream maison, puis flash no_reset :
build/download_esp32.bit: rtl/download_esp32.v $(LPF)
	mkdir -p build
	cd build && yosys -q -p "synth_ecp5 -noabc9 -top download_esp32 -json download_esp32.json" ../rtl/download_esp32.v
	nextpnr-ecp5 --$(FPGA_SIZE) --package $(PACKAGE) --json build/download_esp32.json \
	  --lpf $(LPF) --textcfg build/download_esp32.config --randomize-seed 2> build/dl_pnr.log \
	  || (tail -20 build/dl_pnr.log; false)
	ecppack --compress build/download_esp32.config build/download_esp32.bit

esp32-download: build/download_esp32.bit
	tools/esp32/flash-download.sh $(PORT)

oric-flash: build/oric_ulx3s.bit
	openFPGALoader -f --unprotect-flash -b ulx3s build/oric_ulx3s.bit

clean:
	rm -rf build sim/out

.PHONY: all prog prog-fujprog test $(TESTS) esp32-setup esp32-build esp32-flash \
        esp32-passthru-flash esp32-upload esp32-flash-classic esp32-download oric-flash clean
