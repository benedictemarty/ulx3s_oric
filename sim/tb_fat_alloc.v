// Test de l'allocateur de cluster FAT32 (US-CSAVE.4 phase 1).
// Parse l'image, puis alloue 3 clusters CHAÎNÉS : alloc(prev=0)->c1,
// alloc(prev=c1)->c2, alloc(prev=c2)->c3.
//   - Preuve de persistance côté Verilog : alloc #2 renvoie c1+1 (et non c1) —
//     donc l'EOC de c1 a bien été écrit, persisté et relu par le scan suivant ;
//     idem c3=c2+1. Le scan + RMW FAT + persistance est ainsi validé e2e.
//   - Le chaînage prev->nouveau (FAT[c1]=c2, FAT[c2]=c3, FAT[c3]=EOC) est
//     vérifié par tools/check_fat_alloc.py sur l'image finale.
`timescale 1ns/1ps

module tb_fat_alloc;
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
    reg  [31:0] alloc_prev = 0;
    wire [31:0] alloc_clus;
    wire        alloc_done, alloc_error;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd0), .q_name(), .q_size(), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(),
        .q3_idx(6'd0), .q3_name(),
        .q4_idx(6'd0), .q4_name(),
        .open_start(1'b0), .open_idx(6'd0), .open_offset(32'd0), .open_abort(1'b0),
        .fdata_ready(1'b0), .floading(), .feof(), .fdata(), .fdata_valid(),
        .wblk_start(1'b0), .wblk_idx(6'd0), .wblk_offset(32'd0),
        .wblk_data(8'd0), .wblk_pos(), .wblk_done(), .wblk_error(),
        .dsize_start(1'b0), .dsize_idx(6'd0), .dsize_val(32'd0),
        .dsize_done(), .dsize_error(),
        .alloc_start(alloc_start), .alloc_prev(alloc_prev),
        .alloc_clus(alloc_clus), .alloc_done(alloc_done), .alloc_error(alloc_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    integer errors = 0;
    reg [31:0] c1, c2, c3;

    task do_alloc(input [31:0] prev, output [31:0] clus);
        begin
            @(negedge clk); alloc_prev = prev; alloc_start = 1;
            @(negedge clk); alloc_start = 0;
            wait (alloc_done === 1'b1);
            clus = alloc_clus;
            if (alloc_error) begin $display("FAIL: alloc_error (prev=%0d)", prev); errors=errors+1; end
        end
    endtask

    initial begin
        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("fat: %0d fichier(s)", file_count);

        do_alloc(32'd0, c1);
        do_alloc(c1,    c2);
        do_alloc(c2,    c3);
        $display("ALLOC %0d %0d %0d", c1, c2, c3);

        if (c1 == 0) begin $display("FAIL: c1 nul"); errors=errors+1; end
        if (c2 !== c1 + 32'd1) begin
            $display("FAIL: c2=%0d != c1+1 (%0d) -> EOC de c1 non persiste ?", c2, c1+1);
            errors=errors+1;
        end
        if (c3 !== c2 + 32'd1) begin
            $display("FAIL: c3=%0d != c2+1 (%0d)", c3, c2+1);
            errors=errors+1;
        end

        if (errors == 0) $display("ALL TESTS PASSED (tb_fat_alloc)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
