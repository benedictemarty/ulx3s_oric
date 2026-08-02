// Testbench disposition AZERTY : (scancode HID, Shift) -> ASCII FR -> matrice.
// Vérifie les permutations de lettres, les chiffres en Shift, les symboles
// nécessitant un Shift Oric, la non-propagation du Shift physique sur une
// lettre, le repli positionnel (Entrée) et la non-régression QWERTY.
`timescale 1ns/1ps

module tb_azerty;

    reg clk = 0;
    reg [7:0] mods = 0, k1 = 0, k2 = 0, k3 = 0, k4 = 0;
    reg [2:0] col_sel = 0;
    reg [7:0] ay_ioa = 8'hFF;
    reg       azerty = 1;
    wire sense;

    oric_keyboard dut (
        .clk(clk), .azerty(azerty), .mods(mods), .k1(k1), .k2(k2), .k3(k3), .k4(k4),
        .inj_active(1'b0), .inj_col(3'd0), .inj_row(3'd0), .inj_shift(1'b0),
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

    // La cellule (col,row) est-elle pressée dans la matrice ?
    task expect_cell(input [2:0] col, input [2:0] row, input [255:0] msg);
    begin
        col_sel = col; ay_ioa = ~(8'h01 << row); settle;
        check(sense == 1'b1, msg);
    end
    endtask

    task expect_nocell(input [2:0] col, input [2:0] row, input [255:0] msg);
    begin
        col_sel = col; ay_ioa = ~(8'h01 << row); settle;
        check(sense == 1'b0, msg);
    end
    endtask

    initial begin
        settle;

        // ---- Lettres permutées vs QWERTY ----
        // 0x14 (touche QWERTY Q) -> 'A' Oric (6,5)
        k1 = 8'h14; expect_cell(3'd6, 3'd5, "AZ 0x14 -> A (6,5)"); k1 = 0;
        // 0x04 (touche QWERTY A) -> 'Q' Oric (1,6)
        k1 = 8'h04; expect_cell(3'd1, 3'd6, "AZ 0x04 -> Q (1,6)"); k1 = 0;
        // 0x1A (QWERTY W) -> 'Z' (2,5)
        k1 = 8'h1A; expect_cell(3'd2, 3'd5, "AZ 0x1A -> Z (2,5)"); k1 = 0;
        // 0x1D (QWERTY Z) -> 'W' (6,7)
        k1 = 8'h1D; expect_cell(3'd6, 3'd7, "AZ 0x1D -> W (6,7)"); k1 = 0;
        // 0x33 (QWERTY ;) -> 'M' (2,0)
        k1 = 8'h33; expect_cell(3'd2, 3'd0, "AZ 0x33 -> M (2,0)"); k1 = 0;

        // ---- Une lettre ne doit PAS déclencher le Shift Oric, même Shift tenu ----
        k1 = 8'h14; mods = 8'h02;   // 'A' + LSHIFT physique
        expect_cell(3'd6, 3'd5, "AZ A+Shift : lettre presente");
        expect_nocell(3'd4, 3'd4, "AZ A+Shift : pas de Shift Oric parasite");
        k1 = 0; mods = 0;

        // ---- Rangée chiffres : symbole direct, chiffre en Shift ----
        // 0x1E sans Shift -> '&' = Shift+7 -> (0,0) + Shift Oric (4,4)
        k1 = 8'h1E;
        expect_cell(3'd0, 3'd0, "AZ & : 7 Oric (0,0)");
        expect_cell(3'd4, 3'd4, "AZ & : Shift Oric present");
        // 0x1E avec Shift -> '1' -> (0,5), sans Shift Oric
        mods = 8'h02;
        expect_cell(3'd0, 3'd5, "AZ Shift+& -> 1 (0,5)");
        expect_nocell(3'd4, 3'd4, "AZ 1 : pas de Shift Oric");
        k1 = 0; mods = 0;

        // 0x22 sans Shift -> '(' = Shift+9 -> (3,1) + Shift Oric
        k1 = 8'h22;
        expect_cell(3'd3, 3'd1, "AZ ( : 9 Oric (3,1)");
        expect_cell(3'd4, 3'd4, "AZ ( : Shift Oric present");
        // 0x22 avec Shift -> '5' -> (0,2)
        mods = 8'h02;
        expect_cell(3'd0, 3'd2, "AZ Shift+( -> 5 (0,2)");
        k1 = 0; mods = 0;

        // ---- Ponctuation bas de clavier ----
        // 0x10 (QWERTY M) sans Shift -> ',' -> (4,1)
        k1 = 8'h10; expect_cell(3'd4, 3'd1, "AZ , (4,1)");
        // 0x10 avec Shift -> '?' = Shift+/ -> (7,3) + Shift Oric
        mods = 8'h02;
        expect_cell(3'd7, 3'd3, "AZ ? : / Oric (7,3)");
        expect_cell(3'd4, 3'd4, "AZ ? : Shift Oric present");
        k1 = 0; mods = 0;

        // ---- Repli positionnel : Entrée non réaffectée par l'AZERTY ----
        k2 = 8'h28; expect_cell(3'd7, 3'd5, "AZ Entree -> RETURN (7,5)"); k2 = 0;

        // ---- Non-régression QWERTY (azerty=0) ----
        azerty = 0;
        k1 = 8'h14; expect_cell(3'd1, 3'd6, "QW 0x14 -> Q (1,6)"); k1 = 0;
        k1 = 8'h04; expect_cell(3'd6, 3'd5, "QW 0x04 -> A (6,5)"); k1 = 0;
        // Shift physique reporte tel quel en QWERTY -> (4,4)
        mods = 8'h02; expect_cell(3'd4, 3'd4, "QW LSHIFT -> (4,4)"); mods = 0;

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_azerty)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
