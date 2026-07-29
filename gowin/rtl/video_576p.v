// Sortie vidéo 720x576p50 pour Tang Nano 20K — doubleur de lignes.
//
// Principe : à 27 MHz, une ligne HDMI 576p (864 cycles = 32 µs) vaut
// exactement une DEMI-ligne Oric (64 µs). Trame HDMI ramenée à 624 lignes
// (864 x 624 = 539 136 cycles) = trame Oric (312 x 64 µs x 27) : les deux
// balayages, remis à zéro ensemble, restent verrouillés pour toujours —
// aucun framebuffer, aucun tearing.
//
// La ULA écrit ses pixels (240/ligne) dans 4 tampons de ligne (ping-pong) ;
// la lecture HDMI double chaque ligne Oric (2x en largeur, 2x en hauteur),
// fenêtre 480x448 centrée dans 720x576.

module video_576p (
    input             clk,          // 27 MHz : pixel HDMI ET système Oric
    input             rst,

    // Écriture depuis la ULA (domaine unique)
    input             fb_we,
    input      [3:0]  fb_data,
    input      [8:0]  scan_y,       // 0..311 (visible 0..223)
    input      [5:0]  scan_x,       // cellule 0..39
    input      [15:0] fb_addr,      // y*240 + x (on n'utilise que x modulo)

    output reg [7:0]  red,
    output reg [7:0]  grn,
    output reg [7:0]  blu,
    output            de,
    output            hsync,
    output            vsync
);

    // ------------------------------------------------------------------
    // Timing 864 x 624 @ 27 MHz (~50,08 Hz, comme l'Oric)
    // ------------------------------------------------------------------
    localparam H_ACT = 720, H_FP = 12, H_SY = 64, H_TOT = 864;
    localparam V_ACT = 576, V_FP = 5,  V_SY = 5,  V_TOT = 624;
    localparam WIN_X = 120;   // (720-480)/2
    localparam WIN_Y = 64;    // (576-448)/2

    // Décalage initial du balayage HDMI : la ULA (remise à zéro au même
    // front) écrit sa ligne n pendant les lignes HDMI 2n/2n+1 ; en faisant
    // partir vc à WIN_Y-2, la lecture de la ligne n tombe une ligne Oric
    // APRÈS son écriture — le tampon 4 lignes suffit, verrouillé à jamais.
    localparam V_INIT = WIN_Y - 2;

    reg [9:0] hc;
    reg [9:0] vc;
    always @(posedge clk) begin
        if (rst) begin
            hc <= 0; vc <= V_INIT;
        end else if (hc == H_TOT - 1) begin
            hc <= 0;
            vc <= (vc == V_TOT - 1) ? 10'd0 : vc + 10'd1;
        end else
            hc <= hc + 10'd1;
    end

    assign de    = (hc < H_ACT) && (vc < V_ACT);
    assign hsync = ~((hc >= H_ACT + H_FP) && (hc < H_ACT + H_FP + H_SY));
    assign vsync = ~((vc >= V_ACT + V_FP) && (vc < V_ACT + V_FP + V_SY));

    // ------------------------------------------------------------------
    // Tampons de ligne : 4 x 256 nibbles (LUTRAM)
    // ------------------------------------------------------------------
    (* ram_style = "distributed" *) reg [3:0] lbuf [0:1023];

    // Écriture : position x dans la ligne reconstruite depuis fb_addr
    // (fb_addr = y*240 + x ; x = fb_addr - y*240)
    wire [15:0] line_base = {7'd0, scan_y} * 16'd240;
    wire [7:0]  wr_x = fb_addr - line_base;
    always @(posedge clk)
        if (fb_we)
            lbuf[{scan_y[1:0], wr_x}] <= fb_data;

    // Lecture : ligne Oric = (vc - WIN_Y)/2, une ligne DERRIÈRE l'écriture
    wire [9:0] win_v = vc - WIN_Y;
    wire [8:0] oric_y = {1'b0, win_v[9:1]};
    wire [1:0] rd_bank = oric_y[1:0];
    wire [9:0] win_h = hc - WIN_X;
    wire [7:0] rd_x = win_h[8:1];
    wire in_win = (hc >= WIN_X) && (hc < WIN_X + 480) &&
                  (vc >= WIN_Y) && (vc < WIN_Y + 448);

    reg [3:0] pix;
    reg       in_win_q;
    always @(posedge clk) begin
        pix <= lbuf[{rd_bank, rd_x}];
        in_win_q <= in_win;
    end

    always @* begin
        if (in_win_q) begin
            red = pix[0] ? 8'hFF : 8'h00;
            grn = pix[1] ? 8'hFF : 8'h00;
            blu = pix[2] ? 8'hFF : 8'h00;
        end else begin
            red = 8'h00; grn = 8'h00; blu = 8'h00;
        end
    end

endmodule
