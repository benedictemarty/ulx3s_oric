// Test écriture de bloc SD (US-DISK.5 phase 1) : sd_spi CMD24 -> modèle
// sd_card_file (écrit dans l'image) -> relecture CMD17 -> vérification.
// Image de départ remplie de 0xEE ; on écrit un motif à un LBA, on relit.
`timescale 1ns/1ps

module tb_sd_write;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;

    reg        start_read = 0, start_write = 0;
    reg [31:0] sector = 0;
    wire       ready, busy, error, data_valid;
    wire [7:0] data, status;
    wire [8:0] wr_idx;
    wire       sck, mosi, miso, cs_n;

    // Source des octets à écrire : motif déterministe (LBA-dépendant)
    reg  [7:0] wbuf [0:511];
    wire [7:0] wr_data = wbuf[wr_idx];

    sd_spi #(.HALF(2)) dut (
        .clk(clk), .rst(rst),
        .start_read(start_read), .start_write(start_write), .sector(sector),
        .wr_data(wr_data), .wr_idx(wr_idx),
        .ready(ready), .busy(busy), .error(error),
        .data(data), .data_valid(data_valid), .status(status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );
    sd_card_file #(.IMG("sim/out/wr_test.img")) card (
        .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso)
    );

    integer errors = 0, i;
    reg [7:0] rdbuf [0:511];
    integer rp;

    // capture des octets lus
    always @(posedge clk)
        if (data_valid && rp < 512) begin rdbuf[rp] = data; rp = rp + 1; end

    localparam LBA = 32'd7;

    initial begin
        // motif à écrire
        for (i = 0; i < 512; i = i + 1) wbuf[i] = (i * 3 + 17) & 8'hFF;

        repeat (8) @(negedge clk); rst = 0;
        wait (ready === 1'b1);
        @(negedge clk);

        // --- écriture du bloc LBA ---
        sector = LBA;
        @(negedge clk); start_write = 1; @(negedge clk); start_write = 0;
        wait (busy === 1'b1);
        wait (busy === 1'b0);
        if (error) begin $display("FAIL: erreur pendant l'ecriture (status %02x)", status); errors=errors+1; end
        @(negedge clk);

        // --- relecture du bloc LBA ---
        rp = 0;
        sector = LBA;
        @(negedge clk); start_read = 1; @(negedge clk); start_read = 0;
        wait (busy === 1'b1);
        wait (busy === 1'b0);

        // --- vérification ---
        if (rp != 512) begin $display("FAIL: %0d octets relus (attendu 512)", rp); errors=errors+1; end
        for (i = 0; i < 512; i = i + 1)
            if (rdbuf[i] !== wbuf[i] && errors < 10) begin
                $display("FAIL: octet %0d : relu %02x ecrit %02x", i, rdbuf[i], wbuf[i]);
                errors = errors + 1;
            end

        if (errors == 0) $display("ALL TESTS PASSED (tb_sd_write : ecriture+relecture OK)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #500000000; $display("TIMEOUT"); $finish; end
endmodule
