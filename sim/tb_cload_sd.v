// Testbench bout-en-bout CLOAD via la CHAÎNE SD COMPLÈTE (comme sur carte) :
// sd_card_file (image FAT32) -> sd_spi -> fat32 -> tape_loader ->
// tape_injector -> oric_atmos (ROM réelle, frappe CLOAD"" au clavier).
// Reproduit le chemin exact de la carte, en mode normal (+turbo=0) ou turbo
// (+turbo=1, câblage identique au top). Succès = données du VALID.TAP
// ('ABCD') chargées en $0501-$0504, pas d'« Errors found » à l'écran.
`timescale 1ns/1ps

module tb_cload_sd;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;

    integer turbo_mode = 0;
    initial if (!$value$plusargs("turbo=%d", turbo_mode)) turbo_mode = 0;

    // ---- Clavier ----
    reg  [7:0] key_data = 0;
    reg        key_valid = 0;
    wire       inj_active, inj_shift;
    wire [2:0] inj_col, inj_row;

    key_injector #(.PRESS_TICKS(500_000), .GAP_TICKS(250_000)) keys (
        .clk(clk), .rst(rst),
        .rx_data(key_data), .rx_valid(key_valid),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row),
        .inj_shift(inj_shift)
    );

    // ---- Chaîne SD : carte-image + SPI + FAT32 ----
    wire        rd_start;
    wire [31:0] rd_sector;
    wire        sd_ready, sd_busy, sd_dvalid, sd_error;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start),
        .start_write(1'b0), .wr_data(8'd0), .sector(rd_sector),
        .ready(sd_ready), .busy(sd_busy), .error(sd_error),
        .data(sd_data), .data_valid(sd_dvalid), .status(sd_status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );
    sd_card_file #(.IMG("sim/out/fat_test.img")) card (
        .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso)
    );

    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    wire [87:0] q_name;
    wire [31:0] q_size, q_clus;
    wire        q_isdsk;
    wire        open_start, fdata_ready, floading, feof, fdata_valid;
    wire [5:0]  open_idx;
    wire [7:0]  fdata;

    localparam SEL = 6'd4;      // VALID.TAP (listing : DEFENDER, CITADEL,
                                // ORICCHES, TEST, VALID)
    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(SEL), .q_name(q_name), .q_size(q_size), .q_clus(q_clus), .q_isdsk(q_isdsk),
        .q2_idx(6'd0), .q2_name(),
        .open_start(open_start), .open_idx(open_idx), .open_offset(32'd0), .open_abort(1'b0), .fdata_ready(fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(1'b0), .wblk_idx(6'd0), .wblk_offset(32'd0),
        .wblk_data(8'd0), .wr_idx(9'd0),
        .wblk_pos(), .wblk_done(), .wblk_error(), .wr_start(), .wr_data()
    );

    // ---- Chargeur cassette (comme dans le top) ----
    reg         load_trigger = 0;
    wire [7:0]  ld_rx_data;
    wire        ld_rx_valid, ld_active;
    wire [7:0]  tap_tx_data;
    wire        tap_tx_send;
    wire        tape_line, tape_active, tape_motor;

    tape_loader ld (
        .clk(clk), .rst(rst), .load_trigger(load_trigger),
        .sel_idx(SEL), .file_size(q_size), .fat_ready(fat_done),
        .open_start(open_start), .open_idx(open_idx), .fdata_ready(fdata_ready),
        .fdata_valid(fdata_valid), .fdata(fdata), .feof(feof),
        .tape_rx_data(ld_rx_data), .tape_rx_valid(ld_rx_valid),
        .tape_credit(tap_tx_send), .active(ld_active)
    );

    wire turbo = (turbo_mode != 0) && tape_active;   // comme dans le top

    tape_injector tape (
        .clk(clk), .rst(rst),
        .rx_data(ld_rx_data), .rx_valid(ld_rx_valid),
        .tx_data(tap_tx_data), .tx_send(tap_tx_send),
        .tx_busy(1'b0),                    // loader : jamais occupé (cf. top)
        .turbo(turbo), .motor(tape_motor),
        .tape_line(tape_line), .tape_active(tape_active)
    );

    // ---- Oric ----
    oric_atmos #(.DIV(25), .ROM_FILE("roms/basic11b.hex"), .ROM_FILE_B("roms/basic10.hex"), .MD_ROM_FILE("roms/microdis.hex")) dut (
        .clk(clk), .rst(rst), .rom_bank(1'b0), .telestrat_mode(1'b0), .turbo(turbo),
        .md_enable(1'b0), .md_disk_present(1'b0), .md_n_tracks(7'd42), .md_n_spt(5'd17), .md_req_track(), .md_req_side(), .md_trk_loading(1'b0), .md_sec_id(), .md_sec_valid(1'b0), .md_sec_addr(), .md_sec_byte(8'h00),
        .kbd_azerty(1'b0), .kbd_mods(8'd0), .kbd_k1(8'd0), .kbd_k2(8'd0), .kbd_k3(8'd0), .kbd_k4(8'd0),
        .joy_up(1'b0), .joy_down(1'b0), .joy_left(1'b0), .joy_right(1'b0), .joy_fire(1'b0), .joy_present(1'b0),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row), .inj_shift(inj_shift),
        .exp_addr(), .exp_we(), .exp_do(), .exp_io_page(), .exp_tphase(),
        .ext_din(8'hFF), .ext_irq(1'b0), .ext_romdis(1'b0), .ext_map(1'b0),
        .ext_ioctl(1'b0),
        .prn_data(), .prn_strobe_n(), .prn_ack(1'b1),
        .tape_out(), .tape_motor(tape_motor), .tape_in(tape_line),
        .fb_we(), .fb_addr(), .fb_data(),
        .frame_tick(), .audio(), .cpu_irq_dbg()
    );

    // ---- Écran ----
    integer i, j;
    reg found;
    task scan_for(input [8*8-1:0] pat, input integer plen);
        begin
            found = 0;
            for (i = 16'hBB80; i <= 16'hBFDF - plen; i = i + 1) begin
                found = 1;
                for (j = 0; j < plen; j = j + 1)
                    if (dut.ram.mem[i+j] !== pat[(plen-1-j)*8 +: 8]) found = 0;
                if (found) i = 16'hBFDF;
            end
        end
    endtask

    task type_str(input [8*16-1:0] s, input integer n);
        begin
            for (j = 0; j < n; j = j + 1) begin
                @(negedge clk); key_data = s[(n-1-j)*8 +: 8]; key_valid = 1;
                @(negedge clk); key_valid = 0;
                repeat (10) @(negedge clk);
            end
        end
    endtask

    integer cpu_cycles;
    reg searching_seen = 0;

    initial begin
        repeat (10) @(negedge clk); rst = 0;

        // 0) Init SD + parsing FAT (en parallèle du boot ROM)
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("FAT OK : %0d fichiers, VALID.TAP taille=%0d", file_count, q_size);

        // 1) Boot -> bannière
        found = 0;
        for (cpu_cycles = 0; cpu_cycles < 5_000_000 && !found; cpu_cycles = cpu_cycles + 1) begin
            repeat (25) @(negedge clk);
            if (cpu_cycles % 250_000 == 0) scan_for("ORIC", 4);
        end
        if (!found) begin $display("FAIL: pas de banniere"); $finish; end
        $display("boot OK");
        repeat (2_000_000) @(negedge clk);

        // 2) CLOAD"" + Entrée
        type_str({"CLOAD", 8'h22, 8'h22, 8'h0D}, 8);

        // 3) Attendre Searching (moteur en marche)
        for (cpu_cycles = 0; cpu_cycles < 8_000_000 && !searching_seen; cpu_cycles = cpu_cycles + 1) begin
            repeat (25) @(negedge clk);
            if (cpu_cycles % 100_000 == 0) begin
                scan_for("earching", 8);
                if (found) searching_seen = 1;
            end
        end
        if (!searching_seen) begin $display("FAIL: pas de Searching"); $finish; end
        $display("Searching vu, motor=%b — declenchement OSD (load_trigger)", tape_motor);

        // 4) Déclencher le chargement SD (équivalent BTN4)
        @(negedge clk); load_trigger = 1; @(negedge clk); load_trigger = 0;

        // 5) Laisser aller au bout puis vérifier le résultat
        repeat (60_000_000) @(negedge clk);
        scan_for("rrors", 5);
        $display("VERDICT SD turbo=%0d : Errors=%0d  $0501..0504 = %h %h %h %h",
                 turbo_mode, found,
                 dut.ram.mem[16'h0501], dut.ram.mem[16'h0502],
                 dut.ram.mem[16'h0503], dut.ram.mem[16'h0504]);
        if (dut.ram.mem[16'h0501] === 8'h41 && dut.ram.mem[16'h0502] === 8'h42 &&
            dut.ram.mem[16'h0503] === 8'h43 && dut.ram.mem[16'h0504] === 8'h44 && !found)
            $display("ALL TESTS PASSED (tb_cload_sd, turbo=%0d)", turbo_mode);
        else
            $display("FAIL: chargement SD incorrect (turbo=%0d)", turbo_mode);
        $finish;
    end

    initial begin
        #8_000_000_000;
        $display("FAIL: timeout global"); $finish;
    end

endmodule
