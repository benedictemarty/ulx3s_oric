// Testbench injecteur cassette : pilote le protocole crédits, joue le rôle du
// PC (un octet .tap par crédit), puis REDÉCODE la forme d'onde produite sur
// tape_line (périodes front-montant à front-montant -> bits -> trames 14 bits)
// et vérifie amorce 0x16, framing (start/parité impaire/stop) et données.
`timescale 1ns/1ps

module tb_tape;

    // Durées réduites pour la simulation.
    localparam CH1 = 4, CHL = 8, LEAD = 4, INTER = 6;
    localparam CH1T = 2, CHLT = 4;                 // demi-périodes turbo (÷2)
    localparam THRESH = (2*CH1 + (CH1+CHL)) / 2;   // seuil '1'(=8) / '0'(=12) = 10
    localparam THRESHT = (2*CH1T + (CH1T+CHLT)) / 2;

    reg clk = 0, rst = 1;
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0;
    wire [7:0] tx_data;
    wire       tx_send;
    reg        motor = 1;
    reg        turbo = 0;
    wire       tape_line, tape_active;

    tape_injector #(.CYC_HALF_ONE(CH1), .CYC_HALF_LONG(CHL), .LEADER_SYNCS(LEAD),
                    .CYC_HALF_ONE_T(CH1T), .CYC_HALF_LONG_T(CHLT),
                    .INTER_SYNCS(INTER)) dut (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_send(tx_send), .tx_busy(1'b0),
        .turbo(turbo), .motor(motor), .tape_line(tape_line), .tape_active(tape_active)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    // ---- Données à envoyer ----
    localparam NDATA = 3;
    reg [7:0] data_arr [0:NDATA-1];

    // ---- Flux multi-parties : 2 blocs .tap complets concaténés ----
    // Bloc = 3×0x16, 0x24, en-tête 9 octets (fin=0x6001, début=0x6000 -> 2
    // octets de données), nom vide (0x00), 2 octets de données.
    localparam NB2 = 32;                     // 2 × 16 octets
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

    // ---- Comptage des crédits (concurrent) ----
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

    // ------------------------------------------------------------------
    // Décodeur de forme d'onde : période entre fronts montants -> bit
    // ------------------------------------------------------------------
    reg        tl_prev = 1;
    integer    thresh = THRESH, gapthresh = 1_000_000;
    reg [31:0] cyc = 0, last_rise = 0;
    reg        have_last = 0;
    reg [13:0] dframe = 0;
    integer    dbit = 0;
    integer    ndec = 0;
    reg [7:0]  dec [0:63];
    integer    delta, bitv;

    task validate_frame(input [13:0] f, input integer full);
        begin
            check(f[0] == 1'b0, "trame : start=0");
            check(f[9] == ~(^f[8:1]), "trame : parite impaire");
            if (full) check(f[13:10] == 4'b1111, "trame : 4 stop=1");
            else      check(f[12:10] == 3'b111,  "trame : 3 stop=1 (derniere)");
            dec[ndec] = f[8:1];
            ndec = ndec + 1;
        end
    endtask

    always @(posedge clk) begin
        cyc <= cyc + 1;
        tl_prev <= tape_line;
        if (tape_line && !tl_prev) begin           // front montant
            if (have_last) begin
                delta = cyc - last_rise;
                bitv  = (delta <= thresh) ? 1 : 0;
                // Comme la chasse au start de la ROM : les '1' entre trames
                // (stops turbo supplémentaires) sont ignorés en tête de trame.
                if (dbit == 0 && bitv == 1) begin
                    // stop inter-trames : ignorer
                end else begin
                    dframe[dbit] = bitv;
                    dbit = dbit + 1;
                    if (dbit == 14) begin
                        validate_frame(dframe, 1);
                        dbit = 0;
                    end
                end
            end
            last_rise = cyc;
            have_last = 1;
        end
    end

    integer i, c0;
    initial begin
        data_arr[0] = 8'h55;
        data_arr[1] = 8'hC3;
        data_arr[2] = 8'h2A;

        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // En-tête : 0x01, len_lo, len_hi
        send_byte(8'h01);
        send_byte(NDATA[7:0]);
        send_byte(8'h00);

        // Un octet de donnée par crédit reçu
        for (i = 0; i < NDATA; i = i + 1) begin
            wait (credit_cnt > i);      // i crédits déjà consommés -> le (i+1)e dispo
            send_byte(data_arr[i]);
        end

        // Laisse jouer toute la bande (amorce + données), avec marge.
        wait (tape_active == 1'b0);
        repeat (200) @(negedge clk);

        // Flush d'une trame partielle (dernière : 13 bits, bit13 sans front suivant)
        if (dbit >= 13) validate_frame(dframe, 0);

        // ---- Vérifications ----
        check(credit_cnt == NDATA, "credits == nombre d'octets");
        check(ndec == LEAD + NDATA, "nb trames = amorce + donnees");
        for (i = 0; i < LEAD; i = i + 1)
            check(dec[i] == 8'h16, "amorce = 0x16");
        for (i = 0; i < NDATA; i = i + 1)
            check(dec[LEAD + i] == data_arr[i], "donnee decodee == envoyee");

        // ------------------------------------------------------------------
        // Scénario 2 : fichier MULTI-PARTIES (2 blocs) -> l'amorce doit être
        // ré-insérée entre les blocs (INTER trames 0x16), jamais dans les
        // données, et pas après le dernier octet du fichier.
        // ------------------------------------------------------------------
        build_block(0,  8'hAA, 8'hBB);
        build_block(16, 8'hCC, 8'hDD);
        ndec = 0; dbit = 0; have_last = 0;
        c0 = credit_cnt;

        send_byte(8'h01);
        send_byte(NB2[7:0]);
        send_byte(8'h00);
        for (i = 0; i < NB2; i = i + 1) begin
            wait (credit_cnt > c0 + i);
            send_byte(mp[i]);
        end
        wait (tape_active == 1'b0);
        repeat (200) @(negedge clk);
        if (dbit >= 13) validate_frame(dframe, 0);

        check(credit_cnt - c0 == NB2, "multi: credits == 32");
        check(ndec == LEAD + 16 + INTER + 16,
              "multi: nb trames = amorce + bloc1 + INTER + bloc2");
        for (i = 0; i < LEAD; i = i + 1)
            check(dec[i] == 8'h16, "multi: amorce initiale = 0x16");
        for (i = 0; i < 16; i = i + 1)
            check(dec[LEAD + i] == mp[i], "multi: bloc1 intact");
        for (i = 0; i < INTER; i = i + 1)
            check(dec[LEAD + 16 + i] == 8'h16, "multi: amorce inter-blocs = 0x16");
        for (i = 0; i < 16; i = i + 1)
            check(dec[LEAD + 16 + INTER + i] == mp[16 + i], "multi: bloc2 intact");

        // ------------------------------------------------------------------
        // Scénario 3 : mode TURBO — mêmes données que le scénario 1, demi-
        // périodes réduites (CH1T/CHLT), le décodeur suit avec son seuil turbo.
        // ------------------------------------------------------------------
        turbo = 1; thresh = THRESHT; gapthresh = 2*(CH1T+CHLT);
        ndec = 0; dbit = 0; have_last = 0;
        c0 = credit_cnt;

        send_byte(8'h01);
        send_byte(NDATA[7:0]);
        send_byte(8'h00);
        for (i = 0; i < NDATA; i = i + 1) begin
            wait (credit_cnt > c0 + i);
            send_byte(data_arr[i]);
        end
        wait (tape_active == 1'b0);
        repeat (200) @(negedge clk);
        if (dbit >= 13) validate_frame(dframe, 0);

        check(ndec == LEAD + NDATA, "turbo: nb trames = amorce + donnees");
        for (i = 0; i < LEAD; i = i + 1)
            check(dec[i] == 8'h16, "turbo: amorce = 0x16");
        for (i = 0; i < NDATA; i = i + 1)
            check(dec[LEAD + i] == data_arr[i], "turbo: donnee decodee == envoyee");

        // ------------------------------------------------------------------
        // Scénario 4 : jeu autorun qui COUPE LE MOTEUR dès son dernier octet
        // lu — l'injecteur doit quand même finir (tape_active retombe) alors
        // qu'il ne reste que des stop bits gelés.
        // ------------------------------------------------------------------
        ndec = 0; dbit = 0; have_last = 0;
        c0 = credit_cnt;
        send_byte(8'h01); send_byte(8'd1); send_byte(8'h00);   // 1 octet
        wait (credit_cnt > c0);
        send_byte(8'hA5);
        // attendre que la trame de données atteigne ses stop bits, puis
        // couper le moteur (comme le ferait le loader du jeu)
        wait (dut.consumed == 17'd1 && dut.wf != 0 && dut.bitpos >= 10);
        motor = 0;
        for (i = 0; i < 200 && tape_active; i = i + 1) @(negedge clk);
        check(tape_active == 1'b0, "autorun: tape_active retombe moteur coupe");
        motor = 1;

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
