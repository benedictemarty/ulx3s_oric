// Chargeur cassette depuis la carte SD : lit un fichier .tap via fat32 et
// l'injecte dans tape_injector en reproduisant le protocole UART
// (0x01, len_lo, len_hi, puis 1 octet par crédit 0x5A). Remplace le PC.
//
// Flux :
//   load_trigger -> envoie l'en-tête (taille = file_size) -> lance fat32.open
//   -> pour chaque crédit reçu du tape_injector, fournit l'octet suivant du
//   fichier (contrôle de flux par compteur de crédits).

module tape_loader #(
    parameter DELAY = 2170        // cycles entre octets (~115200 bauds à 25 MHz)
) (
    input             clk,
    input             rst,
    input             load_trigger,   // pulse : charger le fichier sel_idx
    input      [5:0]  sel_idx,
    input      [31:0] file_size,      // taille du fichier (fat32 q_size)
    input             fat_ready,      // fat32.done (parsing terminé)

    // Vers fat32 (lecture de fichier)
    output reg        open_start,
    output reg [5:0]  open_idx,
    output reg        fdata_ready,
    input             fdata_valid,
    input      [7:0]  fdata,
    input             feof,

    // Vers tape_injector
    output reg [7:0]  tape_rx_data,
    output reg        tape_rx_valid,
    input             tape_credit,    // = tape_injector.tx_send (crédit émis)

    output            active          // chargement en cours (pour le multiplexage)
);
    localparam L_IDLE=0, L_HDR0=1, L_HDR1=2, L_HDR2=3, L_OPEN=4, L_DATA=5, L_DONE=6;
    reg [2:0]  state;
    reg [15:0] len;
    reg [15:0] credits;          // large : le tape_injector envoie une rafale (FIFO)
    reg [15:0] dly;              // limitation de débit (évite la rafale d'octets)

    assign active = (state != L_IDLE);

    // Transfert fat32 : exactement un octet au cycle où valid ET ready sont hauts
    wire xfer = fdata_valid && fdata_ready;

    always @(posedge clk) begin
        open_start    <= 1'b0;
        tape_rx_valid <= 1'b0;
        if (rst) begin
            state <= L_IDLE; credits <= 16'd0; fdata_ready <= 1'b0; dly <= 16'd0;
        end else begin
            // compteur de crédits : +1 par crédit reçu, -1 par octet transféré
            credits <= credits + (tape_credit ? 16'd1 : 16'd0)
                               - ((state==L_DATA && xfer) ? 16'd1 : 16'd0);
            case (state)
                L_IDLE: if (load_trigger && fat_ready) begin
                    len <= file_size[15:0]; open_idx <= sel_idx;
                    credits <= 16'd0; dly <= 16'd0; state <= L_HDR0;
                end
                // en-tête (accepté sans crédit : tape_injector en S_IDLE/S_LEN)
                L_HDR0: begin tape_rx_data <= 8'h01;    tape_rx_valid <= 1'b1; state <= L_HDR1; end
                L_HDR1: begin tape_rx_data <= len[7:0]; tape_rx_valid <= 1'b1; state <= L_HDR2; end
                L_HDR2: begin tape_rx_data <= len[15:8];tape_rx_valid <= 1'b1; state <= L_OPEN; end
                L_OPEN: begin open_start <= 1'b1; state <= L_DATA; end
                // données : un octet par crédit
                L_DATA: begin
                    if (dly != 16'd0) dly <= dly - 16'd1;
                    // ready retombe dès le transfert (dly rechargé) : pas de
                    // double débit même si fat32 présente l'octet suivant vite
                    fdata_ready <= (credits != 16'd0) && (dly == 16'd0) && !xfer;
                    if (xfer) begin
                        tape_rx_data  <= fdata;
                        tape_rx_valid <= 1'b1;
                        dly <= DELAY[15:0];         // espace le prochain octet
                    end
                    if (feof) begin fdata_ready <= 1'b0; state <= L_DONE; end
                end
                L_DONE: state <= L_IDLE;
                default: state <= L_IDLE;
            endcase
        end
    end

endmodule
