// Boot Sedoric MACHINE COMPLÈTE (diagnostic US-DISK) : oric_atmos (vrai 6502
// + EPROM Microdisc, md_enable=1) + chaîne SD réelle (sed_test.img contenant
// SEDBOOT.DSK = les pistes de boot de sedoric3). La disquette est insérée
// avant la sortie de reset. On trace les écritures $031x du CPU (à comparer
// au trace FDC de référence) et on dumpe l'écran périodiquement — le point
// de divergence avec l'émulateur devient visible commande par commande.
`timescale 1ns/1ps

module tb_sedboot;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;

    // ---- Chaîne SD ----
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
    sd_card_file #(.IMG("sim/out/sed_test.img")) card (
        .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso)
    );

    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    wire        d_open_start, d_open_abort, d_fdata_ready;
    wire [5:0]  d_open_idx;
    wire [31:0] d_open_offset;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd0), .q_name(), .q_size(), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid)
    );

    reg  insert = 0;
    wire inserted, bad_format, trk_loading, disk_present;
    wire [6:0] n_tracks, req_track;
    wire [4:0] n_spt, sec_id;
    wire req_side, sec_valid;
    wire [8:0] sec_addr;
    wire [7:0] sec_byte;

    dsk_track dsk (
        .clk(clk), .rst(rst), .soft_rst(1'b0),
        .insert(insert), .file_idx(6'd0), .eject(1'b0),
        .inserted(inserted), .bad_format(bad_format),
        .bus_grant(1'b1), .fat_done(fat_done),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready), .fdata_valid(fdata_valid),
        .fdata(fdata), .feof(feof),
        .req_track(req_track), .req_side(req_side),
        .trk_loading(trk_loading), .disk_present(disk_present),
        .n_tracks(n_tracks), .n_spt(n_spt),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte)
    );

    // ---- Machine complète, Microdisc branché ----
    reg cpu_rst = 1;
    oric_atmos #(.DIV(25), .ROM_FILE("roms/basic11b.hex"),
                 .ROM_FILE_B("roms/basic10.hex"),
                 .MD_ROM_FILE("roms/microdis.hex")) dut (
        .clk(clk), .rst(cpu_rst), .rom_bank(1'b0), .turbo(1'b0),
        .md_enable(1'b1),
        .md_disk_present(disk_present), .md_n_tracks(n_tracks), .md_n_spt(n_spt),
        .md_req_track(req_track), .md_req_side(req_side),
        .md_trk_loading(trk_loading),
        .md_sec_id(sec_id), .md_sec_valid(sec_valid),
        .md_sec_addr(sec_addr), .md_sec_byte(sec_byte),
        .kbd_azerty(1'b0), .kbd_mods(8'd0), .kbd_k1(8'd0), .kbd_k2(8'd0), .kbd_k3(8'd0), .kbd_k4(8'd0),
        .inj_active(1'b0), .inj_col(3'd0), .inj_row(3'd0), .inj_shift(1'b0),
        .exp_addr(), .exp_we(), .exp_do(), .exp_io_page(), .exp_tphase(),
        .ext_din(8'hFF), .ext_irq(1'b0), .ext_romdis(1'b0), .ext_map(1'b0),
        .ext_ioctl(1'b0),
        .prn_data(), .prn_strobe_n(), .prn_ack(1'b1),
        .tape_out(), .tape_motor(), .tape_in(1'b1),
        .fb_we(), .fb_addr(), .fb_data(),
        .frame_tick(), .audio(), .cpu_irq_dbg()
    );

    // ---- Golden : secteurs plats attendus (extraction de référence) ----
    reg [7:0] sgold [0:62*17*256-1];
    initial $readmemh("sim/out/sed_golden.hex", sgold);
    reg [7:0] cur_sec = 0;
    integer   mism = 0;

    // ---- Trace des écritures $031x + drains $0313 + détecteur de gel ----
    integer wr_cnt = 0, rd313 = 0;
    reg [31:0] quiet = 0;
    reg [15:0] rb_pc [0:255];
    reg [7:0]  rb_di [0:255];
    reg        rb_we [0:255];
    reg [7:0]  rb_head = 0;
    reg        rb_dumped = 0;
    integer    rb_i;
    integer    wrd_cnt = 0;
    reg        sta_watch = 0;
    integer    sta_cnt = 0;
    integer    wre_cnt = 0, wr27_cnt = 0;
    always @(posedge clk) begin
        if (dut.cen1 && dut.sel_md && dut.bus_we_q && wr_cnt < 1500) begin
            if (rd313 != 0) begin
                $display("[RTL]   (drain %0d octets)", rd313);
                rd313 = 0;
            end
            if (dut.bus_addr_q[3:0] == 4'h2) cur_sec = dut.bus_do_q;
            $display("[RTL] write $%04x = %02x", dut.bus_addr_q, dut.bus_do_q);
            wr_cnt = wr_cnt + 1;
            quiet <= 0;
        end else if (dut.cen1 && dut.sel_md) begin
            quiet <= 0;
            if (!dut.bus_we_q && dut.bus_addr_q[3:0] == 4'h3) begin
                if (dut.md_dout !== sgold[(req_track*17 + (cur_sec-1))*256 + rd313]
                    && mism < 20) begin
                    $display("[DATA] t%0d s%0d octet %0d : CPU=%02x golden=%02x",
                             req_track, cur_sec, rd313, dut.md_dout,
                             sgold[(req_track*17 + (cur_sec-1))*256 + rd313]);
                    mism = mism + 1;
                end
                rd313 = rd313 + 1;
            end
        end else if (dut.cen1)
            quiet <= quiet + 1;
        // Destination des stores pendant les drains (STA qui suit LDA $0313)
        if (dut.cen1) begin
            if (dut.sel_md && !dut.bus_we_q && dut.bus_addr_q[3:0] == 4'h3)
                sta_watch <= 1'b1;
            else if (sta_watch && dut.bus_we_q) begin
                if (rd313 == 1)          // 1er octet du drain : destination
                    $display("[STA] sec %0d (piste %0d) -> %04x",
                             cur_sec, req_track, dut.bus_addr_q);
                sta_watch <= 1'b0;
            end
        end
        // Origine du vecteur, du code fantôme $EExx et des slots $027x
        if (dut.cen1 && dut.bus_we_q) begin
            if (dut.bus_addr_q >= 16'hFFFE)
                $display("[WRV] W %04x = %02x", dut.bus_addr_q, dut.bus_do_q);
            else if (dut.bus_addr_q[15:8] == 8'hEE && wre_cnt < 30) begin
                $display("[WRE] W %04x = %02x", dut.bus_addr_q, dut.bus_do_q);
                wre_cnt = wre_cnt + 1;
            end
            else if (dut.bus_addr_q[15:4] == 12'h027 && wr27_cnt < 20) begin
                $display("[WR2] W %04x = %02x", dut.bus_addr_q, dut.bus_do_q);
                wr27_cnt = wr27_cnt + 1;
            end
        end
        // Écritures vers $D000-$D1FF : atterrissent-elles en RAM ?
        if (dut.cen1 && dut.bus_we_q && dut.bus_addr_q[15:9] == 7'b1101_000
            && wrd_cnt < 30) begin
            $display("[WRD] W %04x=%02x romdis=%b eprom=%b landed=%b",
                     dut.bus_addr_q, dut.bus_do_q, dut.md_romdis,
                     dut.md_eprom_sel, dut.sel_ram | dut.rom_as_ram);
            wrd_cnt = wrd_cnt + 1;
        end
        // Enregistreur de vol : 256 derniers cycles bus, dumpés au gel
        if (dut.cen1) begin
            rb_pc[rb_head] <= dut.cpu_ab;
            rb_di[rb_head] <= dut.cpu_di;
            rb_we[rb_head] <= dut.cpu_we;
            rb_head <= rb_head + 8'd1;
        end
        if (dut.cen1 && quiet[19] && quiet[7:0] == 0 && quiet < 32'hC0000)
            $display("[IRQ] PC~%04x via=%b acia=%b md=%b ifr=%02x ier=%02x t1=%04x",
                     dut.cpu_ab, dut.via_irq, dut.acia_irq, dut.md_irq,
                     dut.via.ifr, dut.via.ier, dut.via.t1c);
        if (dut.cen1 && quiet == 32'd300 && !rb_dumped && wr_cnt > 200) begin
            rb_dumped = 1;
            $display("[VOL] 256 derniers cycles avant gel :");
            for (rb_i = 0; rb_i < 256; rb_i = rb_i + 1)
                $display("[VOL] %04x %s %02x",
                         rb_pc[(rb_head + rb_i) & 8'hFF],
                         rb_we[(rb_head + rb_i) & 8'hFF] ? "W" : "R",
                         rb_di[(rb_head + rb_i) & 8'hFF]);
        end
    end

    // ---- Écran ----
    integer sd_r, sd_c, sd_n = 0;
    reg [7:0] sd_ch;
    reg [40*8-1:0] sd_line;
    task dump_screen;
        begin
            $display("=== ECRAN (dump %0d) ===", sd_n);
            for (sd_r = 0; sd_r < 28; sd_r = sd_r + 1) begin
                for (sd_c = 0; sd_c < 40; sd_c = sd_c + 1) begin
                    sd_ch = dut.ram.mem[16'hBB80 + sd_r*40 + sd_c];
                    if (sd_ch < 8'h20 || sd_ch > 8'h7E) sd_ch = " ";
                    sd_line[(39-sd_c)*8 +: 8] = sd_ch;
                end
                if (sd_line != {40{8'h20}}) $display("|%0d|%s|", sd_r, sd_line);
            end
            sd_n = sd_n + 1;
        end
    endtask

    integer i;
    initial begin
        repeat (8) @(negedge clk); rst = 0;

        // Préparer la disquette AVANT de lâcher le CPU (comme un vrai boot
        // avec la disquette déjà dans le lecteur)
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        wait (trk_loading === 1'b1); wait (trk_loading === 1'b0);
        $display("disquette prete (%0d pistes) — lancement du CPU", n_tracks);
        @(negedge clk); cpu_rst = 0;

        // 16 s Oric max, dump écran toutes les ~500 ms Oric
        for (i = 0; i < 32; i = i + 1) begin
            repeat (12_500_000) @(negedge clk);
            dump_screen;
        end
        // Autopsie mémoire : vecteur IRQ, handler, hooks
        $display("[MEM] vecteur IRQ ($FFFE) = %02x%02x",
                 dut.ram.mem[16'hFFFF], dut.ram.mem[16'hFFFE]);
        for (i = 0; i < 4; i = i + 1)
            $display("[MEM] D0%02x : %02x %02x %02x %02x %02x %02x %02x %02x",
                     8'h90 + i*8,
                     dut.ram.mem[16'hD090+i*8], dut.ram.mem[16'hD091+i*8],
                     dut.ram.mem[16'hD092+i*8], dut.ram.mem[16'hD093+i*8],
                     dut.ram.mem[16'hD094+i*8], dut.ram.mem[16'hD095+i*8],
                     dut.ram.mem[16'hD096+i*8], dut.ram.mem[16'hD097+i*8]);
        $display("FIN (voir traces [RTL] vs fdc_trace_ref.log)");
        $finish;
    end

endmodule
