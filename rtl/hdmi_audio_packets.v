// Générateur de contenu des data island packets audio HDMI (Verilog-2005).
//
// Produit, selon `ptype`, le header (24 bits) et les 4 subpackets (56 bits)
// à fournir à hdmi_packet_assembler :
//   ptype 0 : Audio Clock Regeneration (ACR)  — type 0x01, N/CTS
//   ptype 1 : Audio InfoFrame                 — type 0x84
//   ptype 2 : Audio Sample Packet             — type 0x02, 1 à 4 échantillons
//
// Un Audio Sample Packet transporte jusqu'à 4 trames stéréo (créneaux 0..3),
// nécessaire ici car la cadence audio (32 kHz) dépasse la cadence ligne
// (31,25 kHz à 25 MHz / 800) : on regroupe plusieurs échantillons par packet.
//
// Layouts et positions de bits repris littéralement de la spec HDMI 1.4
// (référence hdl-util/hdmi). Channel status = 0 (LPCM consumer). SAMPLE_WIDTH
// bits d'échantillon cadrés MSB dans le champ 24 bits IEC60958.

module hdmi_audio_packets #(
    parameter [19:0] N   = 20'd4096,     // ACR : 4096 pour 32 kHz
    parameter [19:0] CTS = 20'd25000,    // ACR : 25000 à pixel clock 25 MHz
    parameter        SAMPLE_WIDTH = 16
) (
    input  [1:0]                    ptype,
    input  [3:0]                    present,   // créneaux portant un échantillon
    input  [3:0]                    frame0,    // bit B (début de bloc 192) / créneau
    input  [SAMPLE_WIDTH-1:0]       l0, l1, l2, l3,
    input  [SAMPLE_WIDTH-1:0]       r0, r1, r2, r3,
    output reg [23:0]               header,
    output reg [55:0]               sub0,
    output reg [55:0]               sub1,
    output reg [55:0]               sub2,
    output reg [55:0]               sub3
);

    // ---- ACR : contenu identique sur les 4 subpackets ----
    wire [55:0] acr_sub = {N[7:0], N[15:8], {4'd0, N[19:16]},
                           CTS[7:0], CTS[15:8], {4'd0, CTS[19:16]}, 8'd0};

    // ---- Audio InfoFrame : octets PB ----
    localparam [7:0] IF_HB0 = 8'h84, IF_HB1 = 8'h01, IF_HB2 = 8'h0A;
    localparam [7:0] IF_PB1 = 8'h01, IF_PB2 = 8'h00, IF_PB3 = 8'h00;
    localparam [7:0] IF_PB4 = 8'h00, IF_PB5 = 8'h00, IF_PB6 = 8'h00;
    wire [7:0] if_sum = IF_HB0 + IF_HB1 + IF_HB2 +
                        IF_PB1 + IF_PB2 + IF_PB3 + IF_PB4 + IF_PB5 + IF_PB6;
    wire [7:0] IF_PB0 = 8'd1 + ~if_sum;

    // ---- Audio Sample : un subpacket IEC60958 par créneau ----
    // Échantillon 24 bits (cadrage MSB), C=U=V=0, parité paire sur l'ensemble.
    wire [23:0] l24_0 = {l0, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] l24_1 = {l1, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] l24_2 = {l2, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] l24_3 = {l3, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] r24_0 = {r0, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] r24_1 = {r1, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] r24_2 = {r2, {(24 - SAMPLE_WIDTH){1'b0}}};
    wire [23:0] r24_3 = {r3, {(24 - SAMPLE_WIDTH){1'b0}}};

    // Preamble {P,C,U,V} avec C=U=V=0 -> P = parité de l'échantillon 24 bits
    wire [55:0] asp0 = {(^r24_0), 3'b000, (^l24_0), 3'b000, r24_0, l24_0};
    wire [55:0] asp1 = {(^r24_1), 3'b000, (^l24_1), 3'b000, r24_1, l24_1};
    wire [55:0] asp2 = {(^r24_2), 3'b000, (^l24_2), 3'b000, r24_2, l24_2};
    wire [55:0] asp3 = {(^r24_3), 3'b000, (^l24_3), 3'b000, r24_3, l24_3};

    // B field : début de bloc, uniquement sur les créneaux présents
    wire [3:0] bfield = frame0 & present;

    // ---- AVI InfoFrame (type 0x82) : décrit la vidéo (RGB, VIC=1 640x480) ----
    // Sans lui, l'écran passé en mode HDMI mésinterprète la vidéo (halo autour
    // des caractères). Y=RGB, colorimétrie par défaut, plage par défaut.
    localparam [7:0] AVI_HB0 = 8'h82, AVI_HB1 = 8'h02, AVI_HB2 = 8'h0D;
    // VIC=0 : format non-CEA — l'écran n'impose pas le timing 25,175 MHz de la
    // norme 640x480 (on génère 25,000 MHz) ; VIC=1 le faisait couper après ~30 s.
    // Pour réduire le traitement d'image de l'écran (halo autour des glyphes) :
    //   PB1 bit S=10 : underscan (affichage 1:1, pas d'overscan/rééchantillonnage)
    // (IT_CONTENT / full-range testés mais provoquaient un écran noir sur cet écran.)
    localparam [7:0] AVI_PB1 = 8'h02, AVI_PB2 = 8'h08, AVI_PB3 = 8'h00,
                     AVI_PB4 = 8'h00, AVI_PB5 = 8'h00, AVI_PB6 = 8'h00;
    wire [7:0] avi_sum = AVI_HB0 + AVI_HB1 + AVI_HB2 +
                         AVI_PB1 + AVI_PB2 + AVI_PB3 + AVI_PB4 + AVI_PB5 + AVI_PB6;
    wire [7:0] AVI_PB0 = 8'd1 + ~avi_sum;

    always @* begin
        case (ptype)
            2'd0: begin  // ACR (type 0x01)
                header = 24'h000001;
                sub0 = acr_sub; sub1 = acr_sub;
                sub2 = acr_sub; sub3 = acr_sub;
            end

            2'd1: begin  // Audio InfoFrame (type 0x84)
                header = {IF_HB2, IF_HB1, IF_HB0};
                sub0 = {IF_PB6, IF_PB5, IF_PB4, IF_PB3, IF_PB2, IF_PB1, IF_PB0};
                sub1 = 56'd0; sub2 = 56'd0; sub3 = 56'd0;
            end

            2'd3: begin  // AVI InfoFrame (type 0x82)
                header = {AVI_HB2, AVI_HB1, AVI_HB0};
                sub0 = {AVI_PB6, AVI_PB5, AVI_PB4, AVI_PB3, AVI_PB2, AVI_PB1, AVI_PB0};
                sub1 = 56'd0; sub2 = 56'd0; sub3 = 56'd0;
            end

            default: begin  // Audio Sample Packet (type 0x02)
                header = {bfield, 4'b0000, 4'b0000, present, 8'h02};
                sub0 = present[0] ? asp0 : 56'd0;
                sub1 = present[1] ? asp1 : 56'd0;
                sub2 = present[2] ? asp2 : 56'd0;
                sub3 = present[3] ? asp3 : 56'd0;
            end
        endcase
    end

endmodule
