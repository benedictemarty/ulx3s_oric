// Top-level Tang Nano 20K — Oric Atmos (portage Gowin GW2AR-18).
// Domaine unique 27 MHz (CPU 1 MHz exact avec DIV=27, pixel HDMI 576p50
// verrouillé sur le balayage ULA) + 135 MHz pour la sérialisation TMDS.
// Clavier : injection série 115200 via le BL616 (USB-C, comme picocom).

module top_tangnano20k (
    input        clk27,          // quartz 27 MHz
    input        btn_s1,         // reset utilisateur
    input        uart_rx,        // BL616 -> FPGA (clavier série)
    output [5:0] leds_n,
    output       tmds_clk_p,
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,
    output       audio_pwm       // sigma-delta 1 bit (futur PAM8302)
);

    // ------------------------------------------------------------------
    // Horloges + reset
    // ------------------------------------------------------------------
    wire clk_shift, pll_lock;
    gowin_rpll pll (.clkin(clk27), .clkout(clk_shift), .locked(pll_lock));

    reg [15:0] por = 16'hFFFF;
    always @(posedge clk27)
        if (!pll_lock)      por <= 16'hFFFF;
        else if (por != 0)  por <= por - 16'd1;
    wire rst = (por != 0) || btn_s1;

    // ------------------------------------------------------------------
    // Clavier série (BL616)
    // ------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       inj_active, inj_shift;
    wire [2:0] inj_col, inj_row;

    uart_rx #(.CLK_HZ(27_000_000), .BAUD(115_200)) uart (
        .clk(clk27), .rst(rst), .rx(uart_rx),
        .data(rx_data), .valid(rx_valid)
    );
    key_injector #(.PRESS_TICKS(1_215_000), .GAP_TICKS(675_000)) inj (
        .clk(clk27), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row),
        .inj_shift(inj_shift)
    );

    // ------------------------------------------------------------------
    // Cœur Oric (inchangé, DIV=27)
    // ------------------------------------------------------------------
    wire        fb_we;
    wire [15:0] fb_addr;
    wire [3:0]  fb_data;
    wire [8:0]  scan_y;
    wire [5:0]  scan_x;
    wire        frame_tick;
    wire [9:0]  audio_mix;
    wire        irq_dbg;

    oric_atmos #(.DIV(27), .ROM_FILE("basic11b.hex")) oric (
        .clk         (clk27),
        .rst         (rst),
        .kbd_mods    (8'd0),
        .kbd_k1      (8'd0),
        .kbd_k2      (8'd0),
        .kbd_k3      (8'd0),
        .kbd_k4      (8'd0),
        .inj_active  (inj_active),
        .inj_col     (inj_col),
        .inj_row     (inj_row),
        .inj_shift   (inj_shift),
        .exp_addr    (),
        .exp_we      (),
        .exp_do      (),
        .exp_io_page (),
        .exp_tphase  (),
        .ext_din     (8'hFF),
        .ext_irq     (1'b0),
        .ext_romdis  (1'b0),
        .ext_map     (1'b0),
        .ext_ioctl   (1'b0),
        .prn_data    (),
        .prn_strobe_n(),
        .prn_ack     (1'b1),
        .tape_out    (),
        .tape_motor  (),
        .tape_in     (1'b1),
        .fb_we       (fb_we),
        .fb_addr     (fb_addr),
        .fb_data     (fb_data),
        .scan_y      (scan_y),
        .scan_x      (scan_x),
        .frame_tick  (frame_tick),
        .audio       (audio_mix),
        .cpu_irq_dbg (irq_dbg)
    );

    // ------------------------------------------------------------------
    // Vidéo 576p50 verrouillée + TMDS
    // ------------------------------------------------------------------
    wire [7:0] red, grn, blu;
    wire de, hs, vs;

    video_576p video (
        .clk(clk27), .rst(rst),
        .fb_we(fb_we), .fb_data(fb_data),
        .scan_y(scan_y), .scan_x(scan_x), .fb_addr(fb_addr),
        .red(red), .grn(grn), .blu(blu),
        .de(de), .hsync(hs), .vsync(vs)
    );

    hdmi_tx_gowin hdmi (
        .clk_pixel(clk27), .clk_shift(clk_shift), .rst(rst),
        .red(red), .grn(grn), .blu(blu), .de(de), .hsync(hs), .vsync(vs),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    // ------------------------------------------------------------------
    // Audio : sigma-delta 1 bit
    // ------------------------------------------------------------------
    reg [10:0] sd_acc;
    always @(posedge clk27)
        sd_acc <= {1'b0, sd_acc[9:0]} + {1'b0, audio_mix};
    assign audio_pwm = sd_acc[10];

    // ------------------------------------------------------------------
    // LEDs (actives bas)
    // ------------------------------------------------------------------
    reg [5:0] frame_div;
    always @(posedge clk27)
        if (frame_tick) frame_div <= frame_div + 6'd1;
    assign leds_n = ~{4'b0, irq_dbg, frame_div[5]};

endmodule
