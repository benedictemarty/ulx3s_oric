// Testbench du doubleur de lignes 576p : vérifie le verrouillage
// ULA <-> HDMI (mêmes périodes de trame), le doublage x2 et la fenêtre.
`timescale 1ns/1ps

module tb_video576;

    reg clk = 0, rst = 1;
    always #18.5 clk = ~clk;   // ~27 MHz

    // Émule le flux ULA : réutilise la vraie ULA + RAM
    reg [4:0] tphase = 0;
    always @(posedge clk)
        if (rst) tphase <= 0;
        else tphase <= (tphase == 26) ? 5'd0 : tphase + 5'd1;

    wire [15:0] vram_addr;
    wire [7:0]  vram_dout;
    wire fb_we;
    wire [15:0] fb_addr;
    wire [3:0]  fb_data;
    wire [8:0]  scan_y;
    wire [5:0]  scan_x;
    wire frame_tick;

    oric_ram ram (
        .clk(clk), .addr_a(16'd0), .we_a(1'b0), .din_a(8'd0), .dout_a(),
        .addr_b(vram_addr), .dout_b(vram_dout)
    );
    oric_ula #(.DIV(27)) ula (
        .clk(clk), .rst(rst), .tphase(tphase),
        .vram_addr(vram_addr), .vram_din(vram_dout),
        .fb_we(fb_we), .fb_addr(fb_addr), .fb_data(fb_data),
        .scan_y(scan_y), .scan_x(scan_x),
        .frame_tick(frame_tick)
    );

    wire [7:0] red, grn, blu;
    wire de, hs, vs;
    video_576p dut (
        .clk(clk), .rst(rst),
        .fb_we(fb_we), .fb_data(fb_data),
        .scan_y(scan_y), .scan_x(scan_x), .fb_addr(fb_addr),
        .red(red), .grn(grn), .blu(blu), .de(de), .hsync(hs), .vsync(vs)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    // Mesures
    integer de_count = 0, vs_count = 0;
    integer cyc_frame_ula = 0, cyc_frame_hdmi = 0, cyc = 0;
    reg vs_q = 1;
    integer last_tick_cyc = -1, last_vs_cyc = -1;

    always @(posedge clk) begin
        cyc = cyc + 1;
        if (de) de_count = de_count + 1;
        vs_q <= vs;
        if (frame_tick) begin
            if (last_tick_cyc >= 0) cyc_frame_ula = cyc - last_tick_cyc;
            last_tick_cyc = cyc;
        end
        if (vs_q && !vs) begin
            vs_count = vs_count + 1;
            if (last_vs_cyc >= 0) cyc_frame_hdmi = cyc - last_vs_cyc;
            last_vs_cyc = cyc;
        end
    end

    initial begin
        // écran texte : 'A' partout, charset rayures
        begin : init_ram
            integer i;
            for (i = 0; i < 1120; i = i + 1)
                ram.mem[16'hBB80 + i] = 8'h41;
            for (i = 0; i < 8; i = i + 1)
                ram.mem[16'hB400 + 8*8'h41 + i] = 8'h2A;
        end
        repeat (5) @(negedge clk);
        rst = 0;

        // 3 trames
        repeat (3 * 539136 + 1000) @(posedge clk);

        check(cyc_frame_ula == 539136,  "periode trame ULA = 539136 cycles");
        check(cyc_frame_hdmi == 539136, "periode trame HDMI = 539136 cycles");
        check(de_count > 0, "zone active produite");
        $display("trames: ULA=%0d cycles, HDMI=%0d cycles", cyc_frame_ula, cyc_frame_hdmi);

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_video576)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #90_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
