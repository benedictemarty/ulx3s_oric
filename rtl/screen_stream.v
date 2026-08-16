// Streamer « écran déporté » : lit en boucle le framebuffer 240x224x4bits
// (port 2) et l'envoie par l'UART FTDI vers le PC, qui le rend en direct
// (tools/screen_gui.py). Couvre TOUS les modes vidéo (TEXT, HIRES, mixte)
// puisqu'on transporte le rendu final de la ULA, pas la RAM écran.
//
// INCRUSTATION OSD : l'OSD (liste des fichiers SD) est composité par l'étage
// HDMI, hors framebuffer -> invisible sur la console. On le recompose ici en
// coordonnées framebuffer : ov_x/ov_y = coordonnée du pixel courant vers une
// instance osd (top), ov_on/ov_col reviennent et remplacent le pixel.
//
// Trame : 4 octets d'en-tête (AA 55 F0 0F) puis 26880 octets = 53760 pixels
// empaquetés 2 par octet (nibble bas = pixel pair). Couleur = 3 bits.
//
// `enable` bas -> se tait et rend l'UART (dump/cassette prioritaires).

module screen_stream #(
    parameter PIXELS = 53760          // 240 * 224
) (
    input             clk,
    input             rst,
    input             enable,
    output reg [15:0] raddr,          // vers framebuffer.raddr2
    input      [3:0]  rdata,          // <- framebuffer.rdata2
    input             rd_valid,       // <- framebuffer.rd2_valid
    // Incrustation OSD (coordonnées framebuffer)
    output     [9:0]  ov_x,
    output     [9:0]  ov_y,
    input             ov_on,
    input      [2:0]  ov_col,
    // UART
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
    reg [9:0]  fx, fy;                // coordonnée du pixel PAIR courant
    reg [3:0]  lo;
    reg [7:0]  byte_q;

    assign active = (state != S_IDLE);
    // pixel finalisé : pair (fx) en S_RD0C, impair (fx+1) en S_RD1C
    assign ov_x = (state == S_RD1C) ? fx + 10'd1 : fx;
    assign ov_y = fy;
    wire [3:0] px_lo = ov_on ? {1'b0, ov_col} : (rdata & 4'h7);
    wire [3:0] px_hi = ov_on ? {1'b0, ov_col} : (rdata & 4'h7);

    wire       last = (idx + 17'd2 >= PIXELS);
    wire       wrap = (fx + 10'd2 >= 10'd240);

    always @(posedge clk) begin
        tx_send <= 1'b0;
        if (rst) begin
            state <= S_IDLE; idx <= 17'd0; hdr <= 2'd0; fx <= 10'd0; fy <= 10'd0;
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
                           if (hdr == 2'd3) begin
                               idx <= 17'd0; fx <= 10'd0; fy <= 10'd0;
                               state <= S_RD0;
                           end else hdr <= hdr + 2'd1;
                       end

                // Lecture des 2 pixels via le port partagé : capture sur
                // rd_valid ; l'OSD remplace le pixel quand ov_on.
                S_RD0:  begin raddr <= idx[15:0];          state <= S_RD0W; end
                S_RD0W:                                    state <= S_RD0C;
                S_RD0C: if (rd_valid) begin
                            lo <= px_lo;
                            raddr <= idx[15:0] + 16'd1;    state <= S_RD1W;
                        end
                S_RD1W:                                    state <= S_RD1C;
                S_RD1C: if (rd_valid) begin
                            byte_q <= {px_hi, lo};         state <= S_TX;
                        end

                S_TX:   if (!enable) state <= S_IDLE;
                        else if (!tx_busy && !tx_send) begin
                            tx_data <= byte_q; tx_send <= 1'b1;
                            if (last) begin
                                hdr <= 2'd0; state <= S_HDR;   // trame suivante
                            end else begin
                                idx <= idx + 17'd2;
                                fx  <= wrap ? 10'd0 : fx + 10'd2;
                                fy  <= wrap ? fy + 10'd1 : fy;
                                state <= S_RD0;
                            end
                        end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
