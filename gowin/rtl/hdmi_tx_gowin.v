// Émetteur DVI pour Gowin : 3 encodeurs TMDS (réutilisés du portage ECP5)
// + sérialiseurs OSER10 (10:1, DDR interne à 5x l'horloge pixel) +
// tampons différentiels TLVDS_OBUF vers le connecteur HDMI du Tang Nano.

module hdmi_tx_gowin (
    input        clk_pixel,     // 27 MHz
    input        clk_shift,     // 135 MHz (5x)
    input        rst,
    input  [7:0] red,
    input  [7:0] grn,
    input  [7:0] blu,
    input        de,
    input        hsync,
    input        vsync,
    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n
);

    wire [9:0] enc_r, enc_g, enc_b;
    tmds_encoder enc_blu (.clk(clk_pixel), .data(blu), .ctrl({vsync, hsync}),
                          .de(de), .tmds(enc_b));
    tmds_encoder enc_grn (.clk(clk_pixel), .data(grn), .ctrl(2'b00),
                          .de(de), .tmds(enc_g));
    tmds_encoder enc_red (.clk(clk_pixel), .data(red), .ctrl(2'b00),
                          .de(de), .tmds(enc_r));

    wire ser_clk, ser_r, ser_g, ser_b;

`ifndef SIM
    OSER10 ser_c (.Q(ser_clk), .D0(1'b1), .D1(1'b1), .D2(1'b1), .D3(1'b1),
                  .D4(1'b1), .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
                  .D9(1'b0), .PCLK(clk_pixel), .FCLK(clk_shift), .RESET(rst));
    OSER10 ser_0 (.Q(ser_b), .D0(enc_b[0]), .D1(enc_b[1]), .D2(enc_b[2]),
                  .D3(enc_b[3]), .D4(enc_b[4]), .D5(enc_b[5]), .D6(enc_b[6]),
                  .D7(enc_b[7]), .D8(enc_b[8]), .D9(enc_b[9]),
                  .PCLK(clk_pixel), .FCLK(clk_shift), .RESET(rst));
    OSER10 ser_1 (.Q(ser_g), .D0(enc_g[0]), .D1(enc_g[1]), .D2(enc_g[2]),
                  .D3(enc_g[3]), .D4(enc_g[4]), .D5(enc_g[5]), .D6(enc_g[6]),
                  .D7(enc_g[7]), .D8(enc_g[8]), .D9(enc_g[9]),
                  .PCLK(clk_pixel), .FCLK(clk_shift), .RESET(rst));
    OSER10 ser_2 (.Q(ser_r), .D0(enc_r[0]), .D1(enc_r[1]), .D2(enc_r[2]),
                  .D3(enc_r[3]), .D4(enc_r[4]), .D5(enc_r[5]), .D6(enc_r[6]),
                  .D7(enc_r[7]), .D8(enc_r[8]), .D9(enc_r[9]),
                  .PCLK(clk_pixel), .FCLK(clk_shift), .RESET(rst));

    TLVDS_OBUF buf_c (.I(ser_clk), .O(tmds_clk_p), .OB(tmds_clk_n));
    TLVDS_OBUF buf_0 (.I(ser_b),   .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
    TLVDS_OBUF buf_1 (.I(ser_g),   .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
    TLVDS_OBUF buf_2 (.I(ser_r),   .O(tmds_d_p[2]), .OB(tmds_d_n[2]));
`else
    assign tmds_clk_p = 1'b0; assign tmds_clk_n = 1'b1;
    assign tmds_d_p = 3'b0;   assign tmds_d_n = 3'b111;
`endif

endmodule
