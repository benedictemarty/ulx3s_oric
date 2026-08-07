// Sortie HDMI 640x480@60 avec audio : lit le framebuffer 240x224 (zoom x2,
// centré), palette Oric 8 couleurs, encodage TMDS + data islands audio, et
// sérialisation 10:1 en DDR (ODDRX1F à 125 MHz). Les broches GPDI de l'ULX3S
// sont câblées en direct (LVCMOS33D sur les broches _dp).
//
// L'audio (aud_l/aud_r, PCM signé 16 bits, domaine clk_pixel) est transporté
// dans les data islands HDMI (hdmi_data_island + hdmi_tmds_channel). Sur un
// écran DVI (sans audio), l'image reste identique : les data islands occupent
// le blanking et sont ignorés.

module hdmi_out #(
    parameter SW = 16
) (
    input        clk_pixel,    // 25 MHz
    input        clk_shift,    // 125 MHz
    input        rst,

    // Lecture framebuffer (domaine clk_pixel)
    output [15:0] fb_raddr,
    input  [3:0]  fb_rdata,

    // Audio (domaine clk_pixel)
    input  [SW-1:0] aud_l,
    input  [SW-1:0] aud_r,

    // OSD (liste des fichiers SD)
    input           osd_enable,
    input  [7:0]    osd_file_count,
    input  [5:0]    osd_sel_idx,
    output [5:0]    osd_name_idx,
    input  [87:0]   osd_name,

    output [3:0] gpdi_dp       // {clk, r, g, b}
);

    // Timing 640x480@60 (pixel clock 25 MHz exact)
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
    reg [7:0] pal_r, pal_g, pal_b;
    always @* begin
        if (in_win_q) begin
            pal_r = fb_rdata[0] ? 8'hFF : 8'h00;
            pal_g = fb_rdata[1] ? 8'hFF : 8'h00;
            pal_b = fb_rdata[2] ? 8'hFF : 8'h00;
        end else begin
            pal_r = 8'h00; pal_g = 8'h00; pal_b = 8'h00;
        end
    end

    // Incrustation OSD par-dessus la vidéo
    wire       osd_on;
    wire [7:0] osd_r, osd_g, osd_b;
    osd osd_i (
        .hc(hc), .vc(vc), .enable(osd_enable),
        .file_count(osd_file_count), .sel_idx(osd_sel_idx),
        .name_idx(osd_name_idx), .name(osd_name),
        .osd_on(osd_on), .osd_r(osd_r), .osd_g(osd_g), .osd_b(osd_b)
    );

    wire [7:0] red = osd_on ? osd_r : pal_r;
    wire [7:0] grn = osd_on ? osd_g : pal_g;
    wire [7:0] blu = osd_on ? osd_b : pal_b;

    // ------------------------------------------------------------------
    // Ordonnanceur data islands (mode + nibbles TERC4 + contrôle)
    // ------------------------------------------------------------------
    wire [2:0] mode;
    wire [3:0] aux0, aux1, aux2;
    wire [1:0] ctl0, ctl1, ctl2;

    hdmi_data_island #(
        .H_ACTIVE(H_VISIBLE), .H_TOTAL(H_TOTAL),
        .V_ACTIVE(V_VISIBLE), .V_TOTAL(V_TOTAL),
        .ACR_N(20'd4096), .ACR_CTS(20'd25000),
        .PIXEL_RATE(25000000), .AUDIO_RATE(32000),
        .EMIT_VGUARD(1),          // video guard band (obligatoire HDMI avec data islands)
        .ISLANDS(1),              // data islands (audio) + AVI/Audio InfoFrame + ACR
        .VBLANK_ONLY(0),          // son complet (le ghost venait de l'AVI manquant)
        .SW(SW)
    ) di (
        .clk(clk_pixel), .rst(rst),
        .hc(hc), .vc(vc), .hsync(hsync), .vsync(vsync), .de(de),
        .aud_l(aud_l), .aud_r(aud_r),
        .mode(mode), .aux0(aux0), .aux1(aux1), .aux2(aux2),
        .ctl0(ctl0), .ctl1(ctl1), .ctl2(ctl2)
    );

    // ------------------------------------------------------------------
    // Encodage TMDS HDMI (3 canaux)
    // ------------------------------------------------------------------
    wire [9:0] tmds_r, tmds_g, tmds_b;
    hdmi_tmds_channel #(.CN(0)) enc_b (
        .clk(clk_pixel), .mode(mode), .video_data(blu),
        .aux_data(aux0), .ctrl_data(ctl0), .tmds(tmds_b));
    hdmi_tmds_channel #(.CN(1)) enc_g (
        .clk(clk_pixel), .mode(mode), .video_data(grn),
        .aux_data(aux1), .ctrl_data(ctl1), .tmds(tmds_g));
    hdmi_tmds_channel #(.CN(2)) enc_r (
        .clk(clk_pixel), .mode(mode), .video_data(red),
        .aux_data(aux2), .ctrl_data(ctl2), .tmds(tmds_r));

`ifndef SIM
    // Sérialisation 10:1 : 2 bits par cycle 125 MHz (DDR), chargement aligné
    // en phase (cf. historique). clk_pixel échantillonné dans le domaine 125.
    reg [2:0] pix_sync;
    always @(posedge clk_shift) pix_sync <= {pix_sync[1:0], clk_pixel};
    wire load = pix_sync[1] & ~pix_sync[2];

    reg [9:0] sh_r, sh_g, sh_b, sh_c;
    always @(posedge clk_shift) begin
        if (load) begin
            sh_r <= tmds_r;
            sh_g <= tmds_g;
            sh_b <= tmds_b;
            sh_c <= 10'b0000011111;   // horloge pixel sur le canal clock
        end else begin
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
