// Émetteur UART 8N1 minimal (voie retour FPGA -> PC, US1).
// Sert à renvoyer les octets de crédit du contrôle de flux cassette.

module uart_tx #(
    parameter CLK_HZ = 25_000_000,
    parameter BAUD   = 115_200
)(
    input            clk,
    input            rst,
    input      [7:0] data,
    input            send,       // impulsion 1 cycle : émettre `data` si !busy
    output reg       tx,         // ligne série (repos = 1)
    output           busy
);

    localparam integer DIV = CLK_HZ / BAUD;

    localparam IDLE = 0, START = 1, BITS = 2, STOP = 3;
    reg [1:0]  state = IDLE;
    reg [15:0] baud_cnt = 0;
    reg [2:0]  bit_idx = 0;
    reg [7:0]  shreg = 0;

    assign busy = (state != IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            tx    <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    if (send) begin
                        shreg    <= data;
                        baud_cnt <= DIV - 1;
                        tx       <= 1'b0;      // start bit
                        state    <= START;
                    end
                end
                START: begin                   // maintien du start bit
                    if (baud_cnt == 0) begin
                        tx       <= shreg[0];  // data[0] (LSB)
                        shreg    <= {1'b0, shreg[7:1]};
                        bit_idx  <= 0;
                        baud_cnt <= DIV - 1;
                        state    <= BITS;
                    end else
                        baud_cnt <= baud_cnt - 16'd1;
                end
                BITS: begin
                    if (baud_cnt == 0) begin
                        baud_cnt <= DIV - 1;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;     // stop bit
                            state <= STOP;
                        end else begin
                            tx      <= shreg[0];   // data[1..7]
                            shreg   <= {1'b0, shreg[7:1]};
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else
                        baud_cnt <= baud_cnt - 16'd1;
                end
                STOP: begin                    // maintien du stop bit
                    if (baud_cnt == 0)
                        state <= IDLE;
                    else
                        baud_cnt <= baud_cnt - 16'd1;
                end
            endcase
        end
    end

endmodule
