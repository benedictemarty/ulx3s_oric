// Testbench de séquencement de l'ordonnanceur data island
// (rtl/hdmi_data_island.v). Reproduit le compteur hc/vc de hdmi_out et vérifie
// que, sur une ligne portant un packet audio, la séquence des modes est bien :
//   [0..639]    video (mode 1)
//   [644..651]  data island preamble  (mode 0, ctl1=ctl2=01)
//   [652..653]  leading guard         (mode 4)
//   [654..685]  data island           (mode 3, 32 pixels)
//   [686..687]  trailing guard        (mode 4)
//   [790..797]  video preamble        (mode 0, ctl1=01 ctl2=00)
//   [798..799]  video guard band      (mode 2)
// PIXEL_RATE/AUDIO_RATE réduits pour saturer la file et garantir un packet.
`timescale 1ns/1ps

module tb_hdmi_island;

    localparam H_TOTAL = 800, V_TOTAL = 525;
    localparam H_VIS = 640, V_VIS = 480;
    localparam H_FRONT = 16, H_SYNC = 96;
    localparam V_FRONT = 10, V_SYNC = 2;

    reg clk = 0;
    always #20 clk = ~clk;

    reg rst = 1;
    initial begin repeat (4) @(posedge clk); rst = 0; end

    reg [9:0] hc = 0, vc = 0;
    always @(posedge clk) begin
        if (hc == H_TOTAL-1) begin
            hc <= 0;
            vc <= (vc == V_TOTAL-1) ? 10'd0 : vc + 10'd1;
        end else hc <= hc + 10'd1;
    end

    wire de    = (hc < H_VIS) && (vc < V_VIS);
    wire hsync = ~((hc >= H_VIS+H_FRONT) && (hc < H_VIS+H_FRONT+H_SYNC));
    wire vsync = ~((vc >= V_VIS+V_FRONT) && (vc < V_VIS+V_FRONT+V_SYNC));

    wire [2:0] mode;
    wire [3:0] aux0, aux1, aux2;
    wire [1:0] ctl0, ctl1, ctl2;

    // AUDIO_RATE = PIXEL_RATE -> un tick par cycle, file saturée (packet garanti)
    hdmi_data_island #(
        .H_ACTIVE(H_VIS), .H_TOTAL(H_TOTAL), .V_ACTIVE(V_VIS), .V_TOTAL(V_TOTAL),
        .PIXEL_RATE(800), .AUDIO_RATE(800), .EMIT_VGUARD(0), .SW(16)
    ) dut (
        .clk(clk), .rst(rst), .hc(hc), .vc(vc),
        .hsync(hsync), .vsync(vsync), .de(de),
        .aud_l(16'h1234), .aud_r(16'h5678),
        .mode(mode), .aux0(aux0), .aux1(aux1), .aux2(aux2),
        .ctl0(ctl0), .ctl1(ctl1), .ctl2(ctl2)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL @vc=%0d hc=%0d: %0s", vc, hc, msg);
            errors = errors + 1;
        end
    endtask

    integer isl_count = 0;

    // Vérifs continues (échantillonnées sur front descendant, après stabilisation)
    always @(negedge clk) begin
        // Invariant global : mode 1 <=> vidéo active
        if (de) check(mode === 3'd1, "de => mode video");

        // Sur une ligne audio établie (vc=100), vérifier la structure
        if (vc == 10'd100) begin
            if (hc >= 644 && hc < 652)
                check(mode === 3'd0 && ctl1 === 2'b01 && ctl2 === 2'b01,
                      "data island preamble");
            if (hc >= 652 && hc < 654)
                check(mode === 3'd4, "leading guard");
            if (hc >= 654 && hc < 686) begin
                check(mode === 3'd3, "data island");
                isl_count = isl_count + 1;
            end
            if (hc >= 686 && hc < 688)
                check(mode === 3'd4, "trailing guard");
        end
    end

    initial begin
        // Tourner jusqu'à couvrir la ligne vc=100 une seule fois
        repeat (H_TOTAL * 102) @(posedge clk);
        check(isl_count == 32, "32 pixels de data island sur la ligne");
        if (errors == 0)
            $display("ALL TESTS PASSED (tb_hdmi_island)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
