// Testbench de l'encodeur TMDS HDMI (rtl/hdmi_tmds_channel.v).
//
// Phase 1 — NON-RÉGRESSION : l'encodeur HDMI piloté en mode DVI (control /
//   video) doit produire exactement les mêmes symboles que l'ancien
//   tmds_encoder.v pour une séquence identique. Garantit que l'image reste
//   intacte.
// Phase 2 — CONSTANTES HDMI : vérifie les codes TERC4, les guard bands vidéo
//   et data-island, et les codes de contrôle, contre une copie littérale
//   indépendante (attrape toute faute de frappe dans le module).
`timescale 1ns/1ps

module tb_hdmi_tmds;

    reg clk = 0;
    always #20 clk = ~clk;    // 25 MHz

    // Stimulus commun
    reg [7:0] vdata = 0;
    reg [3:0] aux   = 0;
    reg [1:0] cd    = 0;
    reg [2:0] md    = 0;
    reg       de    = 0;

    // Ancien encodeur DVI (référence de non-régression)
    wire [9:0] t_old;
    tmds_encoder enc_old (.clk(clk), .data(vdata), .ctrl(cd), .de(de), .tmds(t_old));

    // Nouvel encodeur HDMI, un par canal
    wire [9:0] t0, t1, t2;
    hdmi_tmds_channel #(.CN(0)) enc0 (.clk(clk), .mode(md), .video_data(vdata),
                                      .aux_data(aux), .ctrl_data(cd), .tmds(t0));
    hdmi_tmds_channel #(.CN(1)) enc1 (.clk(clk), .mode(md), .video_data(vdata),
                                      .aux_data(aux), .ctrl_data(cd), .tmds(t1));
    hdmi_tmds_channel #(.CN(2)) enc2 (.clk(clk), .mode(md), .video_data(vdata),
                                      .aux_data(aux), .ctrl_data(cd), .tmds(t2));

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    // Table TERC4 de référence (copie littérale indépendante du module)
    function [9:0] terc4_exp;
        input [3:0] d;
        case (d)
            4'h0: terc4_exp = 10'b1010011100;
            4'h1: terc4_exp = 10'b1001100011;
            4'h2: terc4_exp = 10'b1011100100;
            4'h3: terc4_exp = 10'b1011100010;
            4'h4: terc4_exp = 10'b0101110001;
            4'h5: terc4_exp = 10'b0100011110;
            4'h6: terc4_exp = 10'b0110001110;
            4'h7: terc4_exp = 10'b0100111100;
            4'h8: terc4_exp = 10'b1011001100;
            4'h9: terc4_exp = 10'b0100111001;
            4'hA: terc4_exp = 10'b0110011100;
            4'hB: terc4_exp = 10'b1011000110;
            4'hC: terc4_exp = 10'b1010001110;
            4'hD: terc4_exp = 10'b1001110001;
            4'hE: terc4_exp = 10'b0101100011;
            4'hF: terc4_exp = 10'b1011000011;
        endcase
    endfunction

    integer i;
    reg [7:0] lfsr = 8'hA5;

    initial begin
        // Amorçage : blanking pour aligner la disparité à 0 dans les deux encodeurs
        de = 0; md = 0; cd = 0; vdata = 0; aux = 0;
        repeat (8) @(negedge clk);

        // ---- Phase 1 : non-régression DVI (control + video) ----
        for (i = 0; i < 512; i = i + 1) begin
            de = ((i % 64) < 40);           // 40 pixels actifs, 24 de blanking
            md = de ? 3'd1 : 3'd0;          // video / control
            cd = de ? 2'd0 : i[1:0];        // ctrl varié pendant le blanking
            lfsr = {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
            vdata = lfsr;
            @(negedge clk);                 // le posedge intermédiaire a échantillonné
            check(t_old === t0, "non-regression DVI (t_old == t0)");
        end

        // ---- Phase 2 : constantes HDMI ----
        // TERC4 (mode 3) — identique sur tous les canaux
        de = 0; md = 3'd3;
        for (i = 0; i < 16; i = i + 1) begin
            aux = i[3:0];
            @(negedge clk);
            check(t0 === terc4_exp(i[3:0]), "TERC4 canal 0");
            check(t1 === terc4_exp(i[3:0]), "TERC4 canal 1");
            check(t2 === terc4_exp(i[3:0]), "TERC4 canal 2");
        end

        // Video guard band (mode 2)
        md = 3'd2;
        @(negedge clk);
        check(t0 === 10'b1011001100, "video guard band canal 0");
        check(t1 === 10'b0100110011, "video guard band canal 1");
        check(t2 === 10'b1011001100, "video guard band canal 2");

        // Data island guard band (mode 4)
        md = 3'd4;
        cd = 2'b00; @(negedge clk);
        check(t0 === 10'b1010001110, "data guard ch0 (cd=00)");
        check(t1 === 10'b0100110011, "data guard ch1");
        check(t2 === 10'b0100110011, "data guard ch2");
        cd = 2'b01; @(negedge clk); check(t0 === 10'b1001110001, "data guard ch0 (cd=01)");
        cd = 2'b10; @(negedge clk); check(t0 === 10'b0101100011, "data guard ch0 (cd=10)");
        cd = 2'b11; @(negedge clk); check(t0 === 10'b1011000011, "data guard ch0 (cd=11)");

        // Control period (mode 0)
        md = 3'd0;
        cd = 2'b00; @(negedge clk); check(t0 === 10'b1101010100, "control cd=00");
        cd = 2'b01; @(negedge clk); check(t0 === 10'b0010101011, "control cd=01");
        cd = 2'b10; @(negedge clk); check(t0 === 10'b0101010100, "control cd=10");
        cd = 2'b11; @(negedge clk); check(t0 === 10'b1010101011, "control cd=11");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_hdmi_tmds)");
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
