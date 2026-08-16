// Streamer « écran déporté » : lit en boucle le framebuffer 240x224x4bits
// (port 2) et l'envoie par l'UART FTDI vers le PC, qui le rend en direct
// (tools/screen_view.py). Couvre TOUS les modes vidéo (TEXT, HIRES, mixte)
// puisqu'on transporte le rendu final de la ULA, pas la RAM écran.
//
// Trame : 4 octets d'en-tête (AA 55 F0 0F) puis 26880 octets = 53760 pixels
// empaquetés 2 par octet (nibble bas = pixel pair, nibble haut = pixel
// impair). Couleur = 3 bits (b0=R b1=G b2=B), b3 inutilisé. Puis reboucle.
//
// `enable` bas -> se tait et rend l'UART (dump/cassette prioritaires).
// Latence BRAM = 2 cycles : états d'attente RDxw/RDxc après pose de raddr2.

module screen_stream #(
    parameter PIXELS = 53760          // 240 * 224
) (
    input             clk,
    input             rst,
    input             enable,
    output reg [15:0] raddr,          // vers framebuffer.raddr2
    input      [3:0]  rdata,          // <- framebuffer.rdata2
    input             rd_valid,       // <- framebuffer.rd2_valid (lecture propre)
    output reg [7:0]  tx_data,
    output reg        tx_send,
    input             tx_busy,
    output            active
);
    localparam S_IDLE=0, S_HDR=1,
               S_RD0=2, S_RD0W=3, S_RD0C=4,
               S_RD1W=5, S_RD1C=6, S_TX=7;
    reg [2:0]  state;
    reg [1:0]  hdr;
    reg [16:0] idx;
    reg [3:0]  lo;
    reg [7:0]  byte_q;

    assign active = (state != S_IDLE);

    always @(posedge clk) begin
        tx_send <= 1'b0;
        if (rst) begin
            state <= S_IDLE; idx <= 17'd0; hdr <= 2'd0;
        end else begin
            case (state)
                S_IDLE: if (enable) begin hdr <= 2'd0; state <= S_HDR; end

                S_HDR: if (!enable) state <= S_IDLE;
                       else if (!tx_busy && !tx_send) begin
                           case (hdr)
                               2'd0: tx_data <= 8'hAA;
                               2'd1: tx_data <= 8'h55;
                               2'd2: tx_data <= 8'hF0;
                               2'd3: tx_data <= 8'h0F;
                           endcase
                           tx_send <= 1'b1;
                           if (hdr == 2'd3) begin idx <= 17'd0; state <= S_RD0; end
                           else hdr <= hdr + 2'd1;
                       end

                // Lecture des 2 pixels via le port partagé : on ne capture
                // que sur un cycle rd_valid (la ULA n'écrivait pas). S_RDxC
                // « spinne » tant que rd_valid est bas (raddr2 reste stable).
                S_RD0:  begin raddr <= idx[15:0];          state <= S_RD0W; end
                S_RD0W:                                    state <= S_RD0C;
                S_RD0C: if (rd_valid) begin
                            lo <= rdata;
                            raddr <= idx[15:0] + 16'd1;    state <= S_RD1W;
                        end
                S_RD1W:                                    state <= S_RD1C;
                S_RD1C: if (rd_valid) begin
                            byte_q <= {rdata, lo};         state <= S_TX;
                        end

                S_TX:   if (!enable) state <= S_IDLE;
                        else if (!tx_busy && !tx_send) begin
                            tx_data <= byte_q; tx_send <= 1'b1;
                            if (idx + 17'd2 >= PIXELS) begin
                                hdr <= 2'd0; state <= S_HDR;   // trame suivante
                            end else begin
                                idx <= idx + 17'd2; state <= S_RD0;
                            end
                        end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
