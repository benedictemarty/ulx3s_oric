// Testbench bout-en-bout CLOAD : boot ROM réel (DIV=25), frappe de
// CLOAD"" au clavier (key_injector), lecture d'un petit .tap valide via
// tape_injector — en mode normal (+turbo=0) ou turbo (+turbo=1, câblage
// identique au top : turbo = tape_active). Succès = l'écran passe par
// « Searching » puis « Loading » (la ROM a trouvé l'amorce et lu l'en-tête).
`timescale 1ns/1ps

module tb_cload;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;

    // ---- Mode turbo par plusarg ----
    integer turbo_mode = 0;
    initial if (!$value$plusargs("turbo=%d", turbo_mode)) turbo_mode = 0;

    // ---- Clavier : ASCII -> matrice ----
    reg  [7:0] key_data = 0;
    reg        key_valid = 0;
    wire       inj_active, inj_shift;
    wire [2:0] inj_col, inj_row;

    key_injector #(.PRESS_TICKS(500_000), .GAP_TICKS(250_000)) keys (
        .clk(clk), .rst(rst),
        .rx_data(key_data), .rx_valid(key_valid),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row),
        .inj_shift(inj_shift)
    );

    // ---- Cassette ----
    reg  [7:0] tap_data = 0;
    reg        tap_valid = 0;
    wire [7:0] tap_tx_data;
    wire       tap_tx_send;
    wire       tape_line, tape_active, tape_motor;

    wire turbo = (turbo_mode != 0) && tape_active;   // comme dans le top

    tape_injector tape (
        .clk(clk), .rst(rst),
        .rx_data(tap_data), .rx_valid(tap_valid),
        .tx_data(tap_tx_data), .tx_send(tap_tx_send), .tx_busy(1'b0),
        .turbo(turbo), .motor(tape_motor),
        .tape_line(tape_line), .tape_active(tape_active)
    );

    // ---- Oric ----
    oric_atmos #(.DIV(25), .ROM_FILE("roms/basic11b.hex"), .ROM_FILE_B("roms/basic10.hex")) dut (
        .clk(clk), .rst(rst), .rom_bank(1'b0), .turbo(turbo),
        .kbd_azerty(1'b0), .kbd_mods(8'd0), .kbd_k1(8'd0), .kbd_k2(8'd0), .kbd_k3(8'd0), .kbd_k4(8'd0),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row), .inj_shift(inj_shift),
        .exp_addr(), .exp_we(), .exp_do(), .exp_io_page(), .exp_tphase(),
        .ext_din(8'hFF), .ext_irq(1'b0), .ext_romdis(1'b0), .ext_map(1'b0),
        .ext_ioctl(1'b0),
        .prn_data(), .prn_strobe_n(), .prn_ack(1'b1),
        .tape_out(), .tape_motor(tape_motor), .tape_in(tape_line),
        .fb_we(), .fb_addr(), .fb_data(),
        .frame_tick(), .audio(), .cpu_irq_dbg()
    );

    // ---- Recherche de texte dans la RAM écran ----
    integer i, j;
    reg found;
    task scan_for(input [8*8-1:0] pat, input integer plen);
        begin
            found = 0;
            for (i = 16'hBB80; i <= 16'hBFDF - plen; i = i + 1) begin
                found = 1;
                for (j = 0; j < plen; j = j + 1)
                    if (dut.ram.mem[i+j] !== pat[(plen-1-j)*8 +: 8]) found = 0;
                if (found) i = 16'hBFDF;   // trouvé : sortir
            end
        end
    endtask

    task type_str(input [8*16-1:0] s, input integer n);
        begin
            for (j = 0; j < n; j = j + 1) begin
                @(negedge clk); key_data = s[(n-1-j)*8 +: 8]; key_valid = 1;
                @(negedge clk); key_valid = 0;
                repeat (10) @(negedge clk);
            end
        end
    endtask

    // ---- Petit .tap valide : 1 bloc, 4 octets de données en $0501 ----
    localparam NT = 18;
    reg [7:0] tap [0:NT-1];
    initial begin
        tap[0]=8'h16; tap[1]=8'h16; tap[2]=8'h16; tap[3]=8'h24;
        tap[4]=8'h00; tap[5]=8'h00; tap[6]=8'h80; tap[7]=8'h00;
        tap[8]=8'h05; tap[9]=8'h04;                 // fin   = $0504
        tap[10]=8'h05; tap[11]=8'h01;               // début = $0501
        tap[12]=8'h00;                              // 9e octet en-tête
        tap[13]=8'h00;                              // nom vide
        tap[14]=8'h41; tap[15]=8'h42; tap[16]=8'h43; tap[17]=8'h44;
    end

    integer credit_cnt = 0;
    always @(posedge clk)
        if (!rst && tap_tx_send && tap_tx_data == 8'h5A) credit_cnt = credit_cnt + 1;

    // ---- Instrumentation : périodes de tape_line en cycles CPU (cen1) ----
    // En turbo comme en normal, les fronts montants doivent être espacés de
    // ~208 cycles CPU (bit '1') ou ~312 (moitiés 208+416 d'un bit '0')… la
    // valeur absolue importe peu : elle doit être IDENTIQUE dans les 2 modes.
    integer cen_cnt = 0, last_edge_cen = 0, edges_shown = 0;
    reg tl_q = 1;
    always @(posedge clk) begin
        if (dut.cen1) cen_cnt = cen_cnt + 1;
        tl_q <= tape_line;
        if (tape_line && !tl_q && tape_active) begin
            if (edges_shown < 40)
                $display("edge %0d : delta=%0d cycles CPU (ifr_cb1=%b)",
                         edges_shown, cen_cnt - last_edge_cen, dut.via.ifr[4]);
            last_edge_cen = cen_cnt;
            edges_shown = edges_shown + 1;
        end
    end

    // ---- Trace VIA (+viatrace=1) : tous les accès VIA + poses de flag CB1
    // pendant la cassette, en cycles CPU. À diff-er entre turbo=0 et turbo=1.
    integer viatrace = 0;
    initial if (!$value$plusargs("viatrace=%d", viatrace)) viatrace = 0;
    integer via_ev = 0;
    reg tr_on = 0;
    always @(posedge clk) if (viatrace != 0) begin
        if (tape_active && tape_line === 1'b0 && !tr_on) begin
            tr_on = 1; $display("T START @%0d", cen_cnt);
        end
        if (tr_on && dut.cen1 && via_ev < 5000) begin
            if (dut.via.cb1_edge) begin
                $display("T CB1SET @%0d", cen_cnt); via_ev = via_ev + 1;
            end
            // Filtre : on saute les polls IFR ($030D en lecture, spam ~1/10
            // cycles) pour couvrir ~100 octets décodés au lieu de ~13.
            if (dut.sel_via &&
                !(dut.bus_addr_q[3:0] == 4'hd && !dut.bus_we_q)) begin
                $display("T VIA%0s %h w=%h r=%h ifr=%h t2=%h @%0d",
                         dut.bus_we_q ? "W" : "R", dut.bus_addr_q[3:0],
                         dut.bus_do_q, dut.via.dout, dut.via.ifr,
                         dut.via.t2c, cen_cnt);
                via_ev = via_ev + 1;
            end
        end
    end

    // ---- Trace RAM basse (+ramtrace=1) : écritures pages 0-2 pendant la
    // cassette (variables de la routine de sync ROM). Diff normal vs turbo :
    // la première écriture divergente identifie la variable qui déraille.
    integer ramtrace = 0;
    initial if (!$value$plusargs("ramtrace=%d", ramtrace)) ramtrace = 0;
    integer ram_ev = 0;
    reg rtr_on = 0;
    always @(posedge clk) if (ramtrace != 0) begin
        // Déclenchement au 1er octet du FICHIER (l'amorce injectée est passée) :
        // c'est là que la reconnaissance 0x16/0x24 de la ROM peut diverger.
        if (tape_active && tape.consumed != 0 && !rtr_on) begin
            rtr_on = 1; $display("R START @%0d", cen_cnt);
        end
        if (rtr_on && dut.cen1 && ram_ev < 5000 &&
            dut.bus_we_q && dut.bus_addr_q < 16'h0600) begin  // inclut $0501-$0504 (donnees chargees)
            $display("R W %h=%h @%0d", dut.bus_addr_q, dut.bus_do_q, cen_cnt);
            ram_ev = ram_ev + 1;
        end
    end

    task tap_byte(input [7:0] b);
        begin
            @(negedge clk); tap_data = b; tap_valid = 1;
            @(negedge clk); tap_valid = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    // ---- Dump écran périodique (+screendump=1) : que voit-on VRAIMENT ? ----
    integer screendump = 0;
    initial if (!$value$plusargs("screendump=%d", screendump)) screendump = 0;
    integer sd_r, sd_c, sd_n = 0;
    reg [7:0] sd_ch;
    reg [40*8-1:0] sd_line;
    task dump_screen_now;
        begin
            $display("=== ECRAN (dump %0d) @%0d ===", sd_n, cen_cnt);
            for (sd_r = 0; sd_r < 28; sd_r = sd_r + 1) begin
                for (sd_c = 0; sd_c < 40; sd_c = sd_c + 1) begin
                    sd_ch = dut.ram.mem[16'hBB80 + sd_r*40 + sd_c];
                    if (sd_ch < 8'h20 || sd_ch > 8'h7E) sd_ch = " ";
                    sd_line[(39-sd_c)*8 +: 8] = sd_ch;
                end
                if (sd_line != {40{8'h20}}) $display("|%0d|%s|", sd_r, sd_line);
            end
            sd_n = sd_n + 1;
        end
    endtask
    always @(posedge clk)
        if (screendump != 0 && rtr_on && sd_n < 12 && (cen_cnt % 300_000 == 0) && dut.cen1)
            dump_screen_now;

    integer cpu_cycles, errors = 0;
    reg searching_seen = 0, loading_seen = 0;

    initial begin
        repeat (10) @(negedge clk); rst = 0;

        // 1) Boot -> bannière (scan périodique, max ~5 s Oric)
        found = 0;
        for (cpu_cycles = 0; cpu_cycles < 5_000_000 && !found; cpu_cycles = cpu_cycles + 1) begin
            repeat (25) @(negedge clk);
            if (cpu_cycles % 250_000 == 0) scan_for("ORIC", 4);
        end
        if (!found) begin $display("FAIL: pas de banniere au boot"); $finish; end
        $display("boot OK (%0d cycles CPU)", cpu_cycles);
        repeat (2_000_000) @(negedge clk);          // laisse finir l'init/Ready

        // 2) Taper CLOAD"" + Entrée
        type_str({"CLOAD", 8'h22, 8'h22, 8'h0D}, 8);

        // 3) Attendre « Searching » (moteur démarré)
        for (cpu_cycles = 0; cpu_cycles < 8_000_000 && !searching_seen; cpu_cycles = cpu_cycles + 1) begin
            repeat (25) @(negedge clk);
            if (cpu_cycles % 100_000 == 0) begin
                scan_for("earching", 8);
                if (found) searching_seen = 1;
            end
        end
        if (!searching_seen) begin $display("FAIL: Searching jamais affiche"); $finish; end
        $display("Searching vu, motor=%b", tape_motor);

        // 4) Lancer la cassette (protocole 0x01 len puis octets par crédit)
        tap_byte(8'h01); tap_byte(NT[7:0]); tap_byte(8'h00);
        for (j = 0; j < NT; j = j + 1) begin
            wait (credit_cnt > j);
            tap_byte(tap[j]);
        end

        // 5) Laisser le chargement aller AU BOUT (bande ~0,6 s + marge), puis
        // vérifier le RÉSULTAT : données en $0501-$0504 et écran final.
        repeat (60_000_000) @(negedge clk);
        scan_for("oading", 6);  loading_seen = found;
        scan_for("rrors", 5);
        $display("VERDICT turbo=%0d : Loading=%0d Errors=%0d  $0501..0504 = %h %h %h %h",
                 turbo_mode, loading_seen, found,
                 dut.ram.mem[16'h0501], dut.ram.mem[16'h0502],
                 dut.ram.mem[16'h0503], dut.ram.mem[16'h0504]);
        if (dut.ram.mem[16'h0501] === 8'h41 && dut.ram.mem[16'h0502] === 8'h42 &&
            dut.ram.mem[16'h0503] === 8'h43 && dut.ram.mem[16'h0504] === 8'h44 && !found)
            $display("ALL TESTS PASSED (tb_cload, turbo=%0d)", turbo_mode);
        else
            $display("FAIL: chargement incorrect (turbo=%0d)", turbo_mode);
        $finish;
    end

    initial begin
        #6_000_000_000;
        $display("FAIL: timeout global"); $finish;
    end

endmodule
