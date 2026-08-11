// Testbench d'intégration : boot complet de la ROM BASIC 1.1b.
// Le 6502 exécute la ROM ; le test réussit quand la bannière « ORIC » est
// écrite dans la RAM écran ($BB80-$BFDF) et que le charset a été copié en
// $B400 par la routine d'init. DIV=13 pour accélérer la simulation (le
// rapport CPU/VIA/ULA reste identique au réel).
`timescale 1ns/1ps

module tb_boot;

    localparam DIV = 13;

    reg clk = 0, rst = 1;

    wire fb_we;
    wire [15:0] fb_addr;
    wire [3:0] fb_data;
    wire frame_tick;
    wire [9:0] audio;
    wire irq_dbg;

    oric_atmos #(.DIV(DIV), .ROM_FILE("roms/basic11b.hex"), .ROM_FILE_B("roms/basic10.hex")) dut (
        .clk(clk), .rst(rst), .rom_bank(tb_bank), .turbo(tb_turbo),
        .kbd_azerty(1'b0), .kbd_mods(8'd0), .kbd_k1(8'd0), .kbd_k2(8'd0), .kbd_k3(8'd0), .kbd_k4(8'd0),
        .inj_active(1'b0), .inj_col(3'd0), .inj_row(3'd0), .inj_shift(1'b0),
        .exp_addr(), .exp_we(), .exp_do(), .exp_io_page(), .exp_tphase(),
        .ext_din(8'hFF), .ext_irq(1'b0), .ext_romdis(1'b0), .ext_map(1'b0),
        .ext_ioctl(1'b0),
        .prn_data(), .prn_strobe_n(), .prn_ack(1'b1),
        .tape_out(), .tape_motor(), .tape_in(1'b1),
        .fb_we(fb_we), .fb_addr(fb_addr), .fb_data(fb_data),
        .frame_tick(frame_tick),
        .audio(audio),
        .cpu_irq_dbg(irq_dbg)
    );

    always #10 clk = ~clk;

    reg tb_turbo = 0;
    // +bank=1 : boot sur la banque BASIC 1.0 (sa bannière contient aussi ORIC)
    integer bank_arg = 0;
    initial if (!$value$plusargs("bank=%d", bank_arg)) bank_arg = 0;
    wire tb_bank = (bank_arg != 0);
    integer cycles = 0;
    integer i, r, c;
    reg found = 0;
    reg charset_ok = 0;
    reg turbo_alive = 0;
    reg [7:0] ch;
    reg [40*8-1:0] line;

    task scan_screen;
        begin
            found = 0;
            for (i = 16'hBB80; i <= 16'hBFDC; i = i + 1)
                if (dut.ram.mem[i]     == "O" && dut.ram.mem[i + 1] == "R" &&
                    dut.ram.mem[i + 2] == "I" && dut.ram.mem[i + 3] == "C")
                    found = 1;
            charset_ok = (dut.ram.mem[16'hB400 + 8*8'h41 + 2] != 8'h00);
        end
    endtask

    task dump_screen;
        begin
            for (r = 0; r < 28; r = r + 1) begin
                for (c = 0; c < 40; c = c + 1) begin
                    ch = dut.ram.mem[16'hBB80 + r*40 + c];
                    if (ch < 8'h20 || ch > 8'h7E) ch = " ";
                    line[(39-c)*8 +: 8] = ch;
                end
                $display("|%s|", line);
            end
        end
    endtask

    initial begin
        repeat (10) @(negedge clk);
        rst = 0;

        // 4 M cycles CPU max (~4 s Oric réel)
        for (cycles = 0; cycles < 4_000_000 && !found; cycles = cycles + 1) begin
            repeat (DIV) @(negedge clk);
            if (cycles % 200_000 == 0) begin
                scan_screen;
                $display("t=%0d cycles CPU, banniere=%0d charset=%0d, PC~%04x",
                         cycles, found, charset_ok, dut.cpu_ab);
            end
        end

        scan_screen;
        $display("=== Ecran final ===");
        dump_screen;

        // ---- Mode TURBO : bascule à chaud, la machine doit rester vivante ----
        // (cen1 passe de DIV=13 à TURBO_DIV=6 en cours d'exécution : on vérifie
        // que le CPU continue d'exécuter la ROM — IRQ 100 Hz toujours servie —
        // et que l'écran n'est pas corrompu, puis retour normal.)
        turbo_alive = 0;
        tb_turbo = 1;
        for (i = 0; i < 200_000 && !turbo_alive; i = i + 1) begin
            @(negedge clk);
            if (irq_dbg) turbo_alive = 1;      // une IRQ vue en turbo
        end
        repeat (100_000) @(negedge clk);       // laisse tourner en turbo
        tb_turbo = 0;
        repeat (10_000) @(negedge clk);        // retour 1 MHz
        scan_screen;                            // bannière toujours en place ?

        if (found && charset_ok && turbo_alive)
            $display("ALL TESTS PASSED (tb_boot)");
        else
            $display("FAIL: banniere=%0d charset=%0d turbo_alive=%0d apres %0d cycles CPU",
                     found, charset_ok, turbo_alive, cycles);
        $finish;
    end

endmodule
