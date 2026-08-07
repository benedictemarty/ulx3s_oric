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
    output reg        fdata_ready,
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
    reg       armed;     // un octet a été demandé à fat32, on attend fdata_valid

    assign open_idx = sel_idx;
    assign active   = (state != D_IDLE);

    always @(posedge clk) begin
        open_start  <= 1'b0;
        tx_send     <= 1'b0;
        fdata_ready <= 1'b0;      // impulsion d'un seul cycle
        if (rst) begin
            state <= D_IDLE; armed <= 1'b0;
        end else begin
            case (state)
                D_IDLE: if (trigger && fat_ready) begin
                    open_start <= 1'b1; armed <= 1'b0; state <= D_RUN;
                end
                D_RUN: begin
                    if (armed) begin
                        // octet demandé : l'envoyer dès qu'il arrive
                        if (fdata_valid) begin
                            tx_data <= fdata; tx_send <= 1'b1; armed <= 1'b0;
                        end
                    end else if (feof) begin
                        state <= D_DONE;
                    end else if (!tx_busy && !tx_send) begin
                        // UART libre : demander un octet (une impulsion)
                        fdata_ready <= 1'b1; armed <= 1'b1;
                    end
                end
                D_DONE: state <= D_IDLE;
                default: state <= D_IDLE;
            endcase
        end
    end

endmodule
