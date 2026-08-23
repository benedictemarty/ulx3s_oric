// Test de la création d'entrée de répertoire FAT32 (US-CSAVE.4 phase B).
// Alloue un cluster, crée l'entrée "NEWSAVE TAP" pointant dessus (taille 1234),
// vérifie le listing en mémoire, puis RE-PARSE l'image : le fichier doit
// réapparaître avec le bon nom / cluster / taille — ce qui prouve que l'entrée
// a bien été écrite et persistée sur la carte.
`timescale 1ns/1ps

module tb_fat_mkent;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;

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

    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;

    reg         alloc_start = 0;
    wire [31:0] alloc_clus;
    wire        alloc_done, alloc_error;

    reg         mkent_start = 0;
    reg  [87:0] mkent_name = 0;
    reg  [31:0] mkent_clus = 0, mkent_size = 0;
    wire [5:0]  mkent_idx;
    wire        mkent_done, mkent_error;

    reg  [5:0]  q_idx = 0;
    wire [87:0] q_name;
    wire [31:0] q_size, q_clus;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(q_idx), .q_name(q_name), .q_size(q_size), .q_clus(q_clus), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(),
        .q3_idx(6'd0), .q3_name(),
        .q4_idx(6'd0), .q4_name(),
        .open_start(1'b0), .open_idx(6'd0), .open_offset(32'd0), .open_abort(1'b0),
        .fdata_ready(1'b0), .floading(), .feof(), .fdata(), .fdata_valid(),
        .wblk_start(1'b0), .wblk_idx(6'd0), .wblk_offset(32'd0),
        .wblk_data(8'd0), .wblk_pos(), .wblk_done(), .wblk_error(),
        .dsize_start(1'b0), .dsize_idx(6'd0), .dsize_val(32'd0),
        .dsize_done(), .dsize_error(),
        .alloc_start(alloc_start), .alloc_prev(32'd0),
        .alloc_clus(alloc_clus), .alloc_done(alloc_done), .alloc_error(alloc_error),
        .mkent_start(mkent_start), .mkent_name(mkent_name),
        .mkent_clus(mkent_clus), .mkent_size(mkent_size),
        .mkent_idx(mkent_idx), .mkent_done(mkent_done), .mkent_error(mkent_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    integer errors = 0, i;
    reg [7:0]  fc0;
    reg [31:0] c1;
    reg [5:0]  nidx;
    integer found;

    localparam [87:0] NM = "NEWSAVE TAP";   // 11 caractères 8.3
    localparam [31:0] SZ = 32'd1234;

    task do_parse;
        begin
            @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
            wait (fat_done === 1'b1);
        end
    endtask

    initial begin
        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        do_parse; fc0 = file_count;
        $display("parse initial : %0d fichier(s)", fc0);

        // --- allouer un cluster ---
        @(negedge clk); alloc_start = 1; @(negedge clk); alloc_start = 0;
        wait (alloc_done === 1'b1); c1 = alloc_clus;
        if (alloc_error) begin $display("FAIL: alloc_error"); errors=errors+1; end

        // --- créer l'entrée de répertoire ---
        @(negedge clk);
        mkent_name = NM; mkent_clus = c1; mkent_size = SZ;
        @(negedge clk); mkent_start = 1; @(negedge clk); mkent_start = 0;
        wait (mkent_done === 1'b1);
        if (mkent_error) begin $display("FAIL: mkent_error"); errors=errors+1; end
        nidx = mkent_idx;
        $display("mkent : idx=%0d clus=%0d (file_count %0d->%0d)", nidx, c1, fc0, file_count);
        if (file_count !== fc0 + 8'd1) begin $display("FAIL: file_count non incremente"); errors=errors+1; end

        // --- listing en mémoire (sans re-parse) ---
        @(negedge clk); q_idx = nidx; @(negedge clk); @(negedge clk);
        if (q_name !== NM)  begin $display("FAIL: nom memoire %h != %h", q_name, NM); errors=errors+1; end
        if (q_clus !== c1)  begin $display("FAIL: cluster memoire %0d != %0d", q_clus, c1); errors=errors+1; end
        if (q_size !== SZ)  begin $display("FAIL: taille memoire %0d != %0d", q_size, SZ); errors=errors+1; end

        // --- RE-PARSE : le fichier doit être relu depuis l'image ---
        do_parse;
        $display("re-parse : %0d fichier(s)", file_count);
        if (file_count !== fc0 + 8'd1) begin $display("FAIL: re-parse compte %0d (attendu %0d)", file_count, fc0+1); errors=errors+1; end
        found = -1;
        for (i = 0; i < file_count; i = i + 1) begin
            q_idx = i[5:0]; @(negedge clk); @(negedge clk);
            if (q_name === NM) found = i;
        end
        if (found < 0) begin $display("FAIL: NEWSAVE.TAP absent apres re-parse"); errors=errors+1; end
        else begin
            q_idx = found[5:0]; @(negedge clk); @(negedge clk);
            $display("relu a l'index %0d : clus=%0d size=%0d", found, q_clus, q_size);
            if (q_clus !== c1) begin $display("FAIL: cluster relu %0d != %0d", q_clus, c1); errors=errors+1; end
            if (q_size !== SZ) begin $display("FAIL: taille relue %0d != %0d", q_size, SZ); errors=errors+1; end
        end

        if (errors == 0) $display("ALL TESTS PASSED (tb_fat_mkent)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
