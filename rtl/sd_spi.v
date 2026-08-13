// Pilote carte SD en mode SPI (init + lecture de secteur), Verilog-2005.
// Utilise le moteur d'octet rtl/spi_byte.v.
//
// Séquence d'initialisation (SD SPI standard) :
//   power-up (>=74 clocks CS haut) -> CMD0 (idle) -> CMD8 (v2, check tension)
//   -> ACMD41 (CMD55+CMD41, HCS) jusqu'à prêt -> CMD58 (OCR, bit CCS = SDHC).
// Lecture : CMD17 (adresse bloc si SDHC, sinon octet) -> token 0xFE -> 512
// octets (data/data_valid) -> 2 octets CRC ignorés.
//
// `status` code l'étape / l'erreur (pour diagnostic par LED). `ready` = init OK.
// Vitesse : init à ~390 kHz (HALF, norme SD), puis HALF_FAST (6,25 MHz)
// pour tous les transferts dès que `ready` est haut (US-SD-SPEED).

module sd_spi #(
    parameter CLK_HZ    = 25000000,
    parameter HALF      = 32,      // demi-période sck init (25 MHz/64 ≈ 390 kHz)
    parameter HALF_FAST = 2        // après init : 25 MHz/4 = 6,25 MHz
) (
    input             clk,
    input             rst,
    input             start_read,  // pulse : lire le secteur `sector`
    input      [31:0] sector,      // adresse logique de bloc (LBA)
    output reg        ready,       // carte initialisée
    output reg        busy,
    output reg        error,
    output reg [7:0]  data,        // octet lu
    output reg        data_valid,  // pulse par octet
    output reg [7:0]  status,      // étape/erreur (diagnostic)
    // SPI
    output            sck,
    output            mosi,
    input             miso,
    output reg        cs_n
);

    // ------------------------------------------------------------------
    // Moteur d'octet SPI
    // ------------------------------------------------------------------
    reg        spi_start;
    reg  [7:0] spi_tx;
    wire [7:0] spi_rx;
    wire       spi_done, spi_busy;

    // Init à vitesse normalisée (<=400 kHz), puis tout à HALF_FAST dès que
    // la carte est prête (US-SD-SPEED).
    spi_byte #(.HALF(HALF), .HALF_FAST(HALF_FAST)) engine (
        .clk(clk), .rst(rst), .fast(ready),
        .start(spi_start), .tx(spi_tx), .rx(spi_rx),
        .busy(spi_busy), .done(spi_done), .sck(sck), .mosi(mosi), .miso(miso)
    );

    // ------------------------------------------------------------------
    // Sous-programme "transférer un octet" : poser spi_tx, aller à XFER avec
    // `ret` = état de retour ; l'octet reçu se retrouve dans `rxb`.
    // ------------------------------------------------------------------
    localparam
        S_IDLE   = 8'd0,  S_XFER   = 8'd1,  S_XFER_W = 8'd2,
        S_PWR    = 8'd3,  S_PWR_N  = 8'd4,  S_CS0    = 8'd5,
        S_SC     = 8'd6,  S_SC_B   = 8'd7,  S_SC_N   = 8'd8,
        S_SC_R1  = 8'd9,  S_SC_R1C = 8'd10,
        S_CMD0   = 8'd11, S_CMD0D  = 8'd12,
        S_CMD8   = 8'd13, S_CMD8D  = 8'd14, S_CMD8R  = 8'd15, S_CMD8RC = 8'd16,
        S_A55    = 8'd17, S_A55D   = 8'd18, S_A41    = 8'd19, S_A41D   = 8'd20,
        S_CMD58  = 8'd21, S_CMD58D = 8'd22, S_58R    = 8'd23, S_58RC   = 8'd24,
        S_READY  = 8'd25,
        S_CMD17  = 8'd26, S_CMD17D = 8'd27, S_TOKEN  = 8'd28, S_TOKENC = 8'd29,
        S_DATA   = 8'd30, S_DATAC  = 8'd31, S_CRC    = 8'd32, S_END    = 8'd33,
        S_ERROR  = 8'd34,
        S_SC0    = 8'd35, S_POST   = 8'd36, S_POST2  = 8'd37;

    reg [7:0]  state, ret;
    reg [7:0]  rxb;
    reg [7:0]  cmdreg, crcreg;
    reg [31:0] argreg;
    reg [7:0]  after_r1;      // état après lecture de R1
    reg [7:0]  r1;
    reg [2:0]  cmd_i;
    reg [15:0] retry;
    reg [9:0]  bcnt;          // compteur d'octets (0..511 data, 0..3 OCR/R7)
    reg [2:0]  auxn;          // compteur d'octets auxiliaires (R7/OCR)
    reg        ccs;           // 1 = SDHC (adressage bloc)
    reg [31:0] addr;

    function [7:0] cmd_byte;
        input [2:0] i; input [7:0] c; input [31:0] a; input [7:0] r;
        case (i)
            3'd0: cmd_byte = c;
            3'd1: cmd_byte = a[31:24];
            3'd2: cmd_byte = a[23:16];
            3'd3: cmd_byte = a[15:8];
            3'd4: cmd_byte = a[7:0];
            default: cmd_byte = r;
        endcase
    endfunction

    always @(posedge clk) begin
        data_valid <= 1'b0;
        spi_start  <= 1'b0;
        if (rst) begin
            state <= S_PWR; cs_n <= 1'b1; ready <= 1'b0; busy <= 1'b1;
            error <= 1'b0; status <= 8'h00; retry <= 16'd0; bcnt <= 10'd0;
            ccs <= 1'b0;
        end else begin
            case (state)
                // ---- transfert d'un octet (sous-programme) ----
                S_XFER:   begin spi_start <= 1'b1; state <= S_XFER_W; end
                S_XFER_W: if (spi_done) begin rxb <= spi_rx; state <= ret; end

                // ---- power-up : CS haut, 10 octets 0xFF (80 clocks) ----
                S_PWR: begin
                    cs_n <= 1'b1; status <= 8'h01; retry <= 16'd0;
                    spi_tx <= 8'hFF; ret <= S_PWR_N; state <= S_XFER;
                end
                S_PWR_N: begin
                    if (retry == 16'd9) begin state <= S_CS0; end
                    else begin retry <= retry + 16'd1; spi_tx <= 8'hFF;
                               ret <= S_PWR_N; state <= S_XFER; end
                end
                S_CS0: begin cs_n <= 1'b0; state <= S_CMD0; end

                // ---- sous-programme : envoyer commande + lire R1 ----
                // dummy clock (8 cycles) avant chaque commande : robustesse
                S_SC:   begin spi_tx <= 8'hFF; ret <= S_SC0; state <= S_XFER; end
                S_SC0:  begin cmd_i <= 3'd0; state <= S_SC_B; end
                S_SC_B: begin spi_tx <= cmd_byte(cmd_i, cmdreg, argreg, crcreg);
                              ret <= S_SC_N; state <= S_XFER; end
                S_SC_N: begin
                    if (cmd_i == 3'd5) begin retry <= 16'd0; state <= S_SC_R1; end
                    else begin cmd_i <= cmd_i + 3'd1; state <= S_SC_B; end
                end
                S_SC_R1: begin spi_tx <= 8'hFF; ret <= S_SC_R1C; state <= S_XFER; end
                S_SC_R1C: begin
                    if (!rxb[7]) begin r1 <= rxb; state <= after_r1; end
                    else if (retry == 16'd500) begin state <= S_ERROR; end
                    else begin retry <= retry + 16'd1; state <= S_SC_R1; end
                end

                // ---- CMD0 : GO_IDLE (attend R1=0x01) ----
                S_CMD0: begin status <= 8'h02;
                    cmdreg <= 8'h40; argreg <= 32'd0; crcreg <= 8'h95;
                    after_r1 <= S_CMD0D; state <= S_SC; end
                S_CMD0D: if (r1 == 8'h01) state <= S_CMD8; else state <= S_ERROR;

                // ---- CMD8 : SEND_IF_COND (v2) ----
                S_CMD8: begin status <= 8'h03;
                    cmdreg <= 8'h48; argreg <= 32'h000001AA; crcreg <= 8'h87;
                    after_r1 <= S_CMD8D; state <= S_SC; end
                S_CMD8D: begin
                    // R1=0x01 attendu ; lire 4 octets R7 (echo 0xAA au dernier)
                    if (r1 == 8'h01) begin auxn <= 3'd0; state <= S_CMD8R; end
                    else state <= S_ERROR;
                end
                S_CMD8R: begin spi_tx <= 8'hFF; ret <= S_CMD8RC; state <= S_XFER; end
                S_CMD8RC: begin
                    if (auxn == 3'd3) begin
                        if (rxb == 8'hAA) state <= S_A55; else state <= S_ERROR;
                    end else begin auxn <= auxn + 3'd1; state <= S_CMD8R; end
                end

                // ---- ACMD41 : CMD55 + CMD41 (HCS) en boucle ----
                S_A55: begin status <= 8'h04;
                    cmdreg <= 8'h77; argreg <= 32'd0; crcreg <= 8'hFF;
                    after_r1 <= S_A55D; state <= S_SC; end
                S_A55D: state <= S_A41;
                S_A41: begin
                    cmdreg <= 8'h69; argreg <= 32'h40000000; crcreg <= 8'hFF;
                    after_r1 <= S_A41D; state <= S_SC; end
                S_A41D: begin
                    if (r1 == 8'h00) state <= S_CMD58;   // prêt
                    else state <= S_A55;                 // rejouer ACMD41
                end

                // ---- CMD58 : lire OCR (bit CCS = SDHC) ----
                S_CMD58: begin status <= 8'h05;
                    cmdreg <= 8'h7A; argreg <= 32'd0; crcreg <= 8'hFF;
                    after_r1 <= S_CMD58D; state <= S_SC; end
                S_CMD58D: begin auxn <= 3'd0; state <= S_58R; end
                S_58R: begin spi_tx <= 8'hFF; ret <= S_58RC; state <= S_XFER; end
                S_58RC: begin
                    if (auxn == 3'd0) ccs <= rxb[6];     // OCR[30] = CCS
                    if (auxn == 3'd3) state <= S_READY;
                    else begin auxn <= auxn + 3'd1; state <= S_58R; end
                end

                // ---- init terminée ----
                S_READY: begin
                    ready <= 1'b1; busy <= 1'b0; status <= 8'h80; cs_n <= 1'b1;
                    if (start_read) begin
                        busy <= 1'b1; ready <= 1'b1; cs_n <= 1'b0;
                        addr <= ccs ? sector : (sector << 9);  // bloc ou octet
                        state <= S_CMD17;
                    end
                end

                // ---- CMD17 : READ_SINGLE_BLOCK ----
                S_CMD17: begin status <= 8'h81;
                    cmdreg <= 8'h51; argreg <= addr; crcreg <= 8'hFF;
                    after_r1 <= S_CMD17D; state <= S_SC; end
                S_CMD17D: if (r1 == 8'h00) begin retry <= 16'd0; state <= S_TOKEN; end
                          else state <= S_ERROR;

                // ---- attendre le token de données 0xFE ----
                S_TOKEN: begin spi_tx <= 8'hFF; ret <= S_TOKENC; state <= S_XFER; end
                S_TOKENC: begin
                    if (rxb == 8'hFE) begin bcnt <= 10'd0; state <= S_DATA; end
                    else if (retry == 16'd10000) state <= S_ERROR;
                    else begin retry <= retry + 16'd1; state <= S_TOKEN; end
                end

                // ---- 512 octets de données ----
                S_DATA: begin spi_tx <= 8'hFF; ret <= S_DATAC; state <= S_XFER; end
                S_DATAC: begin
                    data <= rxb; data_valid <= 1'b1;
                    if (bcnt == 10'd511) begin auxn <= 3'd0; state <= S_CRC; end
                    else begin bcnt <= bcnt + 10'd1; state <= S_DATA; end
                end

                // ---- 2 octets CRC (ignorés) ----
                S_CRC: begin spi_tx <= 8'hFF; ret <= S_END; state <= S_XFER; end
                S_END: begin
                    if (auxn == 3'd1) begin
                        cs_n <= 1'b1; state <= S_POST;   // désélection + dummy clock
                    end else begin auxn <= auxn + 3'd1; state <= S_CRC; end
                end
                // 8 cycles d'horloge cs haut : la carte finalise avant la commande suivante
                S_POST:  begin spi_tx <= 8'hFF; ret <= S_POST2; state <= S_XFER; end
                S_POST2: begin busy <= 1'b0; status <= 8'h82; state <= S_READY; end

                // ---- erreur ----
                S_ERROR: begin
                    error <= 1'b1; busy <= 1'b0; cs_n <= 1'b1;
                    status <= {4'hE, state[3:0]};   // Ex : E + état fautif
                    // reste bloqué (reset requis)
                end

                default: state <= S_ERROR;
            endcase
        end
    end

endmodule
