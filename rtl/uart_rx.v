// Récepteur UART 8N1 minimal (échantillonnage au milieu du bit).

module uart_rx #(
    parameter CLK_HZ = 25_000_000,
    parameter BAUD   = 115_200
)(
    input            clk,
    input            rst,
    input            rx,
    output reg [7:0] data,
    output reg       valid      // impulsion 1 cycle par octet reçu
);

    localparam integer DIV = CLK_HZ / BAUD;

    reg [1:0]  rx_sync = 2'b11;
    always @(posedge clk) rx_sync <= {rx_sync[0], rx};
    wire rxs = rx_sync[1];

    localparam IDLE = 0, START = 1, BITS = 2, STOP = 3;
    reg [1:0]  state = IDLE;
    reg [15:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        valid <= 1'b0;
        if (rst) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: if (!rxs) begin
                    state <= START;
                    baud_cnt <= DIV / 2;
                end
                START: begin
                    if (baud_cnt == 0) begin
                        if (!rxs) begin        // start bit confirmé
                            state <= BITS;
                            baud_cnt <= DIV - 1;
                            bit_idx <= 0;
                        end else
                            state <= IDLE;
                    end else
                        baud_cnt <= baud_cnt - 16'd1;
                end
                BITS: begin
                    if (baud_cnt == 0) begin
                        shreg <= {rxs, shreg[7:1]};
                        baud_cnt <= DIV - 1;
                        if (bit_idx == 3'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 3'd1;
                    end else
                        baud_cnt <= baud_cnt - 16'd1;
                end
                STOP: begin
                    if (baud_cnt == 0) begin
                        if (rxs) begin         // stop bit valide
                            data  <= shreg;
                            valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else
                        baud_cnt <= baud_cnt - 16'd1;
                end
            endcase
        end
    end

endmodule
