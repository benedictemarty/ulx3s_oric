// Testbench matrice clavier : HID -> matrice Oric -> sense PB3.
`timescale 1ns/1ps

module tb_keyboard;

    reg clk = 0;
    reg [7:0] mods = 0, k1 = 0, k2 = 0, k3 = 0, k4 = 0;
    reg [2:0] col_sel = 0;
    reg [7:0] ay_ioa = 8'hFF;
    wire sense;

    oric_keyboard dut (
        .clk(clk), .mods(mods), .k1(k1), .k2(k2), .k3(k3), .k4(k4),
        .col_sel(col_sel), .ay_ioa(ay_ioa), .sense(sense)
    );

    always #10 clk = ~clk;

    integer errors = 0;

    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    task settle; begin @(negedge clk); @(negedge clk); end endtask

    initial begin
        settle;

        // Aucune touche : sense bas quelle que soit la sélection
        col_sel = 3'd6; ay_ioa = 8'h00; settle;
        check(sense == 1'b0, "repos : sense bas");

        // 'A' HID 0x04 -> Oric (col 6, rangée 5)
        k1 = 8'h04;
        col_sel = 3'd6; ay_ioa = ~(8'h01 << 5); settle;
        check(sense == 1'b1, "A : col 6 rangée 5 detectee");
        ay_ioa = 8'hFF; settle;
        check(sense == 1'b0, "A : rangée non testée -> sense bas");
        col_sel = 3'd5; ay_ioa = ~(8'h01 << 5); settle;
        check(sense == 1'b0, "A : mauvaise colonne -> sense bas");
        k1 = 0;

        // RETURN HID 0x28 -> (7,5)
        k2 = 8'h28; col_sel = 3'd7; ay_ioa = ~(8'h01 << 5); settle;
        check(sense == 1'b1, "RETURN : col 7 rangée 5");
        k2 = 0;

        // Shift gauche (mods bit1) -> (4,4)
        mods = 8'h02; col_sel = 3'd4; ay_ioa = ~(8'h01 << 4); settle;
        check(sense == 1'b1, "LSHIFT : col 4 rangée 4");
        mods = 0;

        // Espace HID 0x2C -> (4,0), masque multi-rangées
        k3 = 8'h2C; col_sel = 3'd4; ay_ioa = 8'h00; settle;
        check(sense == 1'b1, "ESPACE : toutes rangées testées");
        k3 = 0;

        // Deux touches simultanées : 'N' (0,1) + '7' (0,0)
        k1 = 8'h11; k2 = 8'h24; col_sel = 3'd0; ay_ioa = ~(8'h01 << 1); settle;
        check(sense == 1'b1, "N détecté");
        ay_ioa = ~(8'h01 << 0); settle;
        check(sense == 1'b1, "7 détecté");
        ay_ioa = ~(8'h01 << 2); settle;
        check(sense == 1'b0, "rangée 2 vide");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_keyboard)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
