// Orchestration de la création de fichier cassette (US-CSAVE.4 phase D2).
// Pendant un CSAVE, séquence la VRAIE création FAT32 du fichier .tap sur la SD :
//   1. extrait le nom 8.3 du flux (module `tape_name` interne) ;
//   2. alloue un 1er cluster libre (`fat32.alloc`) ;
//   3. crée l'entrée de répertoire (`fat32.mkent`) au nom réel, taille 0 ;
//   4. publie `file_idx`/`file_ready` -> le `tape_saver` écrit les blocs (avec
//      extension de chaîne à la demande) ;
//   5. à la fin de capture (`sav_done`), inscrit la taille réelle dans l'entrée
//      (`fat32.dsize`).
//
// La création se fait pendant l'amorce (~259 o de 0x16), donc bien avant le 1er
// bloc de 512 o : `file_ready` est haut à temps, aucun octet perdu.
// L'accès à fat32 est naturellement sérialisé : création (alloc/mkent) PENDANT
// l'amorce, écriture (wblk) ENSUITE, taille (dsize) APRÈS la capture — jamais
// simultanés. Si l'allocation ou l'entrée échoue (SD pleine), la save est
// abandonnée proprement (`file_ready` reste bas -> le saver ne peut pas écrire).

module tape_creator (
    input             clk,
    input             rst,
    // Flux depuis tape_demod
    input      [7:0]  byte_in,
    input             byte_valid,
    input             capturing,
    // fat32 : allocation de cluster
    output reg        alloc_start,
    output reg [31:0] alloc_prev,
    input      [31:0] alloc_clus,
    input             alloc_done,
    input             alloc_error,
    // fat32 : création d'entrée de répertoire
    output reg        mkent_start,
    output reg [87:0] mkent_name,
    output reg [31:0] mkent_clus,
    output reg [31:0] mkent_size,
    input      [5:0]  mkent_idx,
    input             mkent_done,
    input             mkent_error,
    // fat32 : mise à jour de la taille
    output reg        dsize_start,
    output reg [5:0]  dsize_idx,
    output reg [31:0] dsize_val,
    input             dsize_done,
    // depuis tape_saver
    input             sav_done,
    input      [31:0] sav_nbytes,
    // vers tape_saver
    output reg [5:0]  file_idx,
    output reg        file_ready,
    // état
    output            busy
);
    // Extracteur de nom
    wire [87:0] name83;
    wire        name_ready;
    tape_name namer (
        .clk(clk), .rst(rst), .byte_in(byte_in), .byte_valid(byte_valid),
        .capturing(capturing), .name83(name83), .name_ready(name_ready)
    );

    localparam CR_IDLE=4'd0, CR_NAME=4'd1, CR_ALLOC=4'd2, CR_ALLOCW=4'd3,
               CR_MKENT=4'd4, CR_MKENTW=4'd5, CR_ACTIVE=4'd6, CR_DSIZE=4'd7,
               CR_DSIZEW=4'd8, CR_END=4'd9, CR_FAIL=4'd10;
    reg [3:0] state;

    assign busy = (state != CR_IDLE);

    always @(posedge clk) begin
        alloc_start <= 1'b0;
        mkent_start <= 1'b0;
        dsize_start <= 1'b0;
        if (rst) begin
            state <= CR_IDLE; file_ready <= 1'b0; file_idx <= 6'd0;
        end else case (state)
            CR_IDLE: if (capturing) begin file_ready <= 1'b0; state <= CR_NAME; end
            // attente du nom (extrait après l'en-tête) ; capture avortée -> repos
            CR_NAME: if (!capturing) state <= CR_IDLE;
                     else if (name_ready) state <= CR_ALLOC;
            // alloue le 1er cluster
            CR_ALLOC: begin alloc_start <= 1'b1; alloc_prev <= 32'd0; state <= CR_ALLOCW; end
            CR_ALLOCW: if (alloc_done) begin
                           if (alloc_error) state <= CR_FAIL;
                           else begin mkent_clus <= alloc_clus; state <= CR_MKENT; end
                       end
            // crée l'entrée au nom réel, taille 0
            CR_MKENT: begin
                          mkent_name <= name83; mkent_size <= 32'd0;
                          mkent_start <= 1'b1; state <= CR_MKENTW;
                      end
            CR_MKENTW: if (mkent_done) begin
                           if (mkent_error) state <= CR_FAIL;
                           else begin
                               file_idx <= mkent_idx; file_ready <= 1'b1;
                               state <= CR_ACTIVE;
                           end
                       end
            // fichier prêt : le saver écrit ; on attend la fin de capture
            CR_ACTIVE: if (sav_done) begin
                           dsize_idx <= file_idx; dsize_val <= sav_nbytes;
                           state <= CR_DSIZE;
                       end
            // inscrit la taille réelle
            CR_DSIZE:  begin dsize_start <= 1'b1; state <= CR_DSIZEW; end
            CR_DSIZEW: if (dsize_done) state <= CR_END;
            CR_END:    begin file_ready <= 1'b0; if (!capturing) state <= CR_IDLE; end
            CR_FAIL:   begin file_ready <= 1'b0; if (!capturing) state <= CR_IDLE; end
            default:   state <= CR_IDLE;
        endcase
    end
endmodule
