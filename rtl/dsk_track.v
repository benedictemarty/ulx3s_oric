// Fournisseur de pistes .dsk depuis la SD (US-DISK.3) : sert le WD1793.
//
// Format MFM_DISK (réf. ~/Oric1/src/storage/sedoric.c) : en-tête 256 octets
// (« MFM_DISK », sides LE32 @8, tracks LE32 @12), puis pistes brutes de
// 6400 octets rangées côte 0 complète puis côte 1. Dans une piste, secteur =
// marque d'ID `A1 A1 A1 FE` + champs (track, side, sector, size) puis marque
// de données `A1 A1 A1 FB` dans [ID+10, ID+60] suivie de 256 octets (réf.
// mfm_extract_track — le scan est reproduit ici en RTL sur le buffer).
//
// Fonctionnement :
//   - `insert` (pulse, avec `file_idx`) : lit l'en-tête via fat32 (seek 0),
//     vérifie la signature, mémorise la géométrie -> `inserted`.
//   - Quand la piste demandée par le WD1793 ({req_side, req_track}) diffère
//     de la piste chargée : `trk_loading` monte (le WD gèle ses délais),
//     seek fat32 à 256 + (side*tracks + track)*6400, 6400 octets -> BRAM,
//     puis passe de scan (table des offsets de données des 17 secteurs).
//   - Service : `sec_valid` = secteur au catalogue de la piste chargée ;
//     `sec_byte` = BRAM[table[sec_id] + sec_addr] (lecture synchrone 1 clk).
//
// Le module est un CLIENT du fat32 partagé : il n'émet ses open/ready que
// lorsque `bus_grant` est haut (arbitrage au top ; en test : toujours 1).

module dsk_track (
    input             clk,
    input             rst,           // power-on UNIQUEMENT : un reset machine
                                     // n'éjecte pas la disquette (cf. soft_rst)
    input             soft_rst,      // reset machine (BTN1/banque) : interrompt
                                     // un transfert en cours, GARDE l'insertion

    // Contrôle insertion (depuis l'OSD)
    input             insert,        // pulse : insérer le fichier file_idx
    input      [5:0]  file_idx,
    input             eject,         // pulse : retirer la disquette
    output reg        inserted,
    output reg        bad_format,    // signature MFM_DISK absente

    // Client fat32 (bus partagé, cf. arbitrage au top)
    input             bus_grant,
    input             fat_done,
    output reg        open_start,
    output     [5:0]  open_idx,
    output reg [31:0] open_offset,
    output reg        open_abort,
    output reg        fdata_ready,
    input             fdata_valid,
    input      [7:0]  fdata,
    input             feof,

    // Côté WD1793 (fournisseur de secteurs)
    input      [6:0]  req_track,
    input             req_side,
    output            trk_loading,
    output reg        disk_present,
    output     [6:0]  n_tracks,
    output     [4:0]  n_spt,
    input      [4:0]  sec_id,
    output            sec_valid,
    input      [8:0]  sec_addr,
    output     [7:0]  sec_byte,

    // Écriture de secteur (US-DISK.5 phase 3). Le WD1793 pousse les octets du
    // secteur dans tbuf (sec_we, à la position sec_off[sec_id]+sec_addr), puis
    // pulse wr_commit : dsk_track persiste le secteur sur la SD par
    // read-modify-write des 1-2 blocs SD touchés (fat32.wblk). wr_busy gèle le
    // WD pendant l'opération ; wr_ok/wr_err pulsent à la fin.
    input             sec_we,        // pulse : tbuf[serve_addr] <= sec_wr_data
    input      [7:0]  sec_wr_data,
    input             wr_commit,     // pulse : write-back du secteur courant
    output reg        wr_busy,
    output reg        wr_ok,
    output reg        wr_err,
    // Pilotage fat32.wblk (écriture d'un bloc de 512 o à un offset aligné)
    output reg        wblk_start,
    output     [5:0]  wblk_idx,
    output reg [31:0] wblk_offset,
    output     [7:0]  wblk_data,
    input      [8:0]  wblk_pos,
    input             wblk_done,
    input             wblk_error
);

    localparam TRK_BYTES = 6400;

    // Géométrie (en-tête MFM_DISK)
    reg [6:0]  geo_tracks;
    reg [1:0]  geo_sides;
    reg [5:0]  cur_idx;              // fichier inséré
    assign open_idx = cur_idx;
    assign n_tracks = geo_tracks;
    assign n_spt    = 5'd17;

    // Piste chargée (255 = aucune)
    reg [7:0]  loaded;               // {side, track}
    wire [7:0] wanted = {req_side, req_track};
    // Cible capturée au DÉBUT du chargement : si la demande change en cours
    // de route (seek pendant un rechargement), loaded <= load_tgt garde le
    // mismatch avec wanted et la bonne piste est rechargée aussitôt.
    reg [7:0]  load_tgt;

    // Buffer de piste (6400 octets, BRAM) + table des secteurs
    reg [7:0]  tbuf [0:TRK_BYTES-1];
    reg [12:0] sec_off [0:17];       // offset des données du secteur 1..17
    reg [17:0] sec_ok;               // bit s = secteur s présent

    // Write-back (US-DISK.5 phase 3) : tampon d'un bloc SD (512 o) + RMW.
    reg [7:0]  wbbuf [0:511];
    reg [9:0]  wbpos;                // remplissage lecture du bloc (0..512)
    reg [31:0] sfo;                  // offset fichier du début du secteur
    reg [12:0] wb_base;              // offset du secteur dans tbuf
    reg [31:0] cur_blk;              // offset du bloc SD courant (aligné 512)
    reg        two_blocks;           // le secteur chevauche 2 blocs
    reg [9:0]  ocnt0;                // octets du secteur situés dans le 1er bloc
    reg [8:0]  ov_wdst;              // position dest dans le bloc (0..511)
    reg [12:0] ov_tptr;              // position source dans tbuf
    reg [9:0]  ov_cnt, ov_i;         // longueur et compteur overlay
    reg [1:0]  ov_ph;                // 0 pose adresse, 1 latence, 2 écrit wbbuf
    assign wblk_data = wbbuf[wblk_pos];   // combinatoire (cf. tb_fat_write) :
    assign wblk_idx  = cur_idx;           // pas de latence -> sd_spi latche juste

    // ------------------------------------------------------------------
    // FSM
    // ------------------------------------------------------------------
    localparam D_IDLE = 4'd0,
               D_HOPEN = 4'd1, D_HDR = 4'd2,          // en-tête
               D_TOPEN = 4'd3, D_FILL = 4'd4,         // piste
               D_SCAN = 4'd5, D_SCID = 4'd6, D_SHUNT = 4'd7,
               D_DONE = 4'd8,
               // write-back (US-DISK.5 phase 3)
               D_WSTART = 4'd9, D_ROPEN = 4'd10, D_RD = 4'd11,
               D_OVL = 4'd12, D_WR = 4'd13, D_WNEXT = 4'd14;
    reg [3:0]  state;
    assign trk_loading = inserted && (state != D_IDLE);

    reg [12:0] wpos;                 // position d'écriture/scan dans tbuf
    reg [7:0]  hdr [0:15];           // 16 premiers octets de l'en-tête
    reg [31:0] shreg;                // 4 derniers octets vus (scan)
    reg [12:0] mark_pos;             // position de la marque FE trouvée
    reg [2:0]  idcnt;
    reg [7:0]  id_sec;
    reg [6:0]  hunt;                 // fenêtre de recherche de la marque FB

    // Multiplexage du port BRAM : écriture pendant FILL, lecture sinon
    reg  [12:0] rd_addr;
    reg  [7:0]  tbuf_q;
    wire [12:0] serve_addr = sec_off[sec_id_clip] + {4'd0, sec_addr};
    wire [4:0]  sec_id_clip = (sec_id <= 5'd17) ? sec_id : 5'd0;
    always @(posedge clk) begin
        if (state == D_FILL && fdata_valid && fdata_ready)
            tbuf[wpos] <= fdata;
        else if (sec_we)                      // WD1793 : octet de secteur
            tbuf[serve_addr] <= sec_wr_data;
        tbuf_q <= tbuf[(state == D_IDLE || state == D_DONE) ? serve_addr
                                                            : rd_addr];
    end
    assign sec_byte  = tbuf_q;

    // Tampon de bloc : rempli par la lecture SD (W_RD), écrasé par les octets
    // de secteur venant de tbuf (W_OVL), streamé vers sd_spi à l'écriture (W_WR).
    always @(posedge clk) begin
        if (state == D_RD && fdata_valid && fdata_ready)
            wbbuf[wbpos[8:0]] <= fdata;
        else if (state == D_OVL && ov_ph == 2'd2)   // phase écriture de l'overlay
            wbbuf[ov_wdst] <= tbuf_q;
    end
    assign sec_valid = inserted && (state == D_IDLE) &&
                       (sec_id >= 5'd1) && (sec_id <= 5'd17) &&
                       sec_ok[sec_id];

    // ------------------------------------------------------------------
    integer k;
    always @(posedge clk) begin
        open_start  <= 1'b0;
        open_abort  <= 1'b0;
        wblk_start  <= 1'b0;
        wr_ok       <= 1'b0;
        wr_err      <= 1'b0;
        if (rst) begin
            state <= D_IDLE; inserted <= 1'b0; disk_present <= 1'b0;
            bad_format <= 1'b0; loaded <= 8'hFF; sec_ok <= 18'd0;
            fdata_ready <= 1'b0; open_offset <= 32'd0;
            wr_busy <= 1'b0;
        end else if (soft_rst && state != D_IDLE) begin
            // Reset machine en plein transfert : on abandonne proprement (la
            // piste sera rechargée à la demande) mais la disquette RESTE
            // insérée — comme un vrai lecteur.
            state <= D_IDLE;
            fdata_ready <= 1'b0;
            loaded <= 8'hFF;
            wr_busy <= 1'b0;
        end else begin
            case (state)
                D_IDLE: begin
                    fdata_ready <= 1'b0;
                    if (eject) begin
                        inserted <= 1'b0; disk_present <= 1'b0;
                        loaded <= 8'hFF; sec_ok <= 18'd0;
                    end else if (insert && fat_done && bus_grant) begin
                        cur_idx <= file_idx;
                        inserted <= 1'b0; disk_present <= 1'b0;
                        bad_format <= 1'b0;
                        loaded <= 8'hFF; sec_ok <= 18'd0;
                        open_offset <= 32'd0;
                        open_start <= 1'b1;
                        wpos <= 13'd0;
                        state <= D_HDR;
                    end else if (inserted && loaded != wanted &&
                                 fat_done && bus_grant) begin
                        // (re)charger la piste demandée
                        open_offset <= 32'd256
                            + ({25'd0, req_track}
                               + (req_side ? {25'd0, geo_tracks} : 32'd0))
                              * TRK_BYTES;
                        open_start <= 1'b1;
                        load_tgt <= wanted;
                        wpos <= 13'd0; sec_ok <= 18'd0;
                        state <= D_TOPEN;
                    end else if (wr_commit && inserted && loaded == wanted &&
                                 sec_ok[sec_id_clip] && fat_done && bus_grant) begin
                        // Persister le secteur courant (déjà dans tbuf) sur la SD.
                        // sfo = 256 + (track + side*tracks)*6400 + sec_off[sec].
                        wb_base <= sec_off[sec_id_clip];
                        sfo <= 32'd256
                             + ({25'd0, loaded[6:0]}
                                + (loaded[7] ? {25'd0, geo_tracks} : 32'd0))
                               * TRK_BYTES
                             + {19'd0, sec_off[sec_id_clip]};
                        wr_busy <= 1'b1;
                        state <= D_WSTART;
                    end
                end

                // ---- En-tête : 16 octets suffisent ----
                D_HDR: begin
                    fdata_ready <= 1'b1;
                    if (fdata_valid && fdata_ready) begin
                        if (wpos < 13'd16) hdr[wpos[3:0]] <= fdata;
                        wpos <= wpos + 13'd1;
                        if (wpos == 13'd15) begin
                            fdata_ready <= 1'b0;
                            open_abort  <= 1'b1;
                            state <= D_DONE;
                        end
                    end
                    if (feof) begin bad_format <= 1'b1; state <= D_DONE; end
                end

                // ---- Piste : 6400 octets vers tbuf ----
                D_TOPEN: state <= D_FILL;
                D_FILL: begin
                    fdata_ready <= 1'b1;
                    if (fdata_valid && fdata_ready) begin
                        wpos <= wpos + 13'd1;       // écriture dans le bloc BRAM
                        if (wpos == TRK_BYTES - 1) begin
                            fdata_ready <= 1'b0;
                            open_abort  <= 1'b1;
                            wpos <= 13'd0; rd_addr <= 13'd0;
                            shreg <= 32'd0;
                            state <= D_SCAN;
                        end
                    end
                    if (feof) begin                  // fichier court : piste vide
                        fdata_ready <= 1'b0;
                        loaded <= load_tgt;          // évite de boucler
                        state <= D_DONE;
                    end
                end

                // ---- Scan : marques A1 A1 A1 FE (réf. mfm_extract_track) ----
                D_SCAN: begin
                    if (rd_addr >= TRK_BYTES - 1) begin
                        loaded <= load_tgt;
                        state <= D_DONE;
                    end else begin
                        shreg <= {shreg[23:0], tbuf_q};
                        rd_addr <= rd_addr + 13'd1;
                        if ({shreg[23:0], tbuf_q} == 32'hA1A1A1FE) begin
                            mark_pos <= rd_addr;     // position APRÈS FE
                            idcnt <= 3'd0;
                            state <= D_SCID;
                        end
                    end
                end
                D_SCID: begin                        // track, side, sector, size
                    if (idcnt == 3'd2) id_sec <= tbuf_q;
                    idcnt <= idcnt + 3'd1;
                    rd_addr <= rd_addr + 13'd1;
                    if (idcnt == 3'd3) begin
                        // chercher A1 A1 A1 FB dans [FE+10, FE+60]
                        rd_addr <= mark_pos + 13'd9;
                        hunt <= 7'd0;
                        shreg <= 32'd0;
                        state <= D_SHUNT;
                    end
                end
                D_SHUNT: begin
                    shreg <= {shreg[23:0], tbuf_q};
                    rd_addr <= rd_addr + 13'd1;
                    hunt <= hunt + 7'd1;
                    if ({shreg[23:0], tbuf_q} == 32'hA1A1A1FB) begin
                        if (id_sec >= 8'd1 && id_sec <= 8'd17 &&
                            rd_addr + 13'd256 < TRK_BYTES) begin
                            sec_off[id_sec[4:0]] <= rd_addr; // données après FB
                            sec_ok[id_sec[4:0]] <= 1'b1;
                        end
                        // reprendre le scan après la marque FE (réf. : i++)
                        rd_addr <= mark_pos + 13'd1;
                        shreg <= 32'd0;
                        state <= D_SCAN;
                    end else if (hunt >= 7'd54 ||
                                 rd_addr >= TRK_BYTES - 1) begin
                        rd_addr <= mark_pos + 13'd1;   // FB introuvable
                        shreg <= 32'd0;
                        state <= D_SCAN;
                    end
                end

                D_DONE: begin
                    if (!bad_format && loaded == 8'hFF && wpos != 13'd0) begin
                        // fin de lecture d'en-tête : valider la signature
                        if (hdr[0]=="M" && hdr[1]=="F" && hdr[2]=="M" &&
                            hdr[3]=="_" && hdr[4]=="D" && hdr[5]=="I" &&
                            hdr[6]=="S" && hdr[7]=="K") begin
                            geo_sides  <= hdr[8][1:0];
                            geo_tracks <= hdr[12][6:0];
                            inserted   <= 1'b1;
                            disk_present <= 1'b1;
                        end else
                            bad_format <= 1'b1;
                    end
                    wpos <= 13'd0;
                    state <= D_IDLE;
                end

                // ---- Write-back du secteur : RMW du/des bloc(s) SD ----
                D_WSTART: begin
                    cur_blk    <= sfo & ~32'h1FF;
                    // octets du secteur dans le 1er bloc = min(256, 512 - (sfo mod 512))
                    two_blocks <= (sfo[8:0] > 9'd256);
                    ocnt0      <= (sfo[8:0] > 9'd256)
                                  ? (10'd512 - {1'b0, sfo[8:0]})
                                  : 10'd256;
                    state <= D_ROPEN;
                end
                D_ROPEN: begin                    // ouvrir le bloc en lecture
                    open_offset <= cur_blk;
                    open_start  <= 1'b1;
                    wbpos <= 10'd0;
                    state <= D_RD;
                end
                D_RD: begin                       // 512 octets SD -> wbbuf
                    fdata_ready <= 1'b1;
                    if (fdata_valid && fdata_ready) begin
                        wbpos <= wbpos + 10'd1;
                        if (wbpos == 10'd511) begin
                            fdata_ready <= 1'b0;
                            open_abort  <= 1'b1;
                            // 1er bloc : dest = sfo mod 512, source tbuf = début
                            // secteur, ocnt0 octets. 2e bloc : dest = 0, source
                            // = wb_base+ocnt0, 256-ocnt0 octets. (déterministe,
                            // pas d'accumulation -> pas de fencepost à la jointure)
                            if (cur_blk[31:9] == sfo[31:9]) begin
                                ov_wdst <= sfo[8:0];
                                ov_tptr <= wb_base;
                                ov_cnt  <= ocnt0;
                            end else begin
                                ov_wdst <= 9'd0;
                                ov_tptr <= wb_base + ocnt0;   // 13b = 13b + 10b
                                ov_cnt  <= 10'd256 - ocnt0;
                            end
                            ov_i  <= 10'd0;
                            ov_ph <= 2'd0;
                            state <= D_OVL;
                        end
                    end
                    if (feof) begin
                        wr_err <= 1'b1; wr_busy <= 1'b0; state <= D_IDLE;
                    end
                end
                D_OVL: begin                      // écraser les octets de secteur
                    if (ov_i == ov_cnt) begin
                        state <= D_WR;
                    end else case (ov_ph)         // 3 phases (latence BRAM tbuf)
                        2'd0: begin rd_addr <= ov_tptr; ov_ph <= 2'd1; end
                        2'd1: ov_ph <= 2'd2;
                        default: begin            // wbbuf[ov_wdst]<=tbuf_q ailleurs
                            ov_wdst <= ov_wdst + 9'd1;
                            ov_tptr <= ov_tptr + 13'd1;
                            ov_i    <= ov_i + 10'd1;
                            ov_ph   <= 2'd0;
                        end
                    endcase
                end
                D_WR: begin                       // réécrire le bloc (fat32.wblk)
                    wblk_offset <= cur_blk;
                    wblk_start  <= 1'b1;
                    state <= D_WNEXT;
                end
                D_WNEXT: begin
                    if (wblk_error) begin
                        wr_err <= 1'b1; wr_busy <= 1'b0; state <= D_IDLE;
                    end else if (wblk_done) begin
                        if (two_blocks && cur_blk == (sfo & ~32'h1FF)) begin
                            cur_blk <= (sfo & ~32'h1FF) + 32'd512;
                            state <= D_ROPEN;
                        end else begin
                            wr_ok <= 1'b1; wr_busy <= 1'b0; state <= D_IDLE;
                        end
                    end
                end

                default: state <= D_IDLE;
            endcase
        end
    end

endmodule
