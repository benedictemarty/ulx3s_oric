// Encodeur TMDS 8b/10b (DVI), un canal.

module tmds_encoder (
    input            clk,       // horloge pixel
    input      [7:0] data,
    input      [1:0] ctrl,      // {vsync, hsync} sur le canal bleu
    input            de,        // data enable
    output reg [9:0] tmds
);

    // Nombre de 1 dans l'octet
    wire [3:0] n1d = data[0] + data[1] + data[2] + data[3]
                   + data[4] + data[5] + data[6] + data[7];

    wire use_xnor = (n1d > 4'd4) || (n1d == 4'd4 && data[0] == 1'b0);

    wire [8:0] q_m;
    assign q_m[0] = data[0];
    assign q_m[1] = use_xnor ? ~(q_m[0] ^ data[1]) : (q_m[0] ^ data[1]);
    assign q_m[2] = use_xnor ? ~(q_m[1] ^ data[2]) : (q_m[1] ^ data[2]);
    assign q_m[3] = use_xnor ? ~(q_m[2] ^ data[3]) : (q_m[2] ^ data[3]);
    assign q_m[4] = use_xnor ? ~(q_m[3] ^ data[4]) : (q_m[3] ^ data[4]);
    assign q_m[5] = use_xnor ? ~(q_m[4] ^ data[5]) : (q_m[4] ^ data[5]);
    assign q_m[6] = use_xnor ? ~(q_m[5] ^ data[6]) : (q_m[5] ^ data[6]);
    assign q_m[7] = use_xnor ? ~(q_m[6] ^ data[7]) : (q_m[6] ^ data[7]);
    assign q_m[8] = ~use_xnor;

    wire [3:0] n1qm = q_m[0] + q_m[1] + q_m[2] + q_m[3]
                    + q_m[4] + q_m[5] + q_m[6] + q_m[7];
    wire [3:0] n0qm = 4'd8 - n1qm;

    reg signed [4:0] disparity;

    always @(posedge clk) begin
        if (!de) begin
            disparity <= 5'sd0;
            case (ctrl)
                2'b00: tmds <= 10'b1101010100;
                2'b01: tmds <= 10'b0010101011;
                2'b10: tmds <= 10'b0101010100;
                2'b11: tmds <= 10'b1010101011;
            endcase
        end else begin
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
    end

endmodule
