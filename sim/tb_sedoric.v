// Replay comportemental du boot Sedoric (diagnostic US-DISK) : rejoue contre
// notre RTL (dsk_track + microdisc/WD1793 + chaîne SD) la séquence EXACTE des
// écritures WD/Microdisc capturée (FDC_TRACE) lors d'un boot RÉUSSI dans
// l'émulateur de référence, avec la sémantique IRQ de Sedoric :
//   - écriture $0314 avec INTENA (b0=1) => drainer les DRQ (lecture $0313)
//     puis attendre l'IRQ — tout timeout signale l'ÉTAPE PRÉCISE de blocage.
// Succès = les 1120 écritures rejouées sans blocage.
`timescale 1ns/1ps

module tb_sedoric;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;
    reg [1:0] cdiv = 0;
    always @(posedge clk) cdiv <= cdiv + 2'd1;
    wire cen = (cdiv == 2'd3);

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
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(1'b0), .wblk_idx(6'd0), .wblk_offset(32'd0),
        .wblk_data(8'd0), .wr_idx(9'd0),
        .wblk_pos(), .wblk_done(), .wblk_error(), .wr_start(), .wr_data()
    );

    // ---- Disquette ----
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

    // ---- Microdisc ----
    reg         io_sel = 0, we = 0;
    reg  [15:0] a = 0;
    reg  [7:0]  din = 0;
    wire [7:0]  dout, eprom_dout;
    wire        dout_valid, romdis, eprom_sel, irq;

    microdisc #(.ROM_FILE("roms/microdis.hex"),
                .REV_CYCLES(2000), .INDEX_CYCLES(40),
                .SETTLE_CYCLES(100), .RNF_CYCLES(5000)) md (
        .clk(clk), .cen(cen), .rst(rst), .enable(1'b1),
        .a(a), .io_sel(io_sel), .we(we), .din(din),
        .dout(dout), .dout_valid(dout_valid),
        .romdis(romdis), .eprom_sel(eprom_sel), .eprom_dout(eprom_dout),
        .rom_a(a[13:0]), .irq(irq),
        .disk_present(disk_present), .n_tracks(n_tracks), .n_spt(n_spt),
        .req_track(req_track), .req_side(req_side), .trk_loading(trk_loading),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte)
    );

    // ---- Séquence de replay ----
    localparam NSEQ = 1120;
    reg [11:0] seq [0:NSEQ-1];       // {addr[3:0], value[7:0]}
    initial $readmemh("sim/out/sed_replay.hex", seq);

    integer errors = 0;
    task bus_op(input w, input [15:0] ad, input [7:0] v);
        begin
            @(negedge clk); while (cdiv != 2'd2) @(negedge clk);
            io_sel = 1; we = w; a = ad; din = v;
            @(negedge clk); @(negedge clk);
            io_sel = 0; we = 0;
        end
    endtask
    reg [7:0] rd;
    task bus_read(input [15:0] ad);
        begin
            @(negedge clk); while (cdiv != 2'd2) @(negedge clk);
            io_sel = 1; we = 0; a = ad;
            @(negedge clk); rd = dout;
            @(negedge clk); io_sel = 0;
        end
    endtask

    integer step, guard, drained;
    reg [3:0] sa;
    reg [7:0] sv;

    initial begin
        repeat (8) @(negedge clk); rst = 0;

        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        if (bad_format) begin $display("FAIL: format"); $finish; end
        wait (trk_loading === 1'b1); wait (trk_loading === 1'b0);
        $display("SEDBOOT insere (%0d pistes), replay de %0d ecritures...",
                 n_tracks, NSEQ);

        for (step = 0; step < NSEQ; step = step + 1) begin
            sa = seq[step][11:8];
            sv = seq[step][7:0];
            bus_op(1, {12'h031, sa}, sv);
            if (sa == 4'h0) begin
                // Commande émise : drainer les DRQ ($0318) et attendre
                // /INTRQ actif ($0314 bit7=0) — indépendant de l'ordre
                // d'armement INTENA (le noyau Sedoric arme AVANT la
                // commande, l'EPROM APRÈS).
                guard = 0; drained = 0;
                rd = 8'hFF;
                while (rd[7] && guard < 30_000_000) begin
                    bus_read(16'h0318);
                    if (!rd[7]) begin
                        bus_read(16'h0313);      // octet de données
                        drained = drained + 1;
                    end
                    bus_read(16'h0314);          // /INTRQ ?
                    guard = guard + 1;
                end
                if (rd[7]) begin
                    $display("FAIL: BLOCAGE etape %0d (cmd $0310=%02x, %0d octets draines, piste=%0d chargement=%b present=%b)",
                             step, sv, drained, req_track, trk_loading, disk_present);
                    errors = errors + 1;
                    $finish;
                end
                bus_read(16'h0310);              // status : efface l'INTRQ
            end
            if (step % 100 == 0)
                $display("... etape %0d/%0d (piste %0d)", step, NSEQ, req_track);
        end

        if (errors == 0) $display("ALL TESTS PASSED (tb_sedoric : replay complet)");
        $finish;
    end

    initial begin
        #60_000_000_000;
        $display("FAIL: timeout global"); $finish;
    end

endmodule
