// Testbench 6551 ACIA : accès registres côté CPU (cadencés cen), pont série
// (TX capté, RX injecté), TDRE/RDRF/OVRN et IRQ.
`timescale 1ns/1ps

module tb_acia;

    reg        clk = 0, rst = 1;
    reg        cen = 0, cs = 0, we = 0;
    reg  [1:0] addr = 0;
    reg  [7:0] din = 0;
    wire [7:0] dout;
    wire       irq;
    reg        dcd = 0, dsr = 0;
    wire [7:0] tx_data;
    wire       tx_send;
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0;

    acia6551 dut (
        .clk(clk), .rst(rst), .cen(cen), .cs(cs), .we(we), .addr(addr),
        .din(din), .dout(dout), .irq(irq), .dcd(dcd), .dsr(dsr),
        .tx_data(tx_data), .tx_send(tx_send), .tx_busy(1'b0),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    // Capture du dernier octet émis vers l'ESP32
    reg [7:0] tx_byte = 0; reg tx_seen = 0;
    always @(posedge clk) if (tx_send) begin tx_seen <= 1; tx_byte <= tx_data; end

    task bus_write(input [1:0] a, input [7:0] v);
        begin
            @(negedge clk); cs = 1; we = 1; addr = a; din = v;
            cen = 1; @(negedge clk); cen = 0; cs = 0; we = 0;
            @(negedge clk);
        end
    endtask

    reg [7:0] rd;
    task bus_read(input [1:0] a);
        begin
            @(negedge clk); cs = 1; we = 0; addr = a;
            @(negedge clk); rd = dout;            // échantillon (combinatoire)
            cen = 1; @(negedge clk); cen = 0; cs = 0;  // applique l'effet de bord
            @(negedge clk);
        end
    endtask

    task rx_push(input [7:0] b);
        begin @(negedge clk); rx_data = b; rx_valid = 1; @(negedge clk); rx_valid = 0; @(negedge clk); end
    endtask

    initial begin
        repeat (4) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

        // Reset : TDRE=1 (0x10), RDRF=0
        bus_read(2'd1);
        check(rd[4] == 1'b1, "reset : TDRE=1");
        check(rd[3] == 1'b0, "reset : RDRF=0");

        // Registres command/control lisibles
        bus_write(2'd3, 8'h1E); bus_read(2'd3);
        check(rd == 8'h1E, "control relu");
        bus_write(2'd2, 8'h09); bus_read(2'd2);
        check(rd == 8'h09, "command relu");

        // TX : écriture data -> octet émis vers l'ESP32
        tx_seen = 0;
        bus_write(2'd0, 8'h41);
        repeat (4) @(negedge clk);
        check(tx_seen && tx_byte == 8'h41, "TX : 0x41 emis vers ESP32");

        // RX : octet recu -> RDRF, lecture data
        rx_push(8'h55);
        bus_read(2'd1); check(rd[3] == 1'b1, "RX : RDRF=1");
        bus_read(2'd0); check(rd == 8'h55, "RX : data = 0x55");
        bus_read(2'd1); check(rd[3] == 1'b0, "RX : RDRF efface apres lecture");

        // Overrun : deux octets sans lecture -> OVRN
        rx_push(8'h11); rx_push(8'h22);
        bus_read(2'd1); check(rd[2] == 1'b1, "OVRN=1 sur debordement");
        bus_read(2'd0); check(rd == 8'h11, "data = premier octet (0x11)");
        bus_read(2'd1); check(rd[2] == 1'b0, "OVRN efface apres lecture data");

        // IRQ RX : command IRD=0 (RX IRQ actif)
        bus_write(2'd2, 8'h00);
        rx_push(8'h7E);
        check(irq == 1'b1, "IRQ actif sur RDRF");
        bus_read(2'd1);
        check(rd[7] == 1'b1, "STATUS bit7 (IRQ) lu a 1");
        check(irq == 1'b0, "IRQ acquitte par lecture STATUS");
        bus_read(2'd0);   // vide le RDR

        // IRD=1 : RX n'arme plus l'IRQ
        bus_write(2'd2, 8'h02);
        rx_push(8'h5A);
        check(irq == 1'b0, "IRD=1 : pas d'IRQ sur RDRF");

        if (errors == 0) $display("ALL TESTS PASSED (tb_acia)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
