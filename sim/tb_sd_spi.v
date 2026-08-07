// Testbench du pilote carte SD (rtl/sd_spi.v) avec un modèle de carte SD
// comportemental (sim/sd_card_model.v). Vérifie : l'init aboutit (ready), puis
// la lecture du secteur 0 restitue le motif attendu (dont signature 0x55AA).
`timescale 1ns/1ps

module tb_sd_spi;

    reg clk = 0;
    always #10 clk = ~clk;

    reg        rst = 1;
    reg        start_read = 0;
    reg [31:0] sector = 0;
    wire       ready, busy, error, data_valid;
    wire [7:0] data, status;
    wire       sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) dut (
        .clk(clk), .rst(rst), .start_read(start_read), .sector(sector),
        .ready(ready), .busy(busy), .error(error),
        .data(data), .data_valid(data_valid), .status(status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );

    sd_card_model card (.cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso));

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    reg [7:0] captured [0:511];
    integer   cap = 0;
    always @(posedge clk) if (data_valid) begin captured[cap] = data; cap = cap + 1; end

    integer i, bad;

    initial begin
        rst = 1; repeat (4) @(negedge clk); rst = 0;

        // Attendre la fin de l'init
        wait (ready === 1'b1);
        check(!error, "init sans erreur");
        $display("INIT OK (status=%02x)", status);

        // Lire le secteur 0
        @(negedge clk); sector = 0; start_read = 1;
        @(negedge clk); start_read = 0;

        wait (cap == 512);

        // Vérifier le motif complet : octet i = i[7:0], sauf 510/511 = 55/AA
        bad = 0;
        for (i = 0; i < 512; i = i + 1)
            if (captured[i] !== ((i==510)?8'h55:(i==511)?8'hAA:i[7:0]))
                bad = bad + 1;
        check(bad == 0, "motif 512 octets conforme");
        check(captured[510] === 8'h55, "signature 0x55");
        check(captured[511] === 8'hAA, "signature 0xAA");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_sd_spi)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #50_000_000; $display("FAIL: timeout (status=%02x error=%b)", status, error); $finish;
    end

endmodule
