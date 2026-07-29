// Testbench du port d'extension : une « cartouche » comportementale est
// branchée sur les broches et vérifie le protocole bus (lecture, écriture,
// tristate, ROMDIS/MAP/IRQ, reset drain ouvert).
`timescale 1ns/1ps

module tb_expansion;

    reg clk = 0, rst = 1;
    reg [4:0] tphase = 0;
    reg [15:0] bus_addr = 0;
    reg bus_we = 0;
    reg [7:0] bus_do = 0;
    reg sel_io_page = 0;

    wire [7:0] ext_din;
    wire ext_irq, ext_romdis, ext_map, ext_ioctl, ext_rst_req;

    wire [15:0] pin_a;
    wire [7:0]  pin_d;
    wire pin_rw, pin_phi2, pin_io_n, pin_rst_n;

    // Cartouche comportementale
    reg cart_irq_n = 1, cart_romdis_n = 1, cart_map_n = 1, cart_ioctl_n = 1;
    reg cart_pull_rst = 0;
    reg [7:0] cart_reg = 8'hA7;      // registre lu à $0314
    reg [7:0] cart_written;

    wire cart_sel = (pin_a == 16'h0314) && !pin_io_n;
    wire cart_oe  = cart_sel && pin_rw && pin_phi2;
    assign pin_d = cart_oe ? cart_reg : 8'bz;
    assign pin_rst_n = cart_pull_rst ? 1'b0 : 1'bz;

    pullup pu_rst (pin_rst_n);
    pullup pu_d0 (pin_d[0]); pullup pu_d1 (pin_d[1]);
    pullup pu_d2 (pin_d[2]); pullup pu_d3 (pin_d[3]);
    pullup pu_d4 (pin_d[4]); pullup pu_d5 (pin_d[5]);
    pullup pu_d6 (pin_d[6]); pullup pu_d7 (pin_d[7]);

    always @(negedge pin_phi2)
        if (cart_sel && !pin_rw)
            cart_written <= pin_d;    // la cartouche latche en fin de Φ2

    expansion_port dut (
        .clk(clk), .rst(rst), .tphase(tphase),
        .bus_addr(bus_addr), .bus_we(bus_we), .bus_do(bus_do),
        .sel_io_page(sel_io_page),
        .ext_din(ext_din), .ext_irq(ext_irq), .ext_romdis(ext_romdis),
        .ext_map(ext_map), .ext_ioctl(ext_ioctl), .ext_rst_req(ext_rst_req),
        .pin_a(pin_a), .pin_d(pin_d), .pin_rw(pin_rw), .pin_phi2(pin_phi2),
        .pin_io_n(pin_io_n), .pin_rst_n(pin_rst_n),
        .pin_irq_n(cart_irq_n), .pin_romdis_n(cart_romdis_n),
        .pin_map_n(cart_map_n), .pin_ioctl_n(cart_ioctl_n)
    );

    always #20 clk = ~clk;   // 25 MHz
    always @(posedge clk)
        tphase <= rst ? 5'd0 : (tphase == 5'd24 ? 5'd0 : tphase + 5'd1);

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    task full_cycle; begin wait (tphase == 5'd24); wait (tphase == 5'd0); end endtask

    initial begin
        repeat (6) @(negedge clk);
        rst = 0;

        // Lecture d'un registre cartouche à $0314
        wait (tphase == 5'd0);
        bus_addr = 16'h0314; bus_we = 0; sel_io_page = 1;
        full_cycle;
        check(ext_din == 8'hA7, "lecture registre cartouche = A7");

        // Écriture vers la cartouche
        wait (tphase == 5'd0);
        bus_addr = 16'h0314; bus_we = 1; bus_do = 8'h5C;
        full_cycle;
        check(cart_written == 8'h5C, "ecriture cartouche = 5C");
        bus_we = 0;

        // Bus de données relâché hors écriture (pull-up -> FF hors sélection)
        wait (tphase == 5'd0);
        bus_addr = 16'h1234; sel_io_page = 0;
        full_cycle;
        check(ext_din == 8'hFF, "bus libre = FF (pull-up)");

        // Lignes cartouche -> synchroniseurs
        cart_romdis_n = 0; cart_map_n = 0; cart_irq_n = 0; cart_ioctl_n = 0;
        repeat (4) @(negedge clk);
        check(ext_romdis && ext_map && ext_irq && ext_ioctl,
              "ROMDIS/MAP/IRQ/IOCTL synchronises");
        cart_romdis_n = 1; cart_map_n = 1; cart_irq_n = 1; cart_ioctl_n = 1;
        repeat (4) @(negedge clk);
        check(!ext_romdis && !ext_map && !ext_irq && !ext_ioctl,
              "lignes relachees");

        // Reset drain ouvert tiré par la cartouche
        cart_pull_rst = 1;
        repeat (4) @(negedge clk);
        check(ext_rst_req, "reset cartouche detecte");
        cart_pull_rst = 0;
        repeat (4) @(negedge clk);
        check(!ext_rst_req, "reset relache");
        check(pin_rst_n == 1'b1, "pull-up reset au repos");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_expansion)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
