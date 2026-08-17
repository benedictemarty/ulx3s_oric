// Test écriture disquette END-TO-END (US-DISK.5 phase 4) : commande Write
// Sector du WD1793 via le bus Microdisc -> octets DRQ -> dsk_track (tbuf) ->
// write-back RMW -> SD. On écrit le secteur 1 (piste 0), puis on le relit par
// la commande Read Sector et on vérifie le nouveau motif ; le secteur 2 doit
// rester intact.
`timescale 1ns/1ps

module tb_dsk_wr_e2e;
    reg clk = 0, rst = 1;
    always #10 clk = ~clk;
    reg [1:0] cdiv = 0;
    always @(posedge clk) cdiv <= cdiv + 2'd1;
    wire cen = (cdiv == 2'd3);

    // ---- SD ----
    wire        rd_start, wr_start;
    wire [31:0] rd_sector;
    wire [7:0]  wr_data_sd;
    wire [8:0]  sd_wr_idx;
    wire        sd_ready, sd_busy, sd_dvalid, sd_error;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start),
        .start_write(wr_start), .wr_data(wr_data_sd), .wr_idx(sd_wr_idx),
        .sector(rd_sector),
        .ready(sd_ready), .busy(sd_busy), .error(sd_error),
        .data(sd_data), .data_valid(sd_dvalid), .status(sd_status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );
    sd_card_file #(.IMG("sim/out/fat_test.img")) card (
        .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso)
    );

    // ---- fat32 ----
    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    wire        d_open_start, d_open_abort, d_fdata_ready;
    wire [5:0]  d_open_idx;
    wire [31:0] d_open_offset;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;
    wire        d_wblk_start;
    wire [5:0]  d_wblk_idx;
    wire [31:0] d_wblk_offset;
    wire [7:0]  d_wblk_data;
    wire [8:0]  d_wblk_pos;
    wire        d_wblk_done, d_wblk_error;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd0), .q_name(), .q_size(), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(), .q3_idx(6'd0), .q3_name(),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(d_wblk_start), .wblk_idx(d_wblk_idx), .wblk_offset(d_wblk_offset),
        .wblk_data(d_wblk_data), .wblk_pos(d_wblk_pos),
        .wblk_done(d_wblk_done), .wblk_error(d_wblk_error),
        .wr_start(wr_start), .wr_data(wr_data_sd), .wr_idx(sd_wr_idx)
    );

    // ---- dsk_track ----
    reg        insert = 0;
    wire       inserted, bad_format, trk_loading, disk_present;
    wire [6:0] n_tracks, req_track;
    wire [4:0] n_spt, sec_id;
    wire       req_side, sec_valid;
    wire [8:0] sec_addr;
    wire [7:0] sec_byte;
    wire       d_sec_we, d_wr_commit, d_wr_busy, d_wr_ok, d_wr_err;
    wire [7:0] d_sec_wr_data;

    dsk_track dsk (
        .clk(clk), .rst(rst), .soft_rst(1'b0),
        .insert(insert), .file_idx(6'd5), .eject(1'b0),
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
        .sec_addr(sec_addr), .sec_byte(sec_byte),
        .sec_we(d_sec_we), .sec_wr_data(d_sec_wr_data), .wr_commit(d_wr_commit),
        .wr_busy(d_wr_busy), .wr_ok(d_wr_ok), .wr_err(d_wr_err),
        .wblk_start(d_wblk_start), .wblk_idx(d_wblk_idx),
        .wblk_offset(d_wblk_offset), .wblk_data(d_wblk_data),
        .wblk_pos(d_wblk_pos), .wblk_done(d_wblk_done), .wblk_error(d_wblk_error)
    );

    // ---- Microdisc + WD1793 ----
    reg         io_sel = 0, we = 0;
    reg  [15:0] a = 0;
    reg  [7:0]  din = 0;
    wire [7:0]  dout;

    microdisc #(.ROM_FILE("roms/microdis.hex"),
                .REV_CYCLES(2000), .INDEX_CYCLES(40),
                .SETTLE_CYCLES(100), .RNF_CYCLES(5000)) md (
        .clk(clk), .cen(cen), .rst(rst), .enable(1'b1),
        .a(a), .io_sel(io_sel), .we(we), .din(din),
        .dout(dout), .dout_valid(), .romdis(), .eprom_sel(),
        .eprom_dout(), .rom_a(a[13:0]), .irq(),
        .disk_present(disk_present), .n_tracks(n_tracks), .n_spt(n_spt),
        .req_track(req_track), .req_side(req_side), .trk_loading(trk_loading),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte),
        .sec_we(d_sec_we), .sec_wr_data(d_sec_wr_data), .wr_commit(d_wr_commit),
        .wr_busy(d_wr_busy), .wr_ok(d_wr_ok), .wr_err(d_wr_err)
    );

    integer errors = 0, i;
    reg [7:0] rd;

    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    task bus_op(input w, input [15:0] ad, input [7:0] v);
        begin
            @(negedge clk); while (cdiv != 2'd2) @(negedge clk);
            io_sel = 1; we = w; a = ad; din = v;
            @(negedge clk); @(negedge clk); io_sel = 0; we = 0;
        end
    endtask
    task bus_read(input [15:0] ad);
        begin
            @(negedge clk); while (cdiv != 2'd2) @(negedge clk);
            io_sel = 1; we = 0; a = ad;
            @(negedge clk); rd = dout;
            @(negedge clk); io_sel = 0;
        end
    endtask
    task wait_drq;
        integer n; begin n=0; rd=8'hFF;
            while (rd[7] && n < 4000000) begin bus_read(16'h0318); n=n+1; end
            check(!rd[7], "DRQ attendu");
        end
    endtask
    task wait_intrq;
        integer n; begin n=0; rd=8'hFF;
            while (rd[7] && n < 8000000) begin bus_read(16'h0314); n=n+1; end
            check(!rd[7], "INTRQ attendu");
        end
    endtask

    task write_sector(input [7:0] sec);
        begin
            bus_op(1, 16'h0312, sec);            // SECTOR
            bus_op(1, 16'h0310, 8'hA0);          // Write sector
            for (i = 0; i < 256; i = i + 1) begin
                wait_drq;
                bus_op(1, 16'h0313, 8'hC3 ^ i[7:0]);   // DATA (nouveau motif)
            end
            wait_intrq;
            bus_read(16'h0310);
            check(rd[6] == 1'b0, "write: pas de write-protect (bit6)");
            check(rd[4:0] == 5'd0, "write: status propre");
        end
    endtask

    task read_check(input [7:0] sec, input use_new);
        begin
            bus_op(1, 16'h0312, sec);
            bus_op(1, 16'h0310, 8'h80);          // Read sector
            for (i = 0; i < 256; i = i + 1) begin
                wait_drq;
                bus_read(16'h0313);
                if (use_new) begin
                    if (rd !== (8'hC3 ^ i[7:0]) && errors < 8) begin
                        $display("FAIL: s%0d relu b%0d=%02x att %02x", sec, i, rd, 8'hC3^i[7:0]);
                        errors = errors + 1;
                    end
                end else begin
                    if (rd !== (8'd2 ^ i[7:0]) && errors < 8) begin
                        $display("FAIL: s%0d corrompu b%0d=%02x att %02x", sec, i, rd, 8'd2^i[7:0]);
                        errors = errors + 1;
                    end
                end
            end
            wait_intrq; bus_read(16'h0310);
        end
    endtask

    initial begin
        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);

        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        wait (trk_loading === 1'b1); wait (trk_loading === 1'b0);
        bus_op(1, 16'h0310, 8'h08);              // Restore (piste 0)
        wait_intrq; bus_read(16'h0310);
        $display("disquette prete, piste 0");

        // 1) écrire le secteur 1 (nouveau motif) via le WD1793
        write_sector(8'd1);
        $display("write sector 1 OK (WD1793 -> SD)");

        // 2) relire le secteur 1 -> doit contenir le nouveau motif
        read_check(8'd1, 1'b1);
        $display("secteur 1 relu = nouveau motif");

        // 3) secteur 2 intact
        read_check(8'd2, 1'b0);
        $display("secteur 2 intact");

        if (errors == 0) $display("ALL TESTS PASSED (tb_dsk_wr_e2e)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #8000000000; $display("FAIL: timeout"); $finish; end
endmodule
