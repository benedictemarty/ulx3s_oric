// Testbench ULA : rendu d'une trame complète en mode TEXT.
// RAM préchargée : écran rempli de 'A' (0x41), attribut INK rouge en (0,0),
// charset motif 101010 pour 'A'. Vérifie le nombre d'écritures framebuffer,
// le décodage attribut, le reset des attributs en début de ligne et la
// zone TEXT du bas (lignes 200-223).
`timescale 1ns/1ps

module tb_ula;

    localparam DIV = 13;

    reg clk = 0, rst = 1;
    reg [4:0] tphase = 0;
    wire [15:0] vram_addr;
    wire [7:0]  vram_dout;
    wire fb_we;
    wire [15:0] fb_addr;
    wire [3:0]  fb_data;
    wire frame_tick;

    oric_ram ram (
        .clk(clk),
        .addr_a(16'd0), .we_a(1'b0), .din_a(8'd0), .dout_a(),
        .addr_b(vram_addr), .dout_b(vram_dout)
    );

    oric_ula #(.DIV(DIV)) dut (
        .clk(clk), .rst(rst), .tphase(tphase),
        .vram_addr(vram_addr), .vram_din(vram_dout),
        .fb_we(fb_we), .fb_addr(fb_addr), .fb_data(fb_data),
        .frame_tick(frame_tick)
    );

    always #10 clk = ~clk;

    always @(posedge clk)
        if (rst) tphase <= 0;
        else tphase <= (tphase == DIV - 1) ? 5'd0 : tphase + 5'd1;

    // Capture du framebuffer (uniquement la 2e trame, état stabilisé)
    reg [3:0] fb [0:53759];
    integer wr_count = 0;
    reg capturing = 0;
    always @(posedge clk)
        if (fb_we && capturing) begin
            fb[fb_addr] <= fb_data;
            wr_count = wr_count + 1;
        end

    integer i, errors = 0;

    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    function [15:0] px(input [8:0] x, input [8:0] y);
        px = y * 240 + x;
    endfunction

    initial begin
        // Écran texte : tout à 'A', attribut INK rouge (0x01) en (0,0)
        for (i = 0; i < 1120; i = i + 1)
            ram.mem[16'hBB80 + i] = 8'h41;
        ram.mem[16'hBB80] = 8'h01;
        // 'A' inversé en (2,0) : bit 7
        ram.mem[16'hBB82] = 8'hC1;
        // Charset : 'A' = motif 101010 sur les 8 lignes
        for (i = 0; i < 8; i = i + 1)
            ram.mem[16'hB400 + 8*8'h41 + i] = 8'h2A;

        repeat (5) @(negedge clk);
        rst = 0;

        // Trame 1 : stabilisation ; trame 2 : capture
        @(posedge frame_tick);
        capturing = 1;
        @(posedge frame_tick);
        capturing = 0;

        if (wr_count != 53760)
            $display("info: wr_count = %0d", wr_count);
        check(wr_count == 53760, "53760 ecritures framebuffer (1 trame)");

        // Cellule (0,0) : attribut -> remplissage papier noir
        check(fb[px(0,0)] == 4'd0 && fb[px(5,0)] == 4'd0, "cellule attribut = papier");

        // Cellule (1,0) : 'A' avec ink rouge (attribut applique) : 101010
        check(fb[px(6,0)]  == 4'd1, "pixel fg rouge (6,0)");
        check(fb[px(7,0)]  == 4'd0, "pixel bg noir (7,0)");
        check(fb[px(8,0)]  == 4'd1, "pixel fg rouge (8,0)");
        check(fb[px(11,0)] == 4'd0, "pixel bg noir (11,0)");

        // Cellule (2,0) : 'A' inverse : fg = 1^7 = 6, bg = 0^7 = 7
        check(fb[px(12,0)] == 4'd6, "pixel inverse fg cyan (12,0)");
        check(fb[px(13,0)] == 4'd7, "pixel inverse bg blanc (13,0)");

        // Ligne 8 (rangée 1) : reset ink -> blanc, cellule 0 = 'A'
        check(fb[px(0,8)] == 4'd7, "ligne 8 : ink par defaut blanc");
        check(fb[px(1,8)] == 4'd0, "ligne 8 : bg noir");

        // Zone basse (ligne 200 = rangée 25) : texte depuis $BB80+1000
        check(fb[px(0,200)] == 4'd7, "ligne 200 : rangee 25 texte");
        check(fb[px(1,200)] == 4'd0, "ligne 200 : bg");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_ula)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
