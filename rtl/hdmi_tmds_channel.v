// Encodeur d'un canal TMDS HDMI (Verilog-2005).
//
// Étend l'encodeur DVI 8b/10b (rtl/tmds_encoder.v) avec les périodes propres
// au HDMI, nécessaires pour transporter l'audio dans les data islands :
//   mode 0 : control period      (préambules + blanking)
//   mode 1 : video data          (8b/10b, identique au DVI existant)
//   mode 2 : video guard band
//   mode 3 : data island         (TERC4)
//   mode 4 : data island guard band
//
// Les constantes (table TERC4, codes de guard band, codes de contrôle)
// proviennent de la spec HDMI 1.4 (référence hdl-util/hdmi), réécrites ici
// en Verilog-2005. Un seul bit erroné casse le lien : elles sont vérifiées.
//
// CN = numéro de canal : 0 = bleu (B), 1 = vert (G), 2 = rouge (R).
// En mode vidéo la logique 8b/10b et la disparité sont strictement celles de
// tmds_encoder.v (garantie de non-régression de l'image).

module hdmi_tmds_channel #(
    parameter CN = 0
) (
    input            clk,
    input      [2:0] mode,        // 0=ctrl 1=video 2=vguard 3=island 4=dguard
    input      [7:0] video_data,  // octet pixel (mode video)
    input      [3:0] aux_data,    // nibble TERC4 (mode data island)
    input      [1:0] ctrl_data,   // {vsync,hsync} / control / guard band ch0
    output reg [9:0] tmds
);

    // ------------------------------------------------------------------
    // TERC4 : 4 bits -> 10 bits (spec HDMI 1.4, table complète)
    // ------------------------------------------------------------------
    function [9:0] terc4;
        input [3:0] d;
        case (d)
            4'h0: terc4 = 10'b1010011100;
            4'h1: terc4 = 10'b1001100011;
            4'h2: terc4 = 10'b1011100100;
            4'h3: terc4 = 10'b1011100010;
            4'h4: terc4 = 10'b0101110001;
            4'h5: terc4 = 10'b0100011110;
            4'h6: terc4 = 10'b0110001110;
            4'h7: terc4 = 10'b0100111100;
            4'h8: terc4 = 10'b1011001100;
            4'h9: terc4 = 10'b0100111001;
            4'hA: terc4 = 10'b0110011100;
            4'hB: terc4 = 10'b1011000110;
            4'hC: terc4 = 10'b1010001110;
            4'hD: terc4 = 10'b1001110001;
            4'hE: terc4 = 10'b0101100011;
            4'hF: terc4 = 10'b1011000011;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // 8b/10b vidéo (copie fidèle de tmds_encoder.v)
    // ------------------------------------------------------------------
    wire [3:0] n1d = video_data[0] + video_data[1] + video_data[2] + video_data[3]
                   + video_data[4] + video_data[5] + video_data[6] + video_data[7];

    wire use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && video_data[0] == 1'b0);

    wire [8:0] q_m;
    assign q_m[0] = video_data[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ video_data[1]) : (q_m[0] ^ video_data[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ video_data[2]) : (q_m[1] ^ video_data[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ video_data[3]) : (q_m[2] ^ video_data[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ video_data[4]) : (q_m[3] ^ video_data[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ video_data[5]) : (q_m[4] ^ video_data[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ video_data[6]) : (q_m[5] ^ video_data[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ video_data[7]) : (q_m[6] ^ video_data[7]);
    assign q_m[8] = ~use_xnor;

    wire [3:0] n1qm = q_m[0] + q_m[1] + q_m[2] + q_m[3]
                    + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire [3:0] n0qm = 4'd8 - n1qm;

    reg signed [4:0] disparity;

    always @(posedge clk) begin
        case (mode)
            // ---- mode 1 : vidéo 8b/10b (disparité maintenue) ----
            3'd1: begin
                if (disparity == 0 || n1qm == n0qm) begin
                    tmds <= {~q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
                    if (q_m[8] == 1'b0)
                        disparity <= disparity + $signed({1'b0, n0qm}) - $signed({1'b0, n1qm});
                    else
                        disparity <= disparity + $signed({1'b0, n1qm}) - $signed({1'b0, n0qm});
                end else if ((disparity > 0 && n1qm > n0qm) ||
                             (disparity < 0 && n0qm > n1qm)) begin
                    tmds <= {1'b1, q_m[8], ~q_m[7:0]};
                    disparity <= disparity + {3'd0, q_m[8], 1'b0}
                                 + $signed({1'b0, n0qm}) - $signed({1'b0, n1qm});
                end else begin
                    tmds <= {1'b0, q_m[8], q_m[7:0]};
                    disparity <= disparity - {3'd0, ~q_m[8], 1'b0}
                                 + $signed({1'b0, n1qm}) - $signed({1'b0, n0qm});
                end
            end

            // ---- mode 2 : video guard band ----
            3'd2: begin
                tmds <= (CN == 1) ? 10'b0100110011 : 10'b1011001100;
                disparity <= 5'sd0;
            end

            // ---- mode 3 : data island (TERC4) ----
            3'd3: begin
                tmds <= terc4(aux_data);
                disparity <= 5'sd0;
            end

            // ---- mode 4 : data island guard band ----
            // Canaux 1,2 : code fixe. Canal 0 : TERC4 de {1,1,vsync,hsync}.
            3'd4: begin
                tmds <= (CN == 0) ? terc4({2'b11, ctrl_data}) : 10'b0100110011;
                disparity <= 5'sd0;
            end

            // ---- mode 0 : control period ----
            default: begin
                case (ctrl_data)
                    2'b00: tmds <= 10'b1101010100;
                    2'b01: tmds <= 10'b0010101011;
                    2'b10: tmds <= 10'b0101010100;
                    2'b11: tmds <= 10'b1010101011;
                endcase
                disparity <= 5'sd0;
            end
        endcase
    end

endmodule
