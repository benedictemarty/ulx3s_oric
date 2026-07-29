// Sortie DVI 640x480@60 : lit le framebuffer 240x224 (zoom x2, centré),
// palette Oric 8 couleurs, encodage TMDS et sérialisation 10:1 en DDR
// (ODDRX1F à 125 MHz). Les broches GPDI de l'ULX3S sont câblées en direct :
// IO_TYPE LVCMOS33D sur les broches _dp, paire négative générée par l'IO.

module hdmi_out (
    input        clk_pixel,    // 25 MHz
    input        clk_shift,    // 125 MHz
    input        rst,

    // Lecture framebuffer (domaine clk_pixel)
    output [15:0] fb_raddr,
    input  [3:0]  fb_rdata,

    output [3:0] gpdi_dp       // {clk, r, g, b}
);

    // Timing 640x480@60 (25,175 MHz nominal ; 25 MHz accepté par les écrans)
    localparam H_VISIBLE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48;
    localparam V_VISIBLE = 480, V_FRONT = 10, V_SYNC = 2,  V_BACK = 33;
    localparam H_TOTAL = 800, V_TOTAL = 525;

    // Fenêtre Oric 480x448 centrée
    localparam OX = 80, OY = 16;

    reg [9:0] hc, vc;
    always @(posedge clk_pixel) begin
        if (rst) begin
            hc <= 0; vc <= 0;
        end else begin
            if (hc == H_TOTAL - 1) begin
                hc <= 0;
                vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 10'd1;
            end else
                hc <= hc + 10'd1;
        end
    end

    wire de    = (hc < H_VISIBLE) && (vc < V_VISIBLE);
    wire hsync = ~((hc >= H_VISIBLE + H_FRONT) && (hc < H_VISIBLE + H_FRONT + H_SYNC));
    wire vsync = ~((vc >= V_VISIBLE + V_FRONT) && (vc < V_VISIBLE + V_FRONT + V_SYNC));

    // Lecture framebuffer avec 1 cycle d'avance (latence BRAM)
    wire [9:0] hc1 = (hc == H_TOTAL - 1) ? 10'd0 : hc + 10'd1;
    wire in_win = (hc1 >= OX) && (hc1 < OX + 480) && (vc >= OY) && (vc < OY + 448);
    wire [8:0] ox = (hc1 - OX) >> 1;      // 0..239
    wire [8:0] oy = (vc  - OY) >> 1;      // 0..223
    assign fb_raddr = {7'd0, oy} * 16'd240 + {7'd0, ox};

    reg in_win_q;
    always @(posedge clk_pixel) in_win_q <= in_win;

    // Palette Oric : 8 couleurs saturées (bits {R,G,B} = index)
    reg [7:0] red, grn, blu;
    always @* begin
        if (in_win_q) begin
            red = fb_rdata[0] ? 8'hFF : 8'h00;
            grn = fb_rdata[1] ? 8'hFF : 8'h00;
            blu = fb_rdata[2] ? 8'hFF : 8'h00;
        end else begin
            red = 8'h00; grn = 8'h00; blu = 8'h00;
        end
    end

    // Encodage TMDS
    wire [9:0] tmds_r, tmds_g, tmds_b;
    tmds_encoder enc_b (.clk(clk_pixel), .data(blu), .ctrl({vsync, hsync}), .de(de), .tmds(tmds_b));
    tmds_encoder enc_g (.clk(clk_pixel), .data(grn), .ctrl(2'b00),          .de(de), .tmds(tmds_g));
    tmds_encoder enc_r (.clk(clk_pixel), .data(red), .ctrl(2'b00),          .de(de), .tmds(tmds_r));

`ifndef SIM
    // Sérialisation 10:1 : 2 bits par cycle 125 MHz (DDR)
    reg [2:0] mod5;
    reg [9:0] sh_r, sh_g, sh_b, sh_c;
    always @(posedge clk_shift) begin
        if (mod5 == 3'd4) begin
            mod5 <= 3'd0;
            sh_r <= tmds_r;
            sh_g <= tmds_g;
            sh_b <= tmds_b;
            sh_c <= 10'b0000011111;   // horloge pixel sur le canal clock
        end else begin
            mod5 <= mod5 + 3'd1;
            sh_r <= {2'b00, sh_r[9:2]};
            sh_g <= {2'b00, sh_g[9:2]};
            sh_b <= {2'b00, sh_b[9:2]};
            sh_c <= {2'b00, sh_c[9:2]};
        end
    end

    ODDRX1F ser_c (.D0(sh_c[0]), .D1(sh_c[1]), .SCLK(clk_shift), .RST(1'b0), .Q(gpdi_dp[3]));
    ODDRX1F ser_r (.D0(sh_r[0]), .D1(sh_r[1]), .SCLK(clk_shift), .RST(1'b0), .Q(gpdi_dp[2]));
    ODDRX1F ser_g (.D0(sh_g[0]), .D1(sh_g[1]), .SCLK(clk_shift), .RST(1'b0), .Q(gpdi_dp[1]));
    ODDRX1F ser_b (.D0(sh_b[0]), .D1(sh_b[1]), .SCLK(clk_shift), .RST(1'b0), .Q(gpdi_dp[0]));
`else
    assign gpdi_dp = 4'b0;
`endif

endmodule
