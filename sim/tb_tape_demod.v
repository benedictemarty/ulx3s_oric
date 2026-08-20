// Testbench démodulateur cassette (CSAVE) : boucle tape_injector -> tape_demod.
// L'injecteur (modulation validée sur carte contre la vraie ROM CLOAD) génère
// la forme d'onde ; le démodulateur la reconstruit en octets. On vérifie que
// les octets décodés == amorce (0x16) + données envoyées, sur un flux simple
// puis sur un flux multi-blocs (avec ré-insertion d'amorce inter-blocs).
`timescale 1ns/1ps

module tb_tape_demod;

    // Durées réduites pour la simulation (comme tb_tape).
    localparam CH1 = 4, CHL = 8, LEAD = 4, INTER = 6;
    localparam THRESH = (2*CH1 + (CH1+CHL)) / 2;   // '1'=8 / '0'=12 -> seuil 10
    localparam GAP    = 400;                        // silence de fin de capture

    reg clk = 0, rst = 1;
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0;
    wire [7:0] tx_data;
    wire       tx_send;
    reg        motor = 1;
    wire       tape_line, tape_active;

    tape_injector #(.CYC_HALF_ONE(CH1), .CYC_HALF_LONG(CHL), .LEADER_SYNCS(LEAD),
                    .INTER_SYNCS(INTER)) inj (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_send(tx_send), .tx_busy(1'b0),
        .turbo(1'b0), .motor(motor), .tape_line(tape_line), .tape_active(tape_active)
    );

    wire [7:0] dbyte;
    wire       dvalid, capturing;
    tape_demod #(.CYC_THRESH(THRESH), .GAP_CYCLES(GAP)) dut (
        .clk(clk), .rst(rst),
        .tape_out(tape_line),
        .byte_out(dbyte), .byte_valid(dvalid), .capturing(capturing)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    // ---- Capture des octets décodés ----
    integer ndec = 0;
    reg [7:0] dec [0:255];
    always @(posedge clk)
        if (!rst && dvalid) begin dec[ndec] = dbyte; ndec = ndec + 1; end

    // ---- Comptage des crédits (pour cadencer l'envoi PC) ----
    integer credit_cnt = 0;
    always @(posedge clk)
        if (!rst && tx_send && tx_data == 8'h5A) credit_cnt <= credit_cnt + 1;

    task send_byte(input [7:0] b);
        begin
            @(negedge clk); rx_data = b; rx_valid = 1;
            @(negedge clk); rx_valid = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    // ---- Données simples ----
    localparam NDATA = 4;
    reg [7:0] data_arr [0:NDATA-1];

    // ---- Flux multi-blocs (2 blocs .tap concaténés, cf. tb_tape) ----
    localparam NB2 = 32;
    reg [7:0] mp [0:NB2-1];
    task build_block(input integer base, input [7:0] d0, input [7:0] d1);
        begin
            mp[base+0]=8'h16; mp[base+1]=8'h16; mp[base+2]=8'h16; mp[base+3]=8'h24;
            mp[base+4]=8'h00; mp[base+5]=8'h00; mp[base+6]=8'h80; mp[base+7]=8'h00;
            mp[base+8]=8'h60; mp[base+9]=8'h01;   // fin   = 0x6001
            mp[base+10]=8'h60; mp[base+11]=8'h00; // début = 0x6000
            mp[base+12]=8'h00;                    // 9e octet d'en-tête
            mp[base+13]=8'h00;                    // nom vide
            mp[base+14]=d0; mp[base+15]=d1;       // 2 octets de données
        end
    endtask

    integer i, c0;
    initial begin
        data_arr[0] = 8'h55; data_arr[1] = 8'hC3;
        data_arr[2] = 8'h2A; data_arr[3] = 8'hFF;

        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // ---- Scénario 1 : flux simple ----
        send_byte(8'h01); send_byte(NDATA[7:0]); send_byte(8'h00);
        for (i = 0; i < NDATA; i = i + 1) begin
            wait (credit_cnt > i);
            send_byte(data_arr[i]);
        end
        wait (tape_active == 1'b0);
        // laisser le démod conclure sur le silence de fin
        repeat (GAP + 200) @(negedge clk);

        check(ndec == LEAD + NDATA, "simple: nb octets = amorce + donnees");
        for (i = 0; i < LEAD; i = i + 1)
            check(dec[i] == 8'h16, "simple: amorce = 0x16");
        for (i = 0; i < NDATA; i = i + 1)
            check(dec[LEAD + i] == data_arr[i], "simple: donnee decodee == envoyee");
        check(capturing == 1'b0, "simple: capturing retombe apres silence");

        // ---- Scénario 2 : multi-blocs ----
        build_block(0,  8'hAA, 8'hBB);
        build_block(16, 8'hCC, 8'hDD);
        ndec = 0; c0 = credit_cnt;

        send_byte(8'h01); send_byte(NB2[7:0]); send_byte(8'h00);
        for (i = 0; i < NB2; i = i + 1) begin
            wait (credit_cnt > c0 + i);
            send_byte(mp[i]);
        end
        wait (tape_active == 1'b0);
        repeat (GAP + 200) @(negedge clk);

        check(ndec == LEAD + 16 + INTER + 16,
              "multi: nb octets = amorce + bloc1 + INTER + bloc2");
        for (i = 0; i < 16; i = i + 1)
            check(dec[LEAD + i] == mp[i], "multi: bloc1 decode == envoye");
        for (i = 0; i < INTER; i = i + 1)
            check(dec[LEAD + 16 + i] == 8'h16, "multi: amorce inter-blocs = 0x16");
        for (i = 0; i < 16; i = i + 1)
            check(dec[LEAD + 16 + INTER + i] == mp[16 + i], "multi: bloc2 decode == envoye");

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape_demod)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
