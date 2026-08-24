// Sauvegarde cassette vers la carte SD (US-CSAVE.3/4) : consomme les octets
// .tap produits par `tape_demod` pendant un CSAVE et les écrit dans un fichier
// de la carte, via le chemin `fat32.wblk` (US-DISK.5 : suit la chaîne de
// clusters + CMD24), avec extension de chaîne à la demande (US-CSAVE.4).
//
// La CRÉATION du fichier (allocation FAT + entrée de répertoire) est faite en
// amont par `tape_creator` pendant l'amorce ; `file_idx` désigne ce fichier et
// `file_ready` autorise l'écriture du 1er bloc (le saver bufferise en attendant).
// Historique : US-CSAVE.3 écrivait dans un placeholder `SAVE.TAP` pré-existant.
//
// Contrôle de flux : la ROM CSAVE émet ~137 o/s, très lentement devant une
// écriture de bloc SPI. Un **double buffer ping-pong** (bufA/bufB de 512 o)
// suffit : on écrit le buffer plein pendant que l'autre se remplit — l'écriture
// se termine largement avant que le second buffer soit plein (512 octets à
// cadence cassette >> durée d'un CMD24). Aucun octet perdu.
//
// Le dernier bloc (partiel) est complété par des 0x00 ; `nbytes` donne la
// taille réelle sauvegardée (pour une future mise à jour de la taille dans
// l'entrée de répertoire — refinement séparé). Fin de capture = `capturing`
// retombe (silence détecté par tape_demod).

module tape_saver (
    input             clk,
    input             rst,
    // Flux depuis tape_demod
    input      [7:0]  byte_in,
    input             byte_valid,
    input             capturing,
    // Cible : index du fichier + autorisation SD
    input      [5:0]  file_idx,
    input             enable,        // niveau : autorise la capture SD
    input             file_ready,    // niveau : le fichier cible existe (créé) —
                                     // le 1er bloc n'est écrit qu'une fois haut
                                     // (US-CSAVE.4 : création pendant l'amorce)
    // Vers fat32.wblk
    output reg        wblk_start,
    output reg [5:0]  wblk_idx,
    output reg [31:0] wblk_offset,
    output     [7:0]  wblk_data,     // = buffer[wblk_pos]
    input      [8:0]  wblk_pos,      // index SD courant (0..511)
    input             wblk_done,
    input             wblk_error,
    // État
    output reg        busy,
    output reg        done,          // pulse : sauvegarde terminée
    output reg        error,
    output reg [31:0] nbytes         // octets réellement sauvegardés
);

    // Deux buffers de 512 octets (ping-pong).
    reg [7:0] bufA [0:511];
    reg [7:0] bufB [0:511];

    reg        fill_sel;             // buffer en cours de REMPLISSAGE (0=A,1=B)
    reg [9:0]  wcnt;                 // position de remplissage (0..512)
    reg [31:0] total;                // octets reçus
    reg [22:0] blkno;                // n° de bloc (offset = blkno*512)

    // Requête d'écriture d'un buffer plein/partiel.
    reg        wr_sel;               // buffer à ÉCRIRE
    reg [9:0]  wr_valid;             // octets valides dans ce bloc (512 = plein)
    reg        wr_req;               // une écriture est demandée
    reg        armed;                // capture démarrée (enable verrouillé)
    reg        had_file;             // file_ready a été vu (fichier créé) — si la
                                     // capture se termine sans, la save est
                                     // abandonnée proprement (CSAVE avorté/bruit)

    // Octet fourni à fat32 : buffer sélectionné, 0x00 au-delà des octets valides
    // (padding du dernier bloc).
    wire [7:0] wb_raw = wr_sel ? bufB[wblk_pos] : bufA[wblk_pos];
    assign wblk_data = (wblk_pos < wr_valid) ? wb_raw : 8'h00;

    // FSM d'écriture
    localparam WS_IDLE = 2'd0, WS_START = 2'd1, WS_WAIT = 2'd2;
    reg [1:0] wstate;

    always @(posedge clk) begin
        wblk_start <= 1'b0;
        done       <= 1'b0;

        if (rst) begin
            fill_sel <= 1'b0; wcnt <= 0; total <= 0; blkno <= 0;
            wr_req <= 1'b0; armed <= 1'b0; busy <= 1'b0; error <= 1'b0;
            nbytes <= 0; wstate <= WS_IDLE; had_file <= 1'b0;
        end else begin
            // -------- Remplissage --------
            if (!armed) begin
                // Démarre une capture au 1er octet si autorisé.
                if (enable && byte_valid) begin
                    armed <= 1'b1; busy <= 1'b1; error <= 1'b0; had_file <= 1'b0;
                    total <= 0; blkno <= 0; fill_sel <= 1'b0; wcnt <= 0;
                    // range le 1er octet
                    bufA[0] <= byte_in;
                    wcnt    <= 10'd1;
                    total   <= 32'd1;
                end
            end else begin
                if (file_ready) had_file <= 1'b1;   // fichier créé (verrouillé)
                if (byte_valid) begin
                    if (fill_sel) bufB[wcnt[8:0]] <= byte_in;
                    else          bufA[wcnt[8:0]] <= byte_in;
                    total <= total + 32'd1;
                    if (wcnt == 10'd511) begin
                        // bloc plein : demande son écriture, bascule de buffer
                        wr_sel   <= fill_sel;
                        wr_valid <= 10'd512;
                        wr_req   <= 1'b1;
                        fill_sel <= ~fill_sel;
                        wcnt     <= 0;
                    end else
                        wcnt <= wcnt + 10'd1;
                end

                // Fin de capture : flush du dernier bloc (partiel) puis clôture.
                if (!capturing && wstate == WS_IDLE && !wr_req) begin
                    if (!had_file) begin
                        // fichier jamais créé (CSAVE avorté / bruit avant le nom) :
                        // abandon propre, rien à écrire — évite le blocage sur
                        // file_ready qui ne viendra pas.
                        armed <= 1'b0; busy <= 1'b0; wcnt <= 0;
                    end else if (wcnt != 0) begin
                        wr_sel   <= fill_sel;
                        wr_valid <= wcnt;      // octets valides (reste padé à 0)
                        wr_req   <= 1'b1;
                        wcnt     <= 0;
                    end else begin
                        // rien en attente : terminé
                        armed  <= 1'b0;
                        busy   <= 1'b0;
                        done   <= 1'b1;
                        nbytes <= total;
                    end
                end
            end

            // -------- Moteur d'écriture (consomme wr_req) --------
            case (wstate)
                WS_IDLE: if (wr_req && file_ready) begin
                    wblk_idx    <= file_idx;
                    wblk_offset <= {blkno, 9'd0};   // blkno * 512
                    wstate      <= WS_START;
                end
                WS_START: begin
                    wblk_start <= 1'b1;             // pulse
                    wstate     <= WS_WAIT;
                end
                WS_WAIT: if (wblk_done) begin
                    wr_req <= 1'b0;
                    blkno  <= blkno + 23'd1;
                    if (wblk_error) begin
                        error <= 1'b1; armed <= 1'b0; busy <= 1'b0;
                        done  <= 1'b1; nbytes <= total;
                    end
                    wstate <= WS_IDLE;
                end
                default: wstate <= WS_IDLE;
            endcase
        end
    end

endmodule
