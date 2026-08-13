// Testbench du moteur SPI octet (rtl/spi_byte.v). Boucle MISO=MOSI : l'octet
// reçu doit être identique à l'octet émis, ce qui valide à la fois la
// présentation MOSI et l'échantillonnage MISO au bon front.
`timescale 1ns/1ps

module tb_spi_byte;

    reg clk = 0;
    always #10 clk = ~clk;

    reg        rst = 1;
    reg        start = 0;
    reg        fast = 0;
    reg  [7:0] tx = 0;
    wire [7:0] rx;
    wire       busy, done, sck, mosi;
    wire       miso = mosi;          // loopback

    // HALF_FAST minimum = 2 : mosi doit être présenté un cycle avant le
    // front montant de sck (à 1, présentation et échantillon se confondent).
    spi_byte #(.HALF(4), .HALF_FAST(2)) dut (
        .clk(clk), .rst(rst), .fast(fast), .start(start), .tx(tx), .rx(rx),
        .busy(busy), .done(done), .sck(sck), .mosi(mosi), .miso(miso)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s (rx=%02x tx=%02x)", msg, rx, tx); errors = errors + 1; end
    endtask

    task xfer(input [7:0] v);
        begin
            @(negedge clk); tx = v; start = 1;
            @(negedge clk); start = 0;
            @(posedge done);
            @(negedge clk);
            check(rx === v, "loopback octet");
        end
    endtask

    initial begin
        rst = 1; repeat (4) @(negedge clk); rst = 0;
        xfer(8'hA5);
        xfer(8'h00);
        xfer(8'hFF);
        xfer(8'h3C);
        xfer(8'h81);
        xfer(8'h7E);
        // Vitesse rapide (post-init) : mêmes octets, demi-période HALF_FAST
        fast = 1;
        xfer(8'hA5);
        xfer(8'h5A);
        xfer(8'hFF);
        // Retour lent : la vitesse est figée au lancement de l'octet
        fast = 0;
        xfer(8'h3C);
        if (errors == 0)
            $display("ALL TESTS PASSED (tb_spi_byte)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #1_000_000; $display("FAIL: timeout"); $finish;
    end

endmodule
