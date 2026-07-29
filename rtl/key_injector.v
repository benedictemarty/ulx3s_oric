// Injection clavier depuis l'UART : chaque caractère ASCII reçu est traduit
// en position de la matrice Oric (table dérivée de char_map de la référence
// ~/Oric1/src/io/keyboard.c, elle-même issue des tables ROM $FF70/$FFB0) puis
// « pressé » PRESS_TICKS cycles et relâché GAP_TICKS cycles, comme une vraie
// frappe. FIFO 256 octets pour permettre le collage de listings (limiter le
// débit côté PC, ex. `pv -qL 10`, l'Oric absorbe ~14 caractères/s).

module key_injector #(
    parameter PRESS_TICKS = 1_125_000,   // ~45 ms a 25 MHz
    parameter GAP_TICKS   = 625_000      // ~25 ms
)(
    input        clk,
    input        rst,
    input  [7:0] rx_data,
    input        rx_valid,
    output       inj_active,
    output [2:0] inj_col,
    output [2:0] inj_row,
    output       inj_shift
);

    // ASCII -> {valide, shift, col[2:0], row[2:0]}
    function [7:0] map_char;
        input [7:0] c;
        begin
            casez (c)
                8'h0D, 8'h0A: map_char = {2'b10, 3'd7, 3'd5}; // CR/LF -> RETURN
                8'h1B: map_char = {2'b10, 3'd1, 3'd5};        // ESC
                8'h08, 8'h7F: map_char = {2'b10, 3'd5, 3'd5}; // BS/DEL -> DEL
                8'h20: map_char = {2'b10, 3'd4, 3'd0};        // espace
                8'h21: map_char = {2'b11, 3'd0, 3'd5};        // ! = Shift+1
                8'h22: map_char = {2'b11, 3'd3, 3'd7};        // " = Shift+'
                8'h23: map_char = {2'b11, 3'd0, 3'd7};        // # = Shift+3
                8'h24: map_char = {2'b11, 3'd2, 3'd3};        // $ = Shift+4
                8'h25: map_char = {2'b11, 3'd0, 3'd2};        // % = Shift+5
                8'h26: map_char = {2'b11, 3'd0, 3'd0};        // & = Shift+7
                8'h27: map_char = {2'b10, 3'd3, 3'd7};        // '
                8'h28: map_char = {2'b11, 3'd3, 3'd1};        // ( = Shift+9
                8'h29: map_char = {2'b11, 3'd7, 3'd2};        // ) = Shift+0
                8'h2A: map_char = {2'b11, 3'd7, 3'd0};        // * = Shift+8
                8'h2B: map_char = {2'b11, 3'd7, 3'd7};        // + = Shift+=
                8'h2C: map_char = {2'b10, 3'd4, 3'd1};        // ,
                8'h2D: map_char = {2'b10, 3'd3, 3'd3};        // -
                8'h2E: map_char = {2'b10, 3'd4, 3'd2};        // .
                8'h2F: map_char = {2'b10, 3'd7, 3'd3};        // /
                8'h30: map_char = {2'b10, 3'd7, 3'd2};        // 0
                8'h31: map_char = {2'b10, 3'd0, 3'd5};        // 1
                8'h32: map_char = {2'b10, 3'd2, 3'd6};        // 2
                8'h33: map_char = {2'b10, 3'd0, 3'd7};        // 3
                8'h34: map_char = {2'b10, 3'd2, 3'd3};        // 4
                8'h35: map_char = {2'b10, 3'd0, 3'd2};        // 5
                8'h36: map_char = {2'b10, 3'd2, 3'd1};        // 6
                8'h37: map_char = {2'b10, 3'd0, 3'd0};        // 7
                8'h38: map_char = {2'b10, 3'd7, 3'd0};        // 8
                8'h39: map_char = {2'b10, 3'd3, 3'd1};        // 9
                8'h3A: map_char = {2'b11, 3'd3, 3'd2};        // : = Shift+;
                8'h3B: map_char = {2'b10, 3'd3, 3'd2};        // ;
                8'h3C: map_char = {2'b11, 3'd4, 3'd1};        // < = Shift+,
                8'h3D: map_char = {2'b10, 3'd7, 3'd7};        // =
                8'h3E: map_char = {2'b11, 3'd4, 3'd2};        // > = Shift+.
                8'h3F: map_char = {2'b11, 3'd7, 3'd3};        // ? = Shift+/
                8'h40: map_char = {2'b11, 3'd2, 3'd6};        // @ = Shift+2
                8'h41, 8'h61: map_char = {2'b10, 3'd6, 3'd5}; // A
                8'h42, 8'h62: map_char = {2'b10, 3'd2, 3'd2}; // B
                8'h43, 8'h63: map_char = {2'b10, 3'd2, 3'd7}; // C
                8'h44, 8'h64: map_char = {2'b10, 3'd1, 3'd7}; // D
                8'h45, 8'h65: map_char = {2'b10, 3'd6, 3'd3}; // E
                8'h46, 8'h66: map_char = {2'b10, 3'd1, 3'd3}; // F
                8'h47, 8'h67: map_char = {2'b10, 3'd6, 3'd2}; // G
                8'h48, 8'h68: map_char = {2'b10, 3'd6, 3'd1}; // H
                8'h49, 8'h69: map_char = {2'b10, 3'd5, 3'd1}; // I
                8'h4A, 8'h6A: map_char = {2'b10, 3'd1, 3'd0}; // J
                8'h4B, 8'h6B: map_char = {2'b10, 3'd3, 3'd0}; // K
                8'h4C, 8'h6C: map_char = {2'b10, 3'd7, 3'd1}; // L
                8'h4D, 8'h6D: map_char = {2'b10, 3'd2, 3'd0}; // M
                8'h4E, 8'h6E: map_char = {2'b10, 3'd0, 3'd1}; // N
                8'h4F, 8'h6F: map_char = {2'b10, 3'd5, 3'd2}; // O
                8'h50, 8'h70: map_char = {2'b10, 3'd5, 3'd3}; // P
                8'h51, 8'h71: map_char = {2'b10, 3'd1, 3'd6}; // Q
                8'h52, 8'h72: map_char = {2'b10, 3'd1, 3'd2}; // R
                8'h53, 8'h73: map_char = {2'b10, 3'd6, 3'd6}; // S
                8'h54, 8'h74: map_char = {2'b10, 3'd1, 3'd1}; // T
                8'h55, 8'h75: map_char = {2'b10, 3'd5, 3'd0}; // U
                8'h56, 8'h76: map_char = {2'b10, 3'd0, 3'd3}; // V
                8'h57, 8'h77: map_char = {2'b10, 3'd6, 3'd7}; // W
                8'h58, 8'h78: map_char = {2'b10, 3'd0, 3'd6}; // X
                8'h59, 8'h79: map_char = {2'b10, 3'd6, 3'd0}; // Y
                8'h5A, 8'h7A: map_char = {2'b10, 3'd2, 3'd5}; // Z
                8'h5B: map_char = {2'b10, 3'd5, 3'd7};        // [
                8'h5C: map_char = {2'b10, 3'd3, 3'd6};        // backslash
                8'h5D: map_char = {2'b10, 3'd5, 3'd6};        // ]
                8'h5E: map_char = {2'b11, 3'd2, 3'd1};        // ^ = Shift+6
                8'h5F: map_char = {2'b11, 3'd3, 3'd3};        // _ = Shift+-
                8'h7B: map_char = {2'b11, 3'd5, 3'd7};        // { = Shift+[
                8'h7C: map_char = {2'b11, 3'd3, 3'd6};        // | = Shift+backslash
                8'h7D: map_char = {2'b11, 3'd5, 3'd6};        // } = Shift+]
                default: map_char = 8'h00;                    // non mappé
            endcase
        end
    endfunction

    // FIFO 256 octets
    reg [7:0] fifo [0:255];
    reg [7:0] wptr, rptr;
    wire empty = (wptr == rptr);
    wire full  = (wptr + 8'd1 == rptr);

    always @(posedge clk) begin
        if (rst)
            wptr <= 0;
        else if (rx_valid && !full) begin
            fifo[wptr] <= rx_data;
            wptr <= wptr + 8'd1;
        end
    end

    // FSM presse/relâche
    localparam IDLE = 0, PRESS = 1, GAP = 2;
    reg [1:0]  state;
    reg [20:0] timer;
    reg [7:0]  cur, last_char;
    wire [7:0] m = map_char(cur);

    wire [7:0] head   = fifo[rptr];
    wire [7:0] m_head = map_char(head);

    always @(posedge clk) begin
        if (rst) begin
            rptr <= 0; state <= IDLE; last_char <= 0; cur <= 0;
        end else begin
            case (state)
                IDLE: if (!empty) begin
                    cur  <= head;
                    rptr <= rptr + 8'd1;
                    // LF juste après CR : c'est le même retour ligne, on saute
                    if (head == 8'h0A && last_char == 8'h0D)
                        state <= IDLE;
                    else if (m_head[7]) begin
                        state <= PRESS;
                        timer <= PRESS_TICKS[20:0];
                    end
                    last_char <= head;
                end
                PRESS: begin
                    if (timer == 0) begin
                        state <= GAP;
                        timer <= GAP_TICKS[20:0];
                    end else
                        timer <= timer - 21'd1;
                end
                GAP: begin
                    if (timer == 0)
                        state <= IDLE;
                    else
                        timer <= timer - 21'd1;
                end
                default: state <= IDLE;
            endcase
        end
    end

    assign inj_active = (state == PRESS) && m[7];
    assign inj_shift  = (state == PRESS) && m[6];
    assign inj_col    = m[5:3];
    assign inj_row    = m[2:0];

endmodule
