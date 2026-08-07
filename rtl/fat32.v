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
    output            q_isdsk
);
    // Mémoires de listing
    reg [87:0] name_mem [0:MAXFILES-1];
    reg [31:0] size_mem [0:MAXFILES-1];
    reg [31:0] clus_mem [0:MAXFILES-1];
    reg        dsk_mem  [0:MAXFILES-1];
    assign q_name   = name_mem[q_idx];
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
    reg [31:0] first_data, root_lba;

    // Entrée de répertoire en cours
    reg [7:0]  ntmp [0:10];
    reg [7:0]  eattr;
    reg [31:0] eclus, esize;

    localparam S_IDLE=0, S_RD0_R=1, S_RD0_C=2, S_BPB_R=3, S_BPB_C=4,
               S_CALC=5, S_DIR_R=6, S_DIR_C=7, S_DONE=8, S_ERR=9;
    reg [3:0]  state;
    reg [9:0]  bidx;                 // 0..511 octet dans le secteur
    reg [3:0]  dirsec;               // secteur de répertoire courant (0..DIRSECS-1)
    reg        stop_dir;             // fin de répertoire (entrée 0x00) rencontrée

    wire [4:0] eoff = bidx[4:0];     // offset dans l'entrée (0..31)
    wire       ext_tap = (ntmp[8]=="T") && (ntmp[9]=="A") && (ntmp[10]=="P");
    wire       ext_dsk = (ntmp[8]=="D") && (ntmp[9]=="S") && (ntmp[10]=="K");

    integer k;

    always @(posedge clk) begin
        rd_start <= 1'b0;
        if (rst) begin
            state <= S_IDLE; done <= 0; error <= 0; file_count <= 0;
            status <= 8'h00; rd_sector <= 0; bidx <= 0; dirsec <= 0; stop_dir <= 0;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    done <= 0; error <= 0; file_count <= 0; stop_dir <= 0;
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

                S_DONE: begin done <= 1'b1; end
                S_ERR:  begin error <= 1'b1; end
                default: state <= S_ERR;
            endcase
        end
    end

endmodule
