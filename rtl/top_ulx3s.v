// Top-level ULX3S (ECP5-85F) — Oric Atmos.
// Domaines : clk_sys 25 MHz (Oric, CPU = 25/25 = 1 MHz exact),
// clk_usb 12 MHz (clavier), clk_pixel 25 MHz + clk_shift 125 MHz (DVI).

module top_ulx3s (
    input        clk_25mhz,
    input  [6:0] btn,
    output [7:0] led,
    output [3:0] gpdi_dp,
    inout        usb_fpga_bd_dp,
    inout        usb_fpga_bd_dn,
    output [3:0] audio_l,
    output [3:0] audio_r,
    output       wifi_gpio0
);

    // Maintien de l'alimentation de la carte
    assign wifi_gpio0 = 1'b1;

    // ------------------------------------------------------------------
    // Horloges
    // ------------------------------------------------------------------
    wire clk_shift, clk_pixel, clk_sys, clk_usb;
    wire lock_video, lock_sys;

    pll_video pllv (
        .clkin   (clk_25mhz),
        .clkout0 (clk_shift),    // 125 MHz
        .clkout1 (clk_pixel),    // 25 MHz
        .locked  (lock_video)
    );

    pll_sys plls (
        .clkin   (clk_25mhz),
        .clkout0 (clk_sys),      // 25 MHz (VCO 600, division exacte)
        .clkout1 (clk_usb),      // 12 MHz
        .locked  (lock_sys)
    );

    // ------------------------------------------------------------------
    // Reset : power-on + BTN1 (FIRE1)
    // ------------------------------------------------------------------
    reg [15:0] por = 16'hFFFF;
    always @(posedge clk_sys)
        if (!lock_sys || !lock_video)
            por <= 16'hFFFF;
        else if (por != 0)
            por <= por - 16'd1;

    wire rst_sys = (por != 0) || btn[1];

    reg [3:0] rst_usb_sync = 4'hF;
    always @(posedge clk_usb) rst_usb_sync <= {rst_usb_sync[2:0], rst_sys};
    wire rst_usb = rst_usb_sync[3];

    reg [3:0] rst_pix_sync = 4'hF;
    always @(posedge clk_pixel) rst_pix_sync <= {rst_pix_sync[2:0], rst_sys};
    wire rst_pixel = rst_pix_sync[3];

    // ------------------------------------------------------------------
    // Clavier USB (US2)
    // ------------------------------------------------------------------
    wire [1:0] usb_typ;
    wire       usb_report, usb_conerr;
    wire [7:0] hid_mods, hid_k1, hid_k2, hid_k3, hid_k4;

    usb_hid_host usb (
        .usbclk        (clk_usb),
        .usbrst_n      (~rst_usb),
        .usb_dm        (usb_fpga_bd_dn),
        .usb_dp        (usb_fpga_bd_dp),
        .typ           (usb_typ),
        .report        (usb_report),
        .conerr        (usb_conerr),
        .key_modifiers (hid_mods),
        .key1          (hid_k1),
        .key2          (hid_k2),
        .key3          (hid_k3),
        .key4          (hid_k4),
        .mouse_btn     (),
        .mouse_dx      (),
        .mouse_dy      (),
        .game_l        (), .game_r (), .game_u (), .game_d (),
        .game_a        (), .game_b (), .game_x (), .game_y (),
        .game_sel      (), .game_sta (),
        .dbg_hid_report()
    );

    // Passage 12 MHz -> 24 MHz : signaux quasi statiques, double bascule
    reg [7:0] mods_s1, k1_s1, k2_s1, k3_s1, k4_s1;
    reg [7:0] mods_s2, k1_s2, k2_s2, k3_s2, k4_s2;
    always @(posedge clk_sys) begin
        mods_s1 <= hid_mods; k1_s1 <= hid_k1; k2_s1 <= hid_k2;
        k3_s1 <= hid_k3;     k4_s1 <= hid_k4;
        mods_s2 <= mods_s1;  k1_s2 <= k1_s1;  k2_s2 <= k2_s1;
        k3_s2 <= k3_s1;      k4_s2 <= k4_s1;
    end

    // ------------------------------------------------------------------
    // Système Oric
    // ------------------------------------------------------------------
    wire        fb_we;
    wire [15:0] fb_waddr;
    wire [3:0]  fb_wdata;
    wire        frame_tick;
    wire [9:0]  audio_mix;
    wire        irq_dbg;

    oric_atmos #(.DIV(25), .ROM_FILE("basic11b.hex")) oric (
        .clk         (clk_sys),
        .rst         (rst_sys),
        .kbd_mods    (mods_s2),
        .kbd_k1      (k1_s2),
        .kbd_k2      (k2_s2),
        .kbd_k3      (k3_s2),
        .kbd_k4      (k4_s2),
        .fb_we       (fb_we),
        .fb_addr     (fb_waddr),
        .fb_data     (fb_wdata),
        .frame_tick  (frame_tick),
        .audio       (audio_mix),
        .cpu_irq_dbg (irq_dbg)
    );

    // ------------------------------------------------------------------
    // Vidéo
    // ------------------------------------------------------------------
    wire [15:0] fb_raddr;
    wire [3:0]  fb_rdata;

    framebuffer fb (
        .wclk  (clk_sys),
        .we    (fb_we),
        .waddr (fb_waddr),
        .wdata (fb_wdata),
        .rclk  (clk_pixel),
        .raddr (fb_raddr),
        .rdata (fb_rdata)
    );

    hdmi_out hdmi (
        .clk_pixel (clk_pixel),
        .clk_shift (clk_shift),
        .rst       (rst_pixel),
        .fb_raddr  (fb_raddr),
        .fb_rdata  (fb_rdata),
        .gpdi_dp   (gpdi_dp)
    );

    // ------------------------------------------------------------------
    // Audio : DAC résistif 4 bits de l'ULX3S
    // ------------------------------------------------------------------
    assign audio_l = audio_mix[9:6];
    assign audio_r = audio_mix[9:6];

    // ------------------------------------------------------------------
    // LEDs de vie
    // ------------------------------------------------------------------
    reg [5:0] frame_div;
    always @(posedge clk_sys)
        if (frame_tick) frame_div <= frame_div + 6'd1;

    assign led[0] = frame_div[5];          // clignote ~0,8 Hz si la ULA balaye
    assign led[1] = (usb_typ == 2'd1);     // clavier détecté
    assign led[2] = usb_conerr;
    assign led[3] = irq_dbg;
    assign led[7:4] = 4'b0;

endmodule
