// Test écriture disquette (US-DISK.5 phase 3) : charge la piste 0 de
// TESTMFM.DSK, écrit un secteur (via sec_we) dans tbuf, commit -> write-back
// RMW vers la SD, puis RECHARGE la piste depuis la SD et vérifie que la
// nouvelle donnée a persisté (et qu'un autre secteur est intact).
`timescale 1ns/1ps

module tb_dsk_write;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;

    // ---- SD ----
    wire        rd_start, wr_start;
    wire [31:0] rd_sector;
    wire [7:0]  wr_data;
    wire [8:0]  sd_wr_idx;
    wire        sd_ready, sd_busy, sd_dvalid, sd_error;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start),
        .start_write(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx),
        .sector(rd_sector),
        .ready(sd_ready), .busy(sd_busy), .error(sd_error),
        .data(sd_data), .data_valid(sd_dvalid), .status(sd_status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );
    sd_card_file #(.IMG("sim/out/fat_test.img")) card (
        .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso)
    );

    // ---- fat32 (client = dsk_track) ----
    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    wire        d_open_start, d_open_abort, d_fdata_ready;
    wire [5:0]  d_open_idx;
    wire [31:0] d_open_offset;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;
    // write-back : dsk_track -> fat32.wblk
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
        .q2_idx(6'd0), .q2_name(),
        .q3_idx(6'd0), .q3_name(),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(d_wblk_start), .wblk_idx(d_wblk_idx), .wblk_offset(d_wblk_offset),
        .wblk_data(d_wblk_data), .wblk_pos(d_wblk_pos),
        .wblk_done(d_wblk_done), .wblk_error(d_wblk_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    // ---- dsk_track ----
    reg        insert = 0, eject = 0;
    reg [5:0]  tb_fidx = 6'd5;         // TESTMFM.DSK
    wire       inserted, bad_format, trk_loading, disk_present;
    wire [6:0] n_tracks;
    wire [4:0] n_spt;
    reg  [6:0] req_track = 0;
    reg        req_side = 0;
    reg  [4:0] sec_id = 0;
    wire       sec_valid;
    reg  [8:0] sec_addr = 0;
    wire [7:0] sec_byte;
    reg        sec_we = 0, wr_commit = 0;
    reg  [7:0] sec_wr_data = 0;
    wire       wr_busy, wr_ok, wr_err;

    dsk_track dsk (
        .clk(clk), .rst(rst), .soft_rst(1'b0),
        .insert(insert), .file_idx(tb_fidx), .eject(eject),
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
        // écriture (phase 3)
        .sec_we(sec_we), .sec_wr_data(sec_wr_data), .wr_commit(wr_commit),
        .wr_busy(wr_busy), .wr_ok(wr_ok), .wr_err(wr_err),
        .wblk_start(d_wblk_start), .wblk_idx(d_wblk_idx),
        .wblk_offset(d_wblk_offset), .wblk_data(d_wblk_data),
        .wblk_pos(d_wblk_pos), .wblk_done(d_wblk_done), .wblk_error(d_wblk_error)
    );

    integer errors = 0, i;
    reg [7:0] rb;

    // (re)charge une piste depuis la SD en forçant un aller-retour
    task load_track(input [6:0] trk);
        begin
            req_track = (trk == 7'd0) ? 7'd2 : 7'd0;  // piste différente d'abord
            @(negedge clk); wait (trk_loading === 1'b1); wait (trk_loading === 1'b0);
            req_track = trk;
            @(negedge clk); wait (trk_loading === 1'b1); wait (trk_loading === 1'b0);
        end
    endtask

    // lit un octet de secteur servi depuis tbuf
    task read_byte(input [4:0] s, input [8:0] off, output [7:0] v);
        begin
            @(negedge clk); sec_id = s; sec_addr = off;
            @(negedge clk); @(negedge clk); @(negedge clk);
            v = sec_byte;
        end
    endtask

    initial begin
        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);

        // insertion -> piste 0 chargée (attendre le cycle de chargement complet)
        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        wait (trk_loading === 1'b1); wait (trk_loading === 1'b0);
        if (bad_format) begin $display("FAIL: bad_format"); errors=errors+1; end
        $display("insere + piste 0 chargee (n_tracks=%0d)", n_tracks);

        // 1) données d'origine du secteur 1 (motif (0*32+1)^i = 1^i)
        sec_id = 5'd1; @(negedge clk); @(negedge clk);
        if (sec_valid !== 1'b1) begin $display("FAIL: s1 non valide apres chargement"); errors=errors+1; end
        read_byte(5'd1, 9'd0, rb);
        if (rb !== 8'd1) begin $display("FAIL: orig s1 b0 = %02x (att 01)", rb); errors=errors+1; end
        else $display("orig s1 b0 = 01 OK");

        // 2) écrire un nouveau motif dans le secteur 1 (0xC3 ^ i)
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk);
            sec_id = 5'd1; sec_addr = i[8:0]; sec_wr_data = 8'hC3 ^ i[7:0];
            sec_we = 1'b1;
            @(negedge clk); sec_we = 1'b0;
        end

        $display("256 octets ecrits dans tbuf (secteur 1)");

        // 3) commit -> write-back vers la SD
        req_track = 7'd0; req_side = 1'b0;
        @(negedge clk); wr_commit = 1'b1; @(negedge clk); wr_commit = 1'b0;
        wait (wr_busy === 1'b1);
        $display("write-back en cours...");
        wait (wr_busy === 1'b0);
        if (wr_err) begin $display("FAIL: wr_err"); errors=errors+1; end
        $display("write-back termine");

        // 4) RECHARGER la piste 0 depuis la SD (invalide tbuf) et vérifier
        load_track(7'd0);
        $display("piste 0 rechargee depuis la SD");
        for (i = 0; i < 256; i = i + 1) begin
            read_byte(5'd1, i[8:0], rb);
            if (rb !== (8'hC3 ^ i[7:0]) && errors < 10) begin
                $display("FAIL: relu s1 b%0d = %02x (att %02x)", i, rb, 8'hC3 ^ i[7:0]);
                errors = errors + 1;
            end
        end
        $display("secteur 1 relu depuis SD = nouveau motif");

        // 5) un AUTRE secteur (2) doit rester intact (motif 2^i)
        for (i = 0; i < 256; i = i + 1) begin
            read_byte(5'd2, i[8:0], rb);
            if (rb !== (8'd2 ^ i[7:0]) && errors < 14) begin
                $display("FAIL: s2 corrompu b%0d = %02x (att %02x)", i, rb, 8'd2 ^ i[7:0]);
                errors = errors + 1;
            end
        end
        $display("secteur 2 intact (pas de corruption RMW)");

        if (errors == 0) $display("ALL TESTS PASSED (tb_dsk_write)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #4000000000; $display("FAIL: timeout"); $finish; end
endmodule
