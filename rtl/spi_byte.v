// Moteur SPI mode 0 (CPOL=0, CPHA=0), transfert d'un octet full-duplex, MSB
// d'abord. Brique de base du pilote carte SD (rtl/sd_spi.v).
//
// Mode 0 : sck au repos bas ; MOSI présenté pendant sck bas, MISO échantillonné
// au front montant de sck. HALF = nombre de cycles `clk` par demi-période sck
// (période sck = 2*HALF). Pour l'init SD (<=400 kHz) à 25 MHz : HALF≈32.

module spi_byte #(
    parameter HALF = 32
) (
    input            clk,
    input            rst,
    input            start,      // pulse : lancer le transfert de `tx`
    input      [7:0] tx,         // octet à émettre
    output reg [7:0] rx,         // octet reçu (valide au pulse `done`)
    output reg       busy,
    output reg       done,       // pulse 1 cycle en fin de transfert
    output reg       sck,
    output reg       mosi,
    input            miso
);

    localparam ST_IDLE = 2'd0, ST_LOW = 2'd1, ST_HIGH = 2'd2;

    reg [1:0]  st;
    reg [3:0]  bitc;             // 0..7
    reg [15:0] cnt;              // compteur de demi-période
    reg [7:0]  sh_tx, sh_rx;

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            st <= ST_IDLE; sck <= 1'b0; mosi <= 1'b1; busy <= 1'b0;
            cnt <= 16'd0; bitc <= 4'd0;
        end else begin
            case (st)
                ST_IDLE: begin
                    sck <= 1'b0;
                    if (start) begin
                        sh_tx <= tx; sh_rx <= 8'd0;
                        mosi  <= tx[7];
                        bitc  <= 4'd0; cnt <= 16'd0;
                        busy  <= 1'b1; st <= ST_LOW;
                    end
                end

                // sck bas : MOSI stable (bit courant)
                ST_LOW: begin
                    sck  <= 1'b0;
                    mosi <= sh_tx[7];
                    if (cnt == HALF - 1) begin
                        cnt   <= 16'd0;
                        sh_rx <= {sh_rx[6:0], miso};   // échantillon au front montant
                        sck   <= 1'b1;
                        st    <= ST_HIGH;
                    end else
                        cnt <= cnt + 16'd1;
                end

                // sck haut
                ST_HIGH: begin
                    if (cnt == HALF - 1) begin
                        cnt <= 16'd0;
                        sck <= 1'b0;
                        if (bitc == 4'd7) begin
                            rx    <= sh_rx;
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            st    <= ST_IDLE;
                        end else begin
                            bitc  <= bitc + 4'd1;
                            sh_tx <= {sh_tx[6:0], 1'b0};
                            st    <= ST_LOW;
                        end
                    end else
                        cnt <= cnt + 16'd1;
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule
