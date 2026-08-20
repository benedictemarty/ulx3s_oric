// Parseur FAT32 minimal (lecture seule) : lit le BPB et liste les fichiers
// .TAP / .DSK du répertoire racine. S'appuie sur un pilote de secteur externe
// (rtl/sd_spi.v) via rd_start/rd_sector + data/data_valid.
//
// Gère : table de partition MBR (secteur 0) OU superfloppy (BPB au secteur 0,
// détecté par l'octet de saut 0xEB/0xE9). Répertoire racine lu sur les premiers
// secteurs du cluster racine (suffisant pour un petit répertoire ; le chaînage
// FAT multi-cluster est une amélioration ultérieure).
//
// Le listing est exposé par un port de lecture indexé (q_idx -> q_name/q_size/
// q_clus/q_isdsk), pour l'OSD et le chargement.

module fat32 #(
    parameter MAXFILES  = 32,
    parameter DIRSECS   = 8      // secteurs de répertoire racine balayés
) (
    input             clk,
    input             rst,
    input             start,          // pulse : lancer le parsing

    // Interface pilote de secteur (sd_spi)
    output reg        rd_start,
    output reg [31:0] rd_sector,
    input             sd_ready,
    input             sd_busy,
    input             sd_dvalid,
    input      [7:0]  sd_data,

    // Résultat
    output reg        done,
    output reg        error,
    output reg [7:0]  file_count,
    output reg [7:0]  status,

    // Port de lecture du listing
    input      [5:0]  q_idx,
    output     [87:0] q_name,          // 11 octets (nom 8.3)
    output     [31:0] q_size,
    output     [31:0] q_clus,
    output            q_isdsk,

    // 2e port de lecture (OSD HDMI)
    input      [5:0]  q2_idx,
    output     [87:0] q2_name,

    // 3e port de lecture (OSD de la console déportée)
    input      [5:0]  q3_idx,
    output     [87:0] q3_name,

    // 4e port de lecture (localisation de SAVE.TAP par le top, US-CSAVE.3 ph.B)
    input      [5:0]  q4_idx,
    output     [87:0] q4_name,

    // Lecture de fichier (streaming octet par octet, avec contrôle de flux)
    input             open_start,    // pulse : ouvrir le fichier open_idx
    input      [5:0]  open_idx,
    input      [31:0] open_offset,   // position de départ dans le fichier
                                     // (saut de chaîne de clusters — 0 pour
                                     // un streaming depuis le début)
    input             open_abort,    // pulse : clore la lecture en cours
                                     // (accepté en FO_EMIT uniquement)
    input             fdata_ready,   // niveau : le consommateur peut prendre un octet
    output reg        floading,
    output reg        feof,
    output reg [7:0]  fdata,
    output reg        fdata_valid,   // niveau : tenu jusqu'à l'acceptation ;
                                     // transfert au cycle où valid ET ready sont hauts

    // Écriture d'un bloc (US-DISK.5) : écrit 512 octets à wblk_offset (aligné
    // 512) du fichier wblk_idx. Suit la chaîne de clusters jusqu'au bloc, puis
    // CMD24. La source fournit wblk_data pour la position wblk_pos (= wr_idx SD).
    input             wblk_start,     // pulse : lancer l'écriture
    input      [5:0]  wblk_idx,
    input      [31:0] wblk_offset,
    input      [7:0]  wblk_data,      // octet à la position wblk_pos
    output     [8:0]  wblk_pos,       // = index SD courant (0..511)
    output reg        wblk_done,
    output reg        wblk_error,
    // vers sd_spi (écriture)
    output reg        wr_start,       // -> sd_spi.start_write
    output     [7:0]  wr_data,        // -> sd_spi.wr_data
    input      [8:0]  wr_idx          // <- sd_spi.wr_idx
);
    assign wr_data  = wblk_data;      // passthrough source -> sd_spi
    assign wblk_pos = wr_idx;
    // Mémoires de listing
    reg [87:0] name_mem [0:MAXFILES-1];
    reg [31:0] size_mem [0:MAXFILES-1];
    reg [31:0] clus_mem [0:MAXFILES-1];
    reg        dsk_mem  [0:MAXFILES-1];
    assign q_name   = name_mem[q_idx];
    assign q2_name  = name_mem[q2_idx];
    assign q3_name  = name_mem[q3_idx];
    assign q4_name  = name_mem[q4_idx];
    assign q_size   = size_mem[q_idx];
    assign q_clus   = clus_mem[q_idx];
    assign q_isdsk  = dsk_mem[q_idx];

    // Champs BPB
    reg [7:0]  jump0;
    reg [7:0]  spc;
    reg [15:0] reserved;
    reg [7:0]  nfat;
    reg [31:0] fatsz;
    reg [31:0] root_clus;
    reg [31:0] part_lba;
    reg [31:0] first_data, root_lba, fat_lba;

    // Lecture de fichier. Buffer secteur forcé en logique (registres) : lecture
    // combinatoire garantie, sans le décalage d'une BRAM à lecture synchrone.
    (* ram_style = "logic" *) (* ramstyle = "logic" *) reg [7:0] secbuf [0:511];
    reg [31:0] cur_clus, bytes_left, next_clus;
    reg [8:0]  rdpos;
    reg [7:0]  sec_in_clus;

    // Seek (open_offset) : saut de clusters puis positionnement fin
    reg [31:0] skip_rem;             // octets restant à sauter
    reg        skipping;             // le suivi de chaîne courant est un saut
    // Seek incrémental (US-SD-SPEED) : cur_base = offset fichier du début du
    // cluster courant. Une réouverture du même fichier à un offset en aval
    // repart de cur_clus au lieu de re-suivre la chaîne depuis le début
    // (chargement de pistes .dsk successives en O(1)).
    reg [31:0] cur_base;
    reg [5:0]  cache_idx;
    reg        cache_valid;
    reg [8:0]  rd_init;              // offset octet dans le 1er secteur lu
    reg        rd_init_pend;
    reg        abort_pend;           // open_abort mémorisé (l'impulsion peut
                                     // tomber pendant une transaction SD —
                                     // ex. franchissement de cluster pile en
                                     // fin de stream)
    wire [31:0] clus_bytes = {15'd0, spc, 9'd0};   // spc × 512

    // Entrée de répertoire en cours
    reg [7:0]  ntmp [0:10];
    reg [7:0]  eattr;
    reg [31:0] eclus, esize;

    localparam S_IDLE=0, S_RD0_R=1, S_RD0_C=2, S_BPB_R=3, S_BPB_C=4,
               S_CALC=5, S_DIR_R=6, S_DIR_C=7, S_DONE=8, S_ERR=9,
               FO_INIT=10, FO_RD=11, FO_CAP=12, FO_EMIT=13,
               FO_FAT=14, FO_FATC=15, FO_EOF=16,
               // écriture d'un bloc à un offset
               WB_SKIP=17, WB_FAT=18, WB_FATC=19, WB_WR=20, WB_BUSY=21;
    reg [4:0]  state;
    reg [31:0] wb_clus, wb_skip;     // suivi de chaîne pour l'écriture
    reg [7:0]  wb_sic;               // bloc dans le cluster
    reg [9:0]  bidx;                 // 0..511 octet dans le secteur
    reg [3:0]  dirsec;               // secteur de répertoire courant (0..DIRSECS-1)
    reg        stop_dir;             // fin de répertoire (entrée 0x00) rencontrée

    wire [4:0] eoff = bidx[4:0];     // offset dans l'entrée (0..31)
    wire       ext_tap = (ntmp[8]=="T") && (ntmp[9]=="A") && (ntmp[10]=="P");
    wire       ext_dsk = (ntmp[8]=="D") && (ntmp[9]=="S") && (ntmp[10]=="K");

    integer k;

    always @(posedge clk) begin
        rd_start  <= 1'b0;
        wr_start  <= 1'b0;
        wblk_done <= 1'b0;
        if (rst) begin
            fdata_valid <= 1'b0;
            state <= S_IDLE; done <= 0; error <= 0; file_count <= 0;
            status <= 8'h00; rd_sector <= 0; bidx <= 0; dirsec <= 0; stop_dir <= 0;
            floading <= 0; feof <= 0; cache_valid <= 1'b0; wblk_error <= 1'b0;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    done <= 0; error <= 0; file_count <= 0; stop_dir <= 0;
                    cache_valid <= 1'b0;    // re-listing : cluster caché caduc
                    status <= 8'h10; state <= S_RD0_R;
                end

                // ---- lire secteur 0 (MBR ou BPB) ----
                S_RD0_R: if (sd_ready && !sd_busy) begin
                    rd_sector <= 32'd0; rd_start <= 1'b1; bidx <= 0; state <= S_RD0_C;
                end
                S_RD0_C: if (sd_dvalid) begin
                    if (bidx==0)   jump0        <= sd_data;
                    if (bidx==13)  spc          <= sd_data;
                    if (bidx==14)  reserved[7:0] <= sd_data;
                    if (bidx==15)  reserved[15:8]<= sd_data;
                    if (bidx==16)  nfat         <= sd_data;
                    if (bidx==36)  fatsz[7:0]    <= sd_data;
                    if (bidx==37)  fatsz[15:8]   <= sd_data;
                    if (bidx==38)  fatsz[23:16]  <= sd_data;
                    if (bidx==39)  fatsz[31:24]  <= sd_data;
                    if (bidx==44)  root_clus[7:0]   <= sd_data;
                    if (bidx==45)  root_clus[15:8]  <= sd_data;
                    if (bidx==46)  root_clus[23:16] <= sd_data;
                    if (bidx==47)  root_clus[31:24] <= sd_data;
                    // entrée de partition MBR n°1 : LBA de début (offset 454..457)
                    if (bidx==454) part_lba[7:0]    <= sd_data;
                    if (bidx==455) part_lba[15:8]   <= sd_data;
                    if (bidx==456) part_lba[23:16]  <= sd_data;
                    if (bidx==457) part_lba[31:24]  <= sd_data;
                    if (bidx==511) begin
                        if (jump0==8'hEB || jump0==8'hE9) begin
                            part_lba <= 32'd0; status <= 8'h12; state <= S_CALC;  // superfloppy
                        end else begin
                            status <= 8'h13; state <= S_BPB_R;                    // MBR
                        end
                    end else bidx <= bidx + 10'd1;
                end

                // ---- lire le BPB à part_lba (cas MBR) ----
                S_BPB_R: if (sd_ready && !sd_busy) begin
                    rd_sector <= part_lba; rd_start <= 1'b1; bidx <= 0; state <= S_BPB_C;
                end
                S_BPB_C: if (sd_dvalid) begin
                    if (bidx==13)  spc          <= sd_data;
                    if (bidx==14)  reserved[7:0] <= sd_data;
                    if (bidx==15)  reserved[15:8]<= sd_data;
                    if (bidx==16)  nfat         <= sd_data;
                    if (bidx==36)  fatsz[7:0]    <= sd_data;
                    if (bidx==37)  fatsz[15:8]   <= sd_data;
                    if (bidx==38)  fatsz[23:16]  <= sd_data;
                    if (bidx==39)  fatsz[31:24]  <= sd_data;
                    if (bidx==44)  root_clus[7:0]   <= sd_data;
                    if (bidx==45)  root_clus[15:8]  <= sd_data;
                    if (bidx==46)  root_clus[23:16] <= sd_data;
                    if (bidx==47)  root_clus[31:24] <= sd_data;
                    if (bidx==511) begin status <= 8'h14; state <= S_CALC; end
                    else bidx <= bidx + 10'd1;
                end

                // ---- calcul des LBA ----
                S_CALC: begin
                    fat_lba    <= part_lba + reserved;
                    first_data <= part_lba + reserved + nfat*fatsz;
                    root_lba   <= part_lba + reserved + nfat*fatsz
                                  + (root_clus - 32'd2) * spc;
                    dirsec <= 0; status <= 8'h20; state <= S_DIR_R;
                end

                // ---- lire et parser le répertoire racine ----
                S_DIR_R: if (sd_ready && !sd_busy) begin
                    rd_sector <= root_lba + dirsec; rd_start <= 1'b1;
                    bidx <= 0; state <= S_DIR_C;
                end
                S_DIR_C: if (sd_dvalid) begin
                    // capture des champs de l'entrée courante (little-endian)
                    if (eoff <= 5'd10) ntmp[eoff] <= sd_data;
                    if (eoff == 5'd11) eattr <= sd_data;
                    if (eoff == 5'd20) eclus[23:16] <= sd_data;   // cluster high, LSB
                    if (eoff == 5'd21) eclus[31:24] <= sd_data;   // cluster high, MSB
                    if (eoff == 5'd26) eclus[7:0]   <= sd_data;   // cluster low, LSB
                    if (eoff == 5'd27) eclus[15:8]  <= sd_data;   // cluster low, MSB
                    if (eoff == 5'd28) esize[7:0]   <= sd_data;
                    if (eoff == 5'd29) esize[15:8]  <= sd_data;
                    if (eoff == 5'd30) esize[23:16] <= sd_data;
                    if (eoff == 5'd31) begin
                        // fin d'entrée (octet 31 = size MSB dans sd_data) : décider
                        if (ntmp[0]==8'h00) stop_dir <= 1'b1;                 // fin répertoire
                        else if (ntmp[0]!=8'hE5 && eattr!=8'h0F
                                 && (eattr & 8'h18)==8'h00
                                 && (ext_tap || ext_dsk)
                                 && file_count < MAXFILES) begin
                            name_mem[file_count] <= {ntmp[0],ntmp[1],ntmp[2],ntmp[3],
                                ntmp[4],ntmp[5],ntmp[6],ntmp[7],ntmp[8],ntmp[9],ntmp[10]};
                            size_mem[file_count] <= {sd_data, esize[23:0]};
                            clus_mem[file_count] <= eclus;
                            dsk_mem[file_count]  <= ext_dsk;
                            file_count <= file_count + 8'd1;
                        end
                    end
                    if (bidx==511) begin
                        if (stop_dir || dirsec==DIRSECS-1) begin
                            status <= 8'h80; state <= S_DONE;
                        end else begin dirsec <= dirsec + 4'd1; state <= S_DIR_R; end
                    end else bidx <= bidx + 10'd1;
                end

                S_DONE: begin
                    done <= 1'b1; feof <= 1'b0;
                    if (wblk_start) begin           // écriture d'un bloc à un offset
                        wb_clus <= clus_mem[wblk_idx];
                        wb_skip <= wblk_offset;
                        wblk_error <= 1'b0;
                        state <= WB_SKIP;
                    end else if (open_start) begin
                        // au-delà de la fin : EOF immédiat (bytes_left = 0)
                        bytes_left <= (open_offset < size_mem[open_idx])
                                      ? size_mem[open_idx] - open_offset : 32'd0;
                        if (cache_valid && open_idx == cache_idx &&
                            open_offset >= cur_base) begin
                            // même fichier, offset en aval : repartir du
                            // cluster courant (seek incrémental)
                            skip_rem <= open_offset - cur_base;
                        end else begin
                            cur_clus <= clus_mem[open_idx];
                            cur_base <= 32'd0;
                            skip_rem <= open_offset;
                        end
                        cache_idx   <= open_idx;
                        cache_valid <= 1'b1;
                        skipping   <= 1'b0;
                        rd_init_pend <= 1'b0;
                        abort_pend <= 1'b0;
                        sec_in_clus <= 8'd0;
                        floading <= 1'b1; feof <= 1'b0; fdata_valid <= 1'b0;
                        state <= FO_INIT;
                    end
                end

                // ---- ouverture : sauter les clusters du seek puis lire ----
                FO_INIT: begin
                    if (bytes_left == 32'd0) begin
                        floading <= 1'b0; feof <= 1'b1; state <= FO_EOF;
                    end else if (skip_rem >= clus_bytes) begin
                        skipping <= 1'b1;           // sauter ce cluster
                        state <= FO_FAT;
                    end else begin
                        sec_in_clus  <= skip_rem[16:9];   // secteur dans le cluster
                        rd_init      <= skip_rem[8:0];    // octet dans le secteur
                        rd_init_pend <= 1'b1;
                        state <= FO_RD;
                    end
                end

                // ---- lire un secteur de données du cluster courant ----
                FO_RD: if (open_abort || abort_pend) begin
                    abort_pend <= 1'b0; fdata_valid <= 1'b0;
                    floading <= 1'b0; feof <= 1'b0; state <= S_DONE;
                end else if (sd_ready && !sd_busy) begin status <= 8'h91;   // lecture données
                    rd_sector <= first_data + (cur_clus - 32'd2) * spc + sec_in_clus;
                    rd_start <= 1'b1; bidx <= 0; state <= FO_CAP;
                end
                FO_CAP: begin
                    if (open_abort) abort_pend <= 1'b1;
                    if (sd_dvalid) begin status <= 8'h92;   // réception données
                    secbuf[bidx] <= sd_data;
                    if (bidx == 511) begin
                        rdpos <= rd_init_pend ? rd_init : 9'd0;  // seek fin
                        rd_init_pend <= 1'b0;
                        state <= FO_EMIT;
                    end else bidx <= bidx + 10'd1;
                    end
                end

                // ---- débiter les octets vers le consommateur ----
                // Handshake valid/ready : l'octet est présenté (valid tenu haut)
                // et n'est consommé qu'au cycle où valid ET ready sont hauts —
                // exactement un octet par transfert, quel que soit le nombre de
                // cycles où le consommateur laisse ready haut.
                FO_EMIT: begin
                    status <= 8'h93;                 // débit (attend crédits)
                    if (open_abort || abort_pend) begin  // clôture par le client
                        abort_pend <= 1'b0;
                        fdata_valid <= 1'b0;
                        floading <= 1'b0; feof <= 1'b0;
                        state <= S_DONE;
                    end else if (!fdata_valid) begin
                        if (bytes_left == 32'd0) begin
                            floading <= 1'b0; feof <= 1'b1; state <= FO_EOF;
                        end else begin
                            fdata <= secbuf[rdpos];
                            fdata_valid <= 1'b1;
                        end
                    end else if (fdata_ready) begin
                        // transfert accepté ce cycle
                        fdata_valid <= 1'b0;
                        bytes_left <= bytes_left - 32'd1;
                        if (rdpos == 9'd511) begin
                            // secteur épuisé : suivant dans le cluster ou chaîne FAT
                            if (sec_in_clus + 8'd1 < spc) begin
                                sec_in_clus <= sec_in_clus + 8'd1; state <= FO_RD;
                            end else state <= FO_FAT;
                        end else rdpos <= rdpos + 9'd1;
                    end
                end

                // ---- suivre la chaîne FAT : cluster suivant ----
                FO_FAT: if (open_abort || abort_pend) begin
                    abort_pend <= 1'b0; fdata_valid <= 1'b0;
                    floading <= 1'b0; feof <= 1'b0; state <= S_DONE;
                end else if (sd_ready && !sd_busy) begin
                    status <= 8'h94;                          // suivi chaîne FAT
                    rd_sector <= fat_lba + (cur_clus >> 7);   // 128 entrées/secteur
                    rd_start <= 1'b1; bidx <= 0; state <= FO_FATC;
                end
                FO_FATC: begin
                    if (open_abort) abort_pend <= 1'b1;
                    if (sd_dvalid) begin
                    // entrée FAT de cur_clus à l'offset (cur_clus%128)*4
                    if (bidx[8:0] == {cur_clus[6:0], 2'd0})       next_clus[7:0]   <= sd_data;
                    if (bidx[8:0] == {cur_clus[6:0], 2'd0} + 9'd1) next_clus[15:8]  <= sd_data;
                    if (bidx[8:0] == {cur_clus[6:0], 2'd0} + 9'd2) next_clus[23:16] <= sd_data;
                    if (bidx[8:0] == {cur_clus[6:0], 2'd0} + 9'd3) next_clus[31:24] <= sd_data;
                    if (bidx == 511) begin
                        if ((next_clus & 32'h0FFFFFFF) >= 32'h0FFFFFF8) begin
                            floading <= 1'b0; feof <= 1'b1; state <= FO_EOF;
                        end else if (skipping) begin
                            // saut de cluster (seek) : avancer et re-tester
                            cur_clus <= next_clus & 32'h0FFFFFFF;
                            cur_base <= cur_base + clus_bytes;
                            skip_rem <= skip_rem - clus_bytes;
                            skipping <= 1'b0;
                            state <= FO_INIT;
                        end else begin
                            cur_clus <= next_clus & 32'h0FFFFFFF;
                            cur_base <= cur_base + clus_bytes;
                            sec_in_clus <= 8'd0; state <= FO_RD;
                        end
                    end else bidx <= bidx + 10'd1;
                    end
                end

                FO_EOF: begin floading <= 1'b0; feof <= 1'b1; state <= S_DONE; end

                // ---- écriture d'un bloc : suivre la chaîne jusqu'à l'offset ----
                WB_SKIP: if (wb_skip >= clus_bytes) begin
                             wb_skip <= wb_skip - clus_bytes;   // sauter ce cluster
                             state <= WB_FAT;
                         end else begin
                             wb_sic <= wb_skip[16:9];           // bloc dans le cluster
                             state <= WB_WR;
                         end
                WB_FAT: if (sd_ready && !sd_busy) begin
                            rd_sector <= fat_lba + (wb_clus >> 7);
                            rd_start <= 1'b1; bidx <= 0; state <= WB_FATC;
                        end
                WB_FATC: if (sd_dvalid) begin
                            if (bidx[8:0] == {wb_clus[6:0], 2'd0})       next_clus[7:0]   <= sd_data;
                            if (bidx[8:0] == {wb_clus[6:0], 2'd0} + 9'd1) next_clus[15:8]  <= sd_data;
                            if (bidx[8:0] == {wb_clus[6:0], 2'd0} + 9'd2) next_clus[23:16] <= sd_data;
                            if (bidx[8:0] == {wb_clus[6:0], 2'd0} + 9'd3) next_clus[31:24] <= sd_data;
                            if (bidx == 511) begin
                                if ((next_clus & 32'h0FFFFFFF) >= 32'h0FFFFFF8) begin
                                    wblk_error <= 1'b1; wblk_done <= 1'b1; state <= S_DONE;
                                end else begin
                                    wb_clus <= next_clus & 32'h0FFFFFFF; state <= WB_SKIP;
                                end
                            end else bidx <= bidx + 10'd1;
                        end
                WB_WR: if (sd_ready && !sd_busy) begin
                            rd_sector <= first_data + (wb_clus - 32'd2) * spc + wb_sic;
                            wr_start <= 1'b1; state <= WB_BUSY;
                        end
                WB_BUSY: if (sd_ready && !sd_busy && !wr_start) begin  // écriture finie
                            wblk_done <= 1'b1; state <= S_DONE;
                         end

                S_ERR:  begin error <= 1'b1; end
                default: state <= S_ERR;
            endcase
        end
    end

endmodule
