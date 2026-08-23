// Test de l'extension de chaîne à la demande (US-CSAVE.4 phase C).
// Crée un fichier NEUF (alloc 1 cluster + entrée répertoire, taille 1536), puis
// écrit 3 blocs de 512 o à des offsets croissants avec wblk_extend=1 : les 2e
// et 3e blocs dépassent la fin de chaîne et forcent l'allocation d'un cluster
// supplémentaire. Relit ensuite le fichier et vérifie le contenu.
// SPC=1 dans l'image de test -> 1 bloc = 1 cluster, l'extension est exercée à
// chaque bloc après le premier.
`timescale 1ns/1ps

module tb_fat_extend;
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

    reg         wblk_start = 0;
    reg  [5:0]  wblk_idx = 0;
    reg  [31:0] wblk_offset = 0;
    wire [8:0]  wblk_pos;
    wire        wblk_done, wblk_error;
    reg  [7:0]  wbuf [0:511];
    wire [7:0]  wblk_data = wbuf[wblk_pos];

    reg         open_start = 0;
    reg  [5:0]  open_idx = 0;
    reg  [31:0] open_offset = 0;
    reg         fdata_ready = 0;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd0), .q_name(), .q_size(), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(),
        .q3_idx(6'd0), .q3_name(),
        .q4_idx(6'd0), .q4_name(),
        .open_start(open_start), .open_idx(open_idx), .open_offset(open_offset), .open_abort(1'b0),
        .fdata_ready(fdata_ready), .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(wblk_start), .wblk_idx(wblk_idx), .wblk_offset(wblk_offset),
        .wblk_data(wblk_data), .wblk_extend(1'b1), .wblk_pos(wblk_pos),
        .wblk_done(wblk_done), .wblk_error(wblk_error),
        .dsize_start(1'b0), .dsize_idx(6'd0), .dsize_val(32'd0),
        .dsize_done(), .dsize_error(),
        .alloc_start(alloc_start), .alloc_prev(32'd0),
        .alloc_clus(alloc_clus), .alloc_done(alloc_done), .alloc_error(alloc_error),
        .mkent_start(mkent_start), .mkent_name(mkent_name),
        .mkent_clus(mkent_clus), .mkent_size(mkent_size),
        .mkent_idx(mkent_idx), .mkent_done(mkent_done), .mkent_error(mkent_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    integer errors = 0, i, k, rp;
    reg [31:0] c1;
    reg [5:0]  fidx;
    reg [7:0]  rdbuf [0:1535];

    localparam [87:0] NM = "EXTEND  TAP";
    localparam NB = 3;                       // 3 blocs de 512 o

    function [7:0] pat(input integer blk, input integer off);
        pat = (blk*40 + off) & 8'hFF;
    endfunction

    initial begin
        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);

        // --- créer un fichier neuf : 1 cluster + entrée (taille = 3 blocs) ---
        @(negedge clk); alloc_start = 1; @(negedge clk); alloc_start = 0;
        wait (alloc_done === 1'b1); c1 = alloc_clus;
        @(negedge clk); mkent_name = NM; mkent_clus = c1; mkent_size = NB*512;
        @(negedge clk); mkent_start = 1; @(negedge clk); mkent_start = 0;
        wait (mkent_done === 1'b1);
        fidx = mkent_idx;
        $display("fichier cree : idx=%0d clus=%0d", fidx, c1);

        // --- écrire 3 blocs ; les blocs 1 et 2 étendent la chaîne ---
        for (k = 0; k < NB; k = k + 1) begin
            for (i = 0; i < 512; i = i + 1) wbuf[i] = pat(k, i);
            @(negedge clk); wblk_idx = fidx; wblk_offset = k*512;
            @(negedge clk); wblk_start = 1; @(negedge clk); wblk_start = 0;
            wait (wblk_done === 1'b1);
            if (wblk_error) begin $display("FAIL: wblk_error au bloc %0d", k); errors=errors+1; end
            @(negedge clk);
        end
        $display("3 blocs ecrits (extension de chaine)");

        // --- relire les 1536 octets et vérifier ---
        @(negedge clk); open_idx = fidx; open_offset = 0;
        @(negedge clk); open_start = 1; @(negedge clk); open_start = 0;
        rp = 0;
        while (rp < NB*512 && !feof) begin
            fdata_ready = 1;
            @(negedge clk);
            if (fdata_valid) begin rdbuf[rp] = fdata; rp = rp + 1; end
        end
        fdata_ready = 0;

        if (rp < NB*512) begin $display("FAIL: %0d octets relus (attendu %0d)", rp, NB*512); errors=errors+1; end
        for (i = 0; i < NB*512; i = i + 1)
            if (rdbuf[i] !== pat(i/512, i%512) && errors < 10) begin
                $display("FAIL: octet %0d : relu %02x attendu %02x", i, rdbuf[i], pat(i/512,i%512));
                errors = errors + 1;
            end

        if (errors == 0) $display("ALL TESTS PASSED (tb_fat_extend)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #4000000000; $display("TIMEOUT"); $finish; end
endmodule
