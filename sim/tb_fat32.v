// Testbench du parseur FAT32 (rtl/fat32.v) + lecture de fichier. Le pilote SD
// lit une image FAT32 réelle (tools/gen_fat_test.py) via sim/sd_card_file.v.
// Vérifie : (1) le listing des .TAP/.DSK ; (2) la lecture du fichier TEST.TAP
// (600 octets sur 2 clusters chaînés) restitue le motif i&0xFF.
`timescale 1ns/1ps

module tb_fat32;

    reg clk = 0;
    always #10 clk = ~clk;
    reg rst = 1;

    wire        rd_start;
    wire [31:0] rd_sector;
    wire        sd_ready, sd_busy, sd_error, sd_dvalid;
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

    reg         fat_start;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    reg  [5:0]  q_idx;
    wire [87:0] q_name;
    wire [31:0] q_size, q_clus;
    wire        q_isdsk;
    reg         open_start;
    reg  [5:0]  open_idx;
    reg         fdata_ready;
    wire        floading, feof;
    wire [7:0]  fdata;
    wire        fdata_valid;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(q_idx), .q_name(q_name), .q_size(q_size), .q_clus(q_clus), .q_isdsk(q_isdsk),
        .open_start(open_start), .open_idx(open_idx), .open_offset(32'd0), .open_abort(1'b0), .fdata_ready(fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(1'b0), .wblk_idx(6'd0), .wblk_offset(32'd0),
        .wblk_data(8'd0), .wr_idx(9'd0),
        .wblk_pos(), .wblk_done(), .wblk_error(), .wr_start(), .wr_data()
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    // Capture du flux de fichier
    integer fi = 0, fbad = 0;
    always @(posedge clk) if (fdata_valid) begin
        if (fdata !== (fi & 8'hFF)) fbad = fbad + 1;
        fi = fi + 1;
    end

    initial begin
        rst = 1; fat_start = 0; q_idx = 0; open_start = 0; open_idx = 0; fdata_ready = 0;
        repeat (4) @(negedge clk); rst = 0;

        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1;
        @(negedge clk); fat_start = 0;

        wait (fat_done === 1'b1);
        $display("PARSE OK (status=%02x, %0d fichiers)", fat_status, file_count);
        check(!fat_error, "parsing sans erreur");
        check(file_count === 8'd8, "8 fichiers .tap/.dsk (README.TXT ignoré ; SAVE.TAP inclus)");

        q_idx = 0; #1; check(q_name === "DEFENDERTAP", "fichier 0 = DEFENDER.TAP");
        q_idx = 2; #1; check(q_name === "ORICCHESDSK" && q_isdsk, "fichier 2 = ORICCHES.DSK");
        q_idx = 3; #1; check(q_name === "TEST    TAP" && q_size===32'd600, "fichier 3 = TEST.TAP 600o");

        // ---- lecture du fichier TEST.TAP (index 3) ----
        fdata_ready = 1'b1;
        @(negedge clk); open_idx = 3; open_start = 1'b1;
        @(negedge clk); open_start = 1'b0;

        wait (feof === 1'b1);
        @(negedge clk);
        check(fi === 600, "600 octets lus");
        check(fbad === 0, "contenu conforme au motif");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_fat32)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #400_000_000; $display("FAIL: timeout (status=%02x fi=%0d)", fat_status, fi); $finish;
    end

endmodule
