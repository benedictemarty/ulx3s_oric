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

    oric_atmos #(.DIV(DIV), .ROM_FILE("roms/basic11b.hex")) dut (
        .clk(clk), .rst(rst),
        .kbd_mods(8'd0), .kbd_k1(8'd0), .kbd_k2(8'd0), .kbd_k3(8'd0), .kbd_k4(8'd0),
        .fb_we(fb_we), .fb_addr(fb_addr), .fb_data(fb_data),
        .frame_tick(frame_tick),
        .audio(audio),
        .cpu_irq_dbg(irq_dbg)
    );

    always #10 clk = ~clk;

    integer cycles = 0;
    integer i, r, c;
    reg found = 0;
    reg charset_ok = 0;
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

        if (found && charset_ok)
            $display("ALL TESTS PASSED (tb_boot)");
        else
            $display("FAIL: banniere=%0d charset=%0d apres %0d cycles CPU",
                     found, charset_ok, cycles);
        $finish;
    end

endmodule
