// Test écriture fat32 à un offset (US-DISK.5 phase 2) : écrit un bloc de 512
// octets à l'offset 8192 (3e cluster, exerce le suivi de chaîne FAT) du
// fichier 5 (TESTMFM.DSK), puis relit par le chemin de lecture et vérifie.
`timescale 1ns/1ps

module tb_fat_write;
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

    // ---- fat32 ----
    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    // lecture
    reg         open_start = 0;
    reg  [5:0]  open_idx = 0;
    reg  [31:0] open_offset = 0;
    reg         fdata_ready = 0;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;
    // écriture
    reg         wblk_start = 0;
    reg  [5:0]  wblk_idx = 0;
    reg  [31:0] wblk_offset = 0;
    wire [8:0]  wblk_pos;
    wire        wblk_done, wblk_error;

    // source des octets à écrire : motif déterministe
    reg  [7:0]  wbuf [0:511];
    wire [7:0]  wblk_data = wbuf[wblk_pos];

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd0), .q_name(), .q_size(), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(),
        .q3_idx(6'd0), .q3_name(),
        .open_start(open_start), .open_idx(open_idx),
        .open_offset(open_offset), .open_abort(1'b0),
        .fdata_ready(fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(wblk_start), .wblk_idx(wblk_idx), .wblk_offset(wblk_offset),
        .wblk_data(wblk_data), .wblk_pos(wblk_pos),
        .wblk_done(wblk_done), .wblk_error(wblk_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    integer errors = 0, i, rp;
    reg [7:0] rdbuf [0:511];

    localparam FIDX = 6'd5;          // TESTMFM.DSK (comme tb_dsk)
    localparam OFF  = 32'd8192;      // 3e cluster (spc=8 -> 4096/cluster)

    initial begin
        for (i=0;i<512;i=i+1) wbuf[i] = (i*7 + 3) & 8'hFF;

        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("fat: %0d fichier(s)", file_count);

        // --- écriture d'un bloc à l'offset ---
        wblk_idx = FIDX; wblk_offset = OFF;
        @(negedge clk); wblk_start = 1; @(negedge clk); wblk_start = 0;
        wait (wblk_done === 1'b1);
        if (wblk_error) begin $display("FAIL: wblk_error"); errors=errors+1; end
        $display("ecriture terminee");

        // --- relecture par le chemin de lecture ---
        @(negedge clk);
        open_idx = FIDX; open_offset = OFF;
        @(negedge clk); open_start = 1; @(negedge clk); open_start = 0;
        rp = 0;
        while (rp < 512 && !feof) begin
            fdata_ready = 1;
            @(negedge clk);
            if (fdata_valid) begin rdbuf[rp] = fdata; rp = rp + 1; end
        end
        fdata_ready = 0;

        if (rp < 512) begin $display("FAIL: %0d octets relus", rp); errors=errors+1; end
        for (i=0;i<512;i=i+1)
            if (rdbuf[i] !== wbuf[i] && errors < 10) begin
                $display("FAIL: octet %0d : relu %02x ecrit %02x", i, rdbuf[i], wbuf[i]);
                errors = errors + 1;
            end

        if (errors == 0) $display("ALL TESTS PASSED (tb_fat_write : ecriture offset + relecture OK)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
