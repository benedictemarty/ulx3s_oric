// Testbench disposition AZERTY : (scancode HID, Shift) -> ASCII FR -> matrice.
// Vérifie les permutations de lettres, les chiffres en Shift, les symboles
// nécessitant un Shift Oric (séquencé : avance/maintien/traîne), la
// non-propagation du Shift physique sur une lettre, le repli positionnel
// (Entrée) et la non-régression QWERTY.
`timescale 1ns/1ps

module tb_azerty;

    reg clk = 0;
    reg [7:0] mods = 0, k1 = 0, k2 = 0, k3 = 0, k4 = 0;
    reg [2:0] col_sel = 0;
    reg [7:0] ay_ioa = 8'hFF;
    reg       azerty = 1;
    wire sense;

    // Durées de séquencement du Shift réduites pour la simulation.
    localparam LEAD = 20, HOLD = 4, TAIL = 8;

    oric_keyboard #(.LEAD_TICKS(LEAD), .HOLD_MIN_TICKS(HOLD), .TAIL_TICKS(TAIL)) dut (
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
    task steps(input integer n); integer j; begin
        for (j = 0; j < n; j = j + 1) @(negedge clk);
    end endtask

    // La cellule (col,row) est-elle vue pressée (via sense) ?
    task read_cell(input [2:0] col, input [2:0] row);
        begin col_sel = col; ay_ioa = ~(8'h01 << row); settle; end
    endtask
    task expect_cell(input [2:0] col, input [2:0] row, input [255:0] msg);
        begin read_cell(col, row); check(sense == 1'b1, msg); end
    endtask
    task expect_nocell(input [2:0] col, input [2:0] row, input [255:0] msg);
        begin read_cell(col, row); check(sense == 1'b0, msg); end
    endtask

    initial begin
        settle;

        // ---- Lettres permutées vs QWERTY (posées immédiatement) ----
        k1 = 8'h14; expect_cell(3'd6, 3'd5, "AZ 0x14 -> A (6,5)"); k1 = 0;
        k1 = 8'h04; expect_cell(3'd1, 3'd6, "AZ 0x04 -> Q (1,6)"); k1 = 0;
        k1 = 8'h1A; expect_cell(3'd2, 3'd5, "AZ 0x1A -> Z (2,5)"); k1 = 0;
        k1 = 8'h1D; expect_cell(3'd6, 3'd7, "AZ 0x1D -> W (6,7)"); k1 = 0;
        k1 = 8'h33; expect_cell(3'd2, 3'd0, "AZ 0x33 -> M (2,0)"); k1 = 0;

        // ---- Une lettre ne doit PAS déclencher le Shift Oric, même Shift tenu ----
        k1 = 8'h14; mods = 8'h02;
        expect_cell(3'd6, 3'd5, "AZ A+Shift : lettre presente");
        expect_nocell(3'd4, 3'd4, "AZ A+Shift : pas de Shift Oric parasite");
        k1 = 0; mods = 0; steps(TAIL + 3);

        // ---- Rangée du haut : CHIFFRE direct, immédiat, sans Shift ----
        // 0x1E sans Shift -> '1' -> (0,5)
        k1 = 8'h1E; expect_cell(3'd0, 3'd5, "AZ 0x1E -> 1 (0,5) immediat");
        expect_nocell(3'd4, 3'd4, "AZ 1 : pas de Shift"); k1 = 0;
        // 0x1F sans Shift -> '2' -> (2,6)
        k1 = 8'h1F; expect_cell(3'd2, 3'd6, "AZ 0x1F -> 2 (2,6) immediat"); k1 = 0;

        // ---- Anti-repli : Shift+2 (glyphe é hors ASCII) ne doit RIEN donner,
        //      surtout pas le '2' QWERTY (bug corrige). ----
        k1 = 8'h1F; mods = 8'h02; steps(LEAD + 2);
        expect_nocell(3'd2, 3'd6, "AZ Shift+2 : pas de 2 QWERTY parasite");
        expect_nocell(3'd0, 3'd5, "AZ Shift+2 : pas de 1 non plus");
        k1 = 0; mods = 0; steps(TAIL + 3);

        // ---- Symbole en Shift synthétisé : '&' = Shift+1 -> Shift+7 Oric ----
        // Le Shift doit PRÉCÉDER : d'abord (4,4) seul, la touche (0,0) attend.
        k1 = 8'h1E; mods = 8'h02; @(negedge clk); @(negedge clk);   // entree en LEAD
        expect_cell(3'd4, 3'd4, "AZ & : Shift precede (4,4)");
        expect_nocell(3'd0, 3'd0, "AZ & : touche 7 pas encore posee (LEAD)");
        // Après l'avance, la touche apparaît AVEC le Shift toujours présent.
        steps(LEAD + 2);
        expect_cell(3'd0, 3'd0, "AZ & : 7 Oric (0,0) apres LEAD");
        expect_cell(3'd4, 3'd4, "AZ & : Shift toujours present (HOLD)");
        // Relâché : la touche tombe, le Shift PROLONGE (traîne) puis retombe.
        k1 = 0; mods = 0; steps(HOLD + 1);
        expect_cell(3'd4, 3'd4, "AZ & : Shift prolonge au relache (TAIL)");
        expect_nocell(3'd0, 3'd0, "AZ & : touche relachee");
        steps(TAIL + 3);
        expect_nocell(3'd4, 3'd4, "AZ & : Shift retombe apres TAIL");

        // ---- '(' = Shift+5 -> Shift+9 Oric : présence en régime établi ----
        k1 = 8'h22; mods = 8'h02; steps(LEAD + 2);
        expect_cell(3'd3, 3'd1, "AZ ( : 9 Oric (3,1)");
        expect_cell(3'd4, 3'd4, "AZ ( : Shift present");
        k1 = 0; mods = 0; steps(TAIL + 3);

        // ---- '*' = Shift+8 Oric (7,0), touche *µ (0x31) et variante ISO (0x32) ----
        k1 = 8'h31; steps(LEAD + 2);
        expect_cell(3'd7, 3'd0, "AZ * (0x31) : 8 Oric (7,0)");
        expect_cell(3'd4, 3'd4, "AZ * (0x31) : Shift present");
        k1 = 0; steps(TAIL + 3);
        k1 = 8'h32; steps(LEAD + 2);
        expect_cell(3'd7, 3'd0, "AZ * (0x32) : 8 Oric (7,0)");
        k1 = 0; steps(TAIL + 3);

        // ---- '?' = Shift+/ (0x10 avec Shift physique) ----
        k1 = 8'h10; mods = 8'h02; steps(LEAD + 2);
        expect_cell(3'd7, 3'd3, "AZ ? : / Oric (7,3)");
        expect_cell(3'd4, 3'd4, "AZ ? : Shift present");
        k1 = 0; mods = 0; steps(TAIL + 3);

        // ---- ',' = 0x10 sans Shift : glyphe direct, immédiat, sans Shift ----
        k1 = 8'h10; expect_cell(3'd4, 3'd1, "AZ , (4,1) immediat");
        expect_nocell(3'd4, 3'd4, "AZ , : pas de Shift"); k1 = 0;

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
