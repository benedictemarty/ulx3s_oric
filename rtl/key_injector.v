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

    // ASCII -> {valide, shift, col[2:0], row[2:0]} — table partagée
    `include "ascii2oric.vh"

    // FIFO 256 octets
    (* ram_style = "distributed" *) reg [7:0] fifo [0:255];
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
