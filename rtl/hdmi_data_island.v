// Ordonnanceur de data islands HDMI (Verilog-2005).
//
// À partir de la position (hc, vc) et des syncs, produit pour chaque pixel :
//   - le mode d'encodage (voir hdmi_tmds_channel : 0 ctrl,1 video,2 vguard,
//     3 island,4 dguard) ;
//   - les 3 nibbles TERC4 (aux0/1/2) et les 3 données de contrôle (ctl0/1/2).
//
// Il place UN data island par ligne dans le blanking horizontal, encadré de son
// preamble et de ses guard bands, plus le video preamble + guard band avant la
// reprise de la vidéo active. Ordonnancement par ligne :
//   vc==0 : Audio InfoFrame   vc==1 : Audio Clock Regeneration
//   autres : Audio Sample Packet (si des échantillons sont en attente)
//
// Cadence audio : accumulateur rationnel exact (AUDIO_RATE ticks par seconde
// pour PIXEL_RATE pixels/s) — 32 kHz sans dérive, cohérent avec N/CTS. Comme la
// cadence ligne (31,25 kHz) est inférieure à 32 kHz, jusqu'à 4 échantillons
// sont groupés par packet. Les échantillons en attente prennent la valeur
// audio courante (maintien d'ordre 0, inaudible pour le PSG). Channel status
// et bit B laissés à 0 (LPCM consumer, largement accepté).

module hdmi_data_island #(
    parameter        H_ACTIVE   = 640,
    parameter        H_TOTAL    = 800,
    parameter        V_ACTIVE   = 480,
    parameter        V_TOTAL    = 525,
    parameter [19:0] ACR_N      = 20'd4096,
    parameter [19:0] ACR_CTS    = 20'd25000,
    parameter        PIXEL_RATE = 25000000,
    parameter        AUDIO_RATE = 32000,
    parameter        EMIT_VGUARD = 1,     // 1 : émet video preamble+guard band
    parameter        ISLANDS     = 1,     // 1 : émet les data islands (audio)
    parameter        VBLANK_ONLY = 0,     // 1 : data islands seulement hors zone active
    parameter        EMIT_AVI    = 1,     // 1 : émet l'AVI InfoFrame (description vidéo)
    parameter        SW         = 16
) (
    input             clk,
    input             rst,
    input      [9:0]  hc,
    input      [9:0]  vc,
    input             hsync,      // actif bas (comme hdmi_out)
    input             vsync,
    input             de,         // vidéo active
    input      [SW-1:0] aud_l,    // échantillon courant (domaine pixel)
    input      [SW-1:0] aud_r,
    output reg [2:0]  mode,
    output reg [3:0]  aux0,
    output reg [3:0]  aux1,
    output reg [3:0]  aux2,
    output reg [1:0]  ctl0,
    output reg [1:0]  ctl1,
    output reg [1:0]  ctl2
);

    // Découpage de la ligne (positions hc). Le data island est placé tôt dans le
    // blanking horizontal (front porch/début sync) : tout le reste du blanking
    // (>110 px) sert de control period avant la reprise vidéo — indispensable
    // pour que le récepteur se recale (le placer trop tard, dans le back porch,
    // laisse trop peu de control => perte de signal). Avec VBLANK_ONLY, ce data
    // island ne tombe que sur des lignes non affichées : sa position hc est sans
    // impact visuel.
    localparam DI_PRE = H_ACTIVE + 4;     // 644 : preamble data island (8 px)
    localparam DI_LG  = DI_PRE + 8;       // 652 : leading guard (2 px)
    localparam DI_ISL = DI_LG + 2;        // 654 : data island (32 px)
    localparam DI_TG  = DI_ISL + 32;      // 686 : trailing guard (2 px)
    localparam DI_END = DI_TG + 2;        // 688

    // Lignes portant les packets de service (InfoFrame, ACR). En mode
    // VBLANK_ONLY elles sont dans le blanking vertical, sinon en tête de trame.
    localparam LINE_IF  = (VBLANK_ONLY != 0) ? V_ACTIVE     : 0;
    localparam LINE_ACR = (VBLANK_ONLY != 0) ? V_ACTIVE + 1 : 1;
    localparam LINE_AVI = (VBLANK_ONLY != 0) ? V_ACTIVE + 2 : 2;
    localparam VP     = H_TOTAL - 10;     // 790 : video preamble (8 px)
    localparam VG     = H_TOTAL - 2;      // 798 : video guard band (2 px)

    // ------------------------------------------------------------------
    // Cadence audio : accumulateur rationnel exact
    // ------------------------------------------------------------------
    reg  [24:0] acc;
    wire [25:0] nacc = acc + AUDIO_RATE[24:0];
    wire        tick = (nacc >= PIXEL_RATE);
    always @(posedge clk)
        if (rst) acc <= 25'd0;
        else     acc <= tick ? (nacc - PIXEL_RATE) : nacc[24:0];

    // Échantillons en attente (saturé à 4)
    reg [2:0] pending;

    // ------------------------------------------------------------------
    // Sélection et latch du packet, une fois par ligne (à hc == DI_PRE-1)
    // ------------------------------------------------------------------
    reg [1:0]    ptype_line;
    reg          pkt_active;
    reg [3:0]    present_line;
    reg [SW-1:0] s_l, s_r;         // valeur audio maintenue pour ce packet

    wire        latch = (hc == (DI_PRE - 1));
    wire [2:0]  k = (pending > 3'd4) ? 3'd4 : pending;   // <= 4
    wire [3:0]  kmask = (k == 3'd0) ? 4'b0000 :
                        (k == 3'd1) ? 4'b0001 :
                        (k == 3'd2) ? 4'b0011 :
                        (k == 3'd3) ? 4'b0111 : 4'b1111;

    always @(posedge clk) begin
        if (rst) begin
            pending <= 3'd0; pkt_active <= 1'b0; ptype_line <= 2'd0;
            present_line <= 4'd0; s_l <= 0; s_r <= 0;
        end else begin
            // Accumulation des échantillons
            if (latch) begin
                // Décision de ligne (en VBLANK_ONLY, rien sur les lignes actives)
                if ((VBLANK_ONLY != 0) && (vc < V_ACTIVE)) begin
                    pkt_active <= 1'b0;
                    if (tick && pending < 3'd4) pending <= pending + 3'd1;
                end else if (vc == LINE_IF) begin
                    ptype_line <= 2'd1; pkt_active <= 1'b1;      // InfoFrame
                    if (tick && pending < 3'd4) pending <= pending + 3'd1;
                end else if (vc == LINE_ACR) begin
                    ptype_line <= 2'd0; pkt_active <= 1'b1;      // ACR
                    if (tick && pending < 3'd4) pending <= pending + 3'd1;
                end else if ((EMIT_AVI != 0) && (vc == LINE_AVI)) begin
                    ptype_line <= 2'd3; pkt_active <= 1'b1;      // AVI InfoFrame
                    if (tick && pending < 3'd4) pending <= pending + 3'd1;
                end else if (k != 3'd0) begin
                    ptype_line   <= 2'd2;                        // Audio Sample
                    pkt_active   <= 1'b1;
                    present_line <= kmask;
                    s_l <= aud_l; s_r <= aud_r;
                    pending <= tick ? 3'd1 : 3'd0;              // vidé (+ tick concomitant)
                end else begin
                    pkt_active <= 1'b0;
                    if (tick && pending < 3'd4) pending <= pending + 3'd1;
                end
            end else if (tick && pending < 3'd4) begin
                pending <= pending + 3'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Contenu du packet -> packet_data (combinatoire)
    // ------------------------------------------------------------------
    wire [23:0] header;
    wire [55:0] sub0, sub1, sub2, sub3;

    hdmi_audio_packets #(.N(ACR_N), .CTS(ACR_CTS), .SAMPLE_WIDTH(SW)) pk (
        .ptype(ptype_line), .present(present_line), .frame0(4'b0000),
        .l0(s_l), .l1(s_l), .l2(s_l), .l3(s_l),
        .r0(s_r), .r1(s_r), .r2(s_r), .r3(s_r),
        .header(header), .sub0(sub0), .sub1(sub1), .sub2(sub2), .sub3(sub3)
    );

    wire [4:0]  di_ctr = hc[4:0] - DI_ISL[4:0];   // 0..31 dans la fenêtre island
    wire [8:0]  packet_data;
    hdmi_packet_assembler asm (
        .header(header), .sub0(sub0), .sub1(sub1), .sub2(sub2), .sub3(sub3),
        .counter(di_ctr), .packet_data(packet_data)
    );

    // ------------------------------------------------------------------
    // Décodage de position -> mode / aux / ctl (combinatoire)
    // ------------------------------------------------------------------
    wire pkt_en = pkt_active && (ISLANDS != 0);
    wire in_pre = pkt_en && (hc >= DI_PRE) && (hc < DI_LG);
    wire in_lg  = pkt_en && (hc >= DI_LG)  && (hc < DI_ISL);
    wire in_isl = pkt_en && (hc >= DI_ISL) && (hc < DI_TG);
    wire in_tg  = pkt_en && (hc >= DI_TG)  && (hc < DI_END);

    // Video preamble/guard : uniquement si la ligne suivante est active
    wire next_line_active = (vc < (V_ACTIVE - 1)) || (vc == (V_TOTAL - 1));
    wire in_vp = (EMIT_VGUARD != 0) && next_line_active && (hc >= VP) && (hc < VG);
    wire in_vg = (EMIT_VGUARD != 0) && next_line_active && (hc >= VG) && (hc < H_TOTAL);

    always @* begin
        ctl0 = {vsync, hsync};
        ctl1 = 2'b00;
        ctl2 = 2'b00;
        aux0 = 4'b0000; aux1 = 4'b0000; aux2 = 4'b0000;

        if (de) begin
            mode = 3'd1;                       // vidéo
        end else if (in_isl) begin
            mode = 3'd3;                       // data island
            aux0 = {(di_ctr != 5'd0), packet_data[0], vsync, hsync};
            aux1 = packet_data[4:1];
            aux2 = packet_data[8:5];
        end else if (in_lg || in_tg) begin
            mode = 3'd4;                       // data island guard band
        end else if (in_isl == 1'b0 && in_pre) begin
            mode = 3'd0;                       // data island preamble
            ctl1 = 2'b01; ctl2 = 2'b01;
        end else if (in_vg) begin
            mode = 3'd2;                       // video guard band
        end else if (in_vp) begin
            mode = 3'd0;                       // video preamble
            ctl1 = 2'b01; ctl2 = 2'b00;
        end else begin
            mode = 3'd0;                       // control period normal
        end
    end

endmodule
