// Testbench injecteur cassette : pilote le protocole crédits, joue le rôle du
// PC (un octet .tap par crédit), puis REDÉCODE la forme d'onde produite sur
// tape_line (périodes front-montant à front-montant -> bits -> trames 14 bits)
// et vérifie amorce 0x16, framing (start/parité impaire/stop) et données.
`timescale 1ns/1ps

module tb_tape;

    // Durées réduites pour la simulation.
    localparam CH1 = 4, CHL = 8, LEAD = 4;
    localparam THRESH = (2*CH1 + (CH1+CHL)) / 2;   // seuil '1'(=8) / '0'(=12) = 10

    reg clk = 0, rst = 1;
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0;
    wire [7:0] tx_data;
    wire       tx_send;
    reg        motor = 1;
    wire       tape_line, tape_active;

    tape_injector #(.CYC_HALF_ONE(CH1), .CYC_HALF_LONG(CHL), .LEADER_SYNCS(LEAD)) dut (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_send(tx_send), .tx_busy(1'b0),
        .motor(motor), .tape_line(tape_line), .tape_active(tape_active)
    );

    always #10 clk = ~clk;

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    // ---- Données à envoyer ----
    localparam NDATA = 3;
    reg [7:0] data_arr [0:NDATA-1];

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
                bitv  = (delta <= THRESH) ? 1 : 0;
                dframe[dbit] = bitv;
                dbit = dbit + 1;
                if (dbit == 14) begin
                    validate_frame(dframe, 1);
                    dbit = 0;
                end
            end
            last_rise = cyc;
            have_last = 1;
        end
    end

    integer i;
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

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
