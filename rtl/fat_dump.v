// Debug : envoie le contenu d'un fichier de la carte SD vers l'UART (PC).
// Sur `trigger`, ouvre le fichier `sel_idx` via fat32 et relaie chaque octet à
// un uart_tx (contrôle de flux : un octet quand l'UART est libre). Permet de
// capturer sur le PC ce que fat32 lit réellement et de le comparer au .tap.

module fat_dump (
    input             clk,
    input             rst,
    input             trigger,       // pulse : démarrer le dump du fichier sel_idx
    input      [5:0]  sel_idx,
    input             fat_ready,      // fat32.done

    // Vers fat32 (lecture de fichier)
    output reg        open_start,
    output     [5:0]  open_idx,
    output            fdata_ready,
    input             fdata_valid,
    input      [7:0]  fdata,
    input             feof,

    // Vers uart_tx
    output reg [7:0]  tx_data,
    output reg        tx_send,
    input             tx_busy,

    output            active
);
    localparam D_IDLE=0, D_RUN=2, D_DONE=3;
    reg [1:0] state;

    assign open_idx = sel_idx;
    assign active   = (state != D_IDLE);

    // Handshake valid/ready en niveau : ready tant que l'UART est libre ;
    // le transfert a lieu au cycle où fat32 présente valid (un seul octet,
    // tx_send/tx_busy couvrent la retombée). Survit aux absences de valid
    // pendant que fat32 lit le secteur suivant.
    assign fdata_ready = (state == D_RUN) && !tx_busy && !tx_send;

    always @(posedge clk) begin
        open_start <= 1'b0;
        tx_send    <= 1'b0;
        if (rst) begin
            state <= D_IDLE;
        end else begin
            case (state)
                D_IDLE: if (trigger && fat_ready) begin
                    open_start <= 1'b1; state <= D_RUN;
                end
                D_RUN: begin
                    if (fdata_valid && fdata_ready) begin
                        tx_data <= fdata; tx_send <= 1'b1;   // transfert accepté
                    end else if (feof) begin
                        state <= D_DONE;
                    end
                end
                D_DONE: state <= D_IDLE;
                default: state <= D_IDLE;
            endcase
        end
    end

endmodule
