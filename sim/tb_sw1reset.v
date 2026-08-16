// Vérifie l'anti-rebond du reset-auto SW1 (rtl/top_ulx3s.v) : un interrupteur
// mécanique qui rebondit ne doit PAS générer de resets en boucle (bug du
// 2026-08-16), un basculement propre doit donner UN reset, et SW1 OFF au boot
// aucun. Logique recopiée à l'identique du top (DEB réduit pour la sim).
`timescale 1ns/1ps

module tb_sw1reset;
    reg clk = 0; always #5 clk = ~clk;   // 100 MHz sim
    reg sw = 0;

    // --- logique identique au top (DEB=20 au lieu de 250000 pour la sim) ---
    localparam DEB = 20;
    reg [1:0]  sw0_sync = 2'b00;
    reg [9:0]  sw0_deb  = 0;
    reg        sw0_stable = 1'b0, sw0_prev = 1'b0;
    reg [9:0]  sw0_rst  = 0;
    always @(posedge clk) begin
        sw0_sync <= {sw0_sync[0], sw};
        if (sw0_sync[1] == sw0_stable)
            sw0_deb <= 0;
        else if (sw0_deb == DEB) begin
            sw0_stable <= sw0_sync[1];
            sw0_deb    <= 0;
        end else
            sw0_deb <= sw0_deb + 10'd1;
        sw0_prev <= sw0_stable;
        if (sw0_stable != sw0_prev)
            sw0_rst <= 10'd60;                 // impulsion reset
        else if (sw0_rst != 0)
            sw0_rst <= sw0_rst - 10'd1;
    end

    // compte les fronts montants de (sw0_rst != 0) = nombre de resets déclenchés
    reg rst_a = 0;
    integer resets = 0;
    always @(posedge clk) begin
        rst_a <= (sw0_rst != 0);
        if ((sw0_rst != 0) && !rst_a) resets = resets + 1;
    end

    integer errors = 0;
    task expect(input [31:0] got, input [31:0] exp, input [255:0] msg);
        if (got !== exp) begin
            $display("FAIL: %0s (got %0d, exp %0d)", msg, got, exp);
            errors = errors + 1;
        end
    endtask

    initial begin
        sw = 0;
        repeat (60) @(posedge clk);
        expect(resets, 0, "SW1 OFF au boot : aucun reset");

        // Basculement PROPRE OFF->ON
        sw = 1;
        repeat (80) @(posedge clk);
        expect(resets, 1, "bascule propre ON : 1 reset");

        // Basculement PROPRE ON->OFF
        sw = 0;
        repeat (80) @(posedge clk);
        expect(resets, 2, "bascule propre OFF : 2e reset");

        // Basculement REBONDISSANT OFF->ON (rebonds < fenêtre anti-rebond)
        repeat (8) begin sw = 1; repeat (3) @(posedge clk); sw = 0; repeat (3) @(posedge clk); end
        sw = 1;                         // se stabilise à ON
        repeat (80) @(posedge clk);
        expect(resets, 3, "bascule rebondissante : UN SEUL reset (pas de boucle)");

        if (errors == 0) $display("ALL TESTS PASSED (tb_sw1reset)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
