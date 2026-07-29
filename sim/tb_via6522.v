// Testbench VIA 6522 : timers T1/T2, IFR/IER, ports, PCR (CA2/CB2 manuels).
`timescale 1ns/1ps

module tb_via6522;

    reg clk = 0, rst = 1;
    reg [3:0] addr = 0;
    reg cs = 0, we = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    wire irq;
    reg [7:0] pa_in = 8'hFF, pb_in = 8'hFF;
    wire [7:0] pa_out, pb_out, ddra, ddrb;
    wire ca2, cb2;

    via6522 dut (
        .clk(clk), .cen(1'b1), .rst(rst),
        .addr(addr), .cs(cs), .we(we), .din(din), .dout(dout), .irq(irq),
        .pa_in(pa_in), .pa_out(pa_out), .ddra_o(ddra),
        .pb_in(pb_in), .pb_out(pb_out), .ddrb_o(ddrb),
        .ca1_in(1'b1), .ca2_out(ca2), .cb1_in(1'b1), .cb2_out(cb2)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    integer i, t_irq1, t_irq2;

    task wr(input [3:0] a, input [7:0] d);
        begin
            @(negedge clk);
            addr = a; din = d; cs = 1; we = 1;
            @(negedge clk);
            cs = 0; we = 0;
        end
    endtask

    task rd(input [3:0] a, output [7:0] d);
        begin
            @(negedge clk);
            addr = a; cs = 1; we = 0;
            @(negedge clk);
            d = dout;          // dout registré : valide après un front
            cs = 0;
        end
    endtask

    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    reg [7:0] v;

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // --- Ports : DDRB sortie, écriture ORB
        wr(4'h2, 8'hFF);          // DDRB = sorties
        wr(4'h0, 8'hA5);
        check(pb_out == 8'hA5, "ORB -> PB");

        // --- PB en entrée : lecture reflète pb_in
        wr(4'h2, 8'h07);          // PB0-2 sorties, reste entrées
        pb_in = 8'h08;            // sense PB3 haut
        wr(4'h0, 8'h05);
        rd(4'h0, v);
        check(v[3] == 1'b1 && v[2:0] == 3'b101, "lecture PB mixte");

        // --- CA2/CB2 manuels via PCR
        wr(4'hC, 8'hCC);          // CA2 mode 110 (bas), CB2 mode 110 (bas)
        check(ca2 == 1'b0 && cb2 == 1'b0, "PCR modes 110 -> bas");
        wr(4'hC, 8'hEE);          // CA2 mode 111 (haut), CB2 mode 111 (haut)
        check(ca2 == 1'b1 && cb2 == 1'b1, "PCR modes 111 -> haut");

        // --- T1 free-run : période N+1 approx, IRQ périodique
        wr(4'hB, 8'h40);          // ACR bit6 = free-run
        wr(4'hE, 8'hC0);          // IER : set T1
        wr(4'h4, 8'd100);         // T1L low
        wr(4'h5, 8'd0);           // T1C high -> lance
        check(irq == 1'b0, "IRQ basse au lancement T1");
        i = 0;
        while (!irq && i < 300) begin @(negedge clk); i = i + 1; end
        t_irq1 = i;
        check(irq == 1'b1, "IRQ T1 levée");
        rd(4'h4, v);              // lecture T1CL efface le flag
        check(irq == 1'b0, "lecture T1CL efface IRQ");
        i = 0;
        while (!irq && i < 300) begin @(negedge clk); i = i + 1; end
        t_irq2 = i;
        check(t_irq2 >= 99 && t_irq2 <= 105, "période T1 free-run ~101 cycles");

        // --- IFR write-1-to-clear
        wr(4'hD, 8'h40);
        check(irq == 1'b0, "IFR write-1-clear");

        // --- T2 one-shot : une seule IRQ (T1 free-run coupé d'abord)
        wr(4'hE, 8'h40);          // IER : clear T1
        wr(4'hE, 8'hA0);          // IER : set T2
        wr(4'h8, 8'd50);          // T2 low latch
        wr(4'h9, 8'd0);           // lance T2
        i = 0;
        while (!irq && i < 200) begin @(negedge clk); i = i + 1; end
        check(irq == 1'b1, "IRQ T2 levée");
        rd(4'h8, v);              // efface flag T2
        check(irq == 1'b0, "lecture T2CL efface IRQ");
        for (i = 0; i < 400; i = i + 1) @(negedge clk);
        check(irq == 1'b0, "T2 one-shot : pas de 2e IRQ");

        // --- IER masque
        wr(4'h4, 8'd10);
        wr(4'h5, 8'd0);           // relance T1 (IER T1 toujours actif)
        wr(4'hE, 8'h40);          // IER : clear T1
        for (i = 0; i < 50; i = i + 1) @(negedge clk);
        check(irq == 1'b0, "IER masque T1");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_via6522)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
