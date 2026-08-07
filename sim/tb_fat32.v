// Testbench du parseur FAT32 (rtl/fat32.v) : le pilote SD (rtl/sd_spi.v) lit une
// image FAT32 réelle (générée par tools/gen_fat_test.py) servie par
// sim/sd_card_file.v. On vérifie que le parseur liste les bons fichiers .TAP/.DSK
// du répertoire racine (README.TXT ignoré), via une table MBR.
`timescale 1ns/1ps

module tb_fat32;

    reg clk = 0;
    always #10 clk = ~clk;
    reg rst = 1;

    // Pilote SD <-> parseur
    wire        rd_start;
    wire [31:0] rd_sector;
    wire        sd_ready, sd_busy, sd_error, sd_dvalid;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start), .sector(rd_sector),
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

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(q_idx), .q_name(q_name), .q_size(q_size), .q_clus(q_clus), .q_isdsk(q_isdsk)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    initial begin
        rst = 1; fat_start = 0; q_idx = 0;
        repeat (4) @(negedge clk); rst = 0;

        wait (sd_ready === 1'b1);          // init SD
        @(negedge clk); fat_start = 1;
        @(negedge clk); fat_start = 0;

        wait (fat_done === 1'b1);
        $display("PARSE OK (status=%02x, %0d fichiers)", fat_status, file_count);

        check(!fat_error, "parsing sans erreur");
        check(file_count === 8'd3, "3 fichiers .tap/.dsk (README.TXT ignoré)");

        q_idx = 0; #1;
        check(q_name === "DEFENDERTAP", "fichier 0 = DEFENDER.TAP");
        check(q_isdsk === 1'b0, "fichier 0 = TAP");
        check(q_size === 32'd58683, "taille fichier 0");

        q_idx = 1; #1;
        check(q_name === "CITADEL TAP", "fichier 1 = CITADEL.TAP");

        q_idx = 2; #1;
        check(q_name === "ORICCHESDSK", "fichier 2 = ORICCHES.DSK");
        check(q_isdsk === 1'b1, "fichier 2 = DSK");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_fat32)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #200_000_000; $display("FAIL: timeout (status=%02x)", fat_status); $finish;
    end

endmodule
