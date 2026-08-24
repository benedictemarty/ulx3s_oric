// Test sauvegarde cassette -> carte SD (US-CSAVE.3) : chaîne complète
//   tape_injector -> tape_demod -> tape_saver -> fat32.wblk -> sd_card_file.
// L'injecteur joue une forme d'onde CSAVE (amorce + charge > 512 o pour
// exercer le ping-pong et l'écriture multi-blocs), le démod la reconstruit en
// octets, le saver les écrit dans le placeholder SAVE.TAP de l'image FAT. On
// relit ensuite SAVE.TAP par le chemin de lecture fat32 et on vérifie :
//   bloc 0 = amorce 0x16 + données ; fin du dernier bloc = padding 0x00.
`timescale 1ns/1ps

module tb_tape_saver;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;

    // Durées cassette réduites (comme tb_tape_demod).
    localparam CH1 = 4, CHL = 8, LEAD = 4;
    localparam THRESH = (2*CH1 + (CH1+CHL)) / 2;   // seuil '1'/'0'
    localparam GAP    = 400;                        // silence fin de capture

    localparam SAVE_IDX = 6'd7;                     // SAVE.TAP (README.TXT filtré -> idx 7)
    localparam NDATA    = 600;                      // > 512 -> 2 blocs

    // ---- injecteur (rôle PC + forme d'onde) ----
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0;
    wire [7:0] tx_data;
    wire       tx_send, tape_line, tape_active;
    tape_injector #(.CYC_HALF_ONE(CH1), .CYC_HALF_LONG(CHL), .LEADER_SYNCS(LEAD)) inj (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_send(tx_send), .tx_busy(1'b0),
        .turbo(1'b0), .motor(1'b1), .tape_line(tape_line), .tape_active(tape_active)
    );

    // ---- démodulateur ----
    wire [7:0] dbyte;
    wire       dvalid, capturing;
    tape_demod #(.CYC_THRESH(THRESH), .GAP_CYCLES(GAP)) demod (
        .clk(clk), .rst(rst), .tape_out(tape_line),
        .byte_out(dbyte), .byte_valid(dvalid), .capturing(capturing)
    );

    // ---- SD + fat32 ----
    wire        rd_start, wr_start;
    wire [31:0] rd_sector;
    wire [7:0]  wr_data;
    wire [8:0]  sd_wr_idx;
    wire        sd_ready, sd_busy, sd_dvalid, sd_error;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;
    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start),
        .start_write(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx),
        .sector(rd_sector),
        .ready(sd_ready), .busy(sd_busy), .error(sd_error),
        .data(sd_data), .data_valid(sd_dvalid), .status(sd_status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );
    sd_card_file #(.IMG("sim/out/fat_test.img")) card (
        .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso)
    );

    reg         fat_start = 0;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    // lecture (relecture de contrôle)
    reg         open_start = 0;
    reg         open_abort = 0;
    reg  [5:0]  open_idx = 0;
    reg  [31:0] open_offset = 0;
    reg         fdata_ready = 0;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;
    // maj taille entrée répertoire (refinement)
    reg         dsize_start = 0;
    reg  [5:0]  dsize_idx = 0;
    reg  [31:0] dsize_val = 0;
    wire        dsize_done, dsize_error;
    reg  [5:0]  q_idx = 0;
    wire [31:0] q_size;
    // écriture (pilotée par le saver)
    wire        wblk_start;
    wire [5:0]  wblk_idx;
    wire [31:0] wblk_offset;
    wire [7:0]  wblk_data;
    wire [8:0]  wblk_pos;
    wire        wblk_done, wblk_error;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(q_idx), .q_name(), .q_size(q_size), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(), .q3_idx(6'd0), .q3_name(),
        .q4_idx(6'd0), .q4_name(),
        .open_start(open_start), .open_idx(open_idx),
        .open_offset(open_offset), .open_abort(open_abort),
        .fdata_ready(fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(wblk_start), .wblk_idx(wblk_idx), .wblk_offset(wblk_offset),
        .wblk_data(wblk_data), .wblk_pos(wblk_pos),
        .wblk_done(wblk_done), .wblk_error(wblk_error),
        .dsize_start(dsize_start), .dsize_idx(dsize_idx), .dsize_val(dsize_val),
        .dsize_done(dsize_done), .dsize_error(dsize_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    // ---- saver ----
    wire       sav_busy, sav_done, sav_error;
    wire [31:0] sav_nbytes;
    tape_saver saver (
        .clk(clk), .rst(rst),
        .byte_in(dbyte), .byte_valid(dvalid), .capturing(capturing),
        .file_idx(SAVE_IDX), .enable(1'b1), .file_ready(1'b1),
        .wblk_start(wblk_start), .wblk_idx(wblk_idx), .wblk_offset(wblk_offset),
        .wblk_data(wblk_data), .wblk_pos(wblk_pos),
        .wblk_done(wblk_done), .wblk_error(wblk_error),
        .busy(sav_busy), .done(sav_done), .error(sav_error), .nbytes(sav_nbytes)
    );

    // ---- crédits (cadence l'envoi PC) ----
    integer credit_cnt = 0;
    always @(posedge clk)
        if (!rst && tx_send && tx_data == 8'h5A) credit_cnt <= credit_cnt + 1;

    task send_byte(input [7:0] b);
        begin
            @(negedge clk); rx_data = b; rx_valid = 1;
            @(negedge clk); rx_valid = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    // ---- données envoyées (jamais 0x24 -> pas d'amorce inter-blocs parasite) ----
    reg [7:0] data_arr [0:NDATA-1];
    // attendu décodé : LEAD×0x16 puis les données
    reg [7:0] exp [0:1023];

    integer errors = 0, i, rp;
    reg [7:0] rdbuf [0:1023];
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    initial begin
        for (i = 0; i < NDATA; i = i + 1)
            data_arr[i] = 8'h80 | (i & 6'h3F);       // 0x80..0xBF
        for (i = 0; i < 1024; i = i + 1) begin
            if (i < LEAD)            exp[i] = 8'h16;
            else if (i < LEAD+NDATA) exp[i] = data_arr[i-LEAD];
            else                     exp[i] = 8'h00;  // padding du dernier bloc
        end

        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("fat: %0d fichier(s)", file_count);

        // --- CSAVE simulé : en-tête + NDATA octets, un par crédit ---
        send_byte(8'h01); send_byte(NDATA[7:0]); send_byte(NDATA[15:8]);
        for (i = 0; i < NDATA; i = i + 1) begin
            wait (credit_cnt > i);
            send_byte(data_arr[i]);
        end

        // --- laisser jouer la bande puis le saver conclure sur le silence ---
        wait (tape_active == 1'b0);
        wait (sav_done === 1'b1);
        $display("saver : %0d octets sauvegardes (attendu %0d)", sav_nbytes, LEAD+NDATA);
        check(sav_error == 1'b0, "saver sans erreur");
        check(sav_nbytes == LEAD + NDATA, "nbytes == amorce + donnees");

        // --- relecture des 2 premiers blocs de SAVE.TAP ---
        @(negedge clk);
        open_idx = SAVE_IDX; open_offset = 0;
        @(negedge clk); open_start = 1; @(negedge clk); open_start = 0;
        rp = 0;
        while (rp < 1024 && !feof) begin
            fdata_ready = 1;
            @(negedge clk);
            if (fdata_valid) begin rdbuf[rp] = fdata; rp = rp + 1; end
        end
        fdata_ready = 0;

        check(rp >= 1024, "1024 octets relus");
        for (i = 0; i < 1024; i = i + 1)
            if (rdbuf[i] !== exp[i] && errors < 12) begin
                $display("FAIL: octet %0d : relu %02x attendu %02x", i, rdbuf[i], exp[i]);
                errors = errors + 1;
            end

        // --- clore la lecture de contrôle (retour fat32 -> S_DONE) ---
        @(negedge clk); open_abort = 1; @(negedge clk); open_abort = 0;
        wait (floading === 1'b0);
        repeat (4) @(negedge clk);

        // --- refinement : maj de la taille de SAVE.TAP dans l'entrée répertoire ---
        @(negedge clk);
        dsize_idx = SAVE_IDX; dsize_val = LEAD + NDATA;   // 604
        @(negedge clk); dsize_start = 1; @(negedge clk); dsize_start = 0;
        wait (dsize_done === 1'b1);
        check(dsize_error == 1'b0, "maj taille sans erreur");
        @(negedge clk); q_idx = SAVE_IDX; #1;
        check(q_size === LEAD + NDATA, "q_size reflete la nouvelle taille");
        $display("taille SAVE.TAP apres maj : %0d (attendu %0d)", q_size, LEAD+NDATA);

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape_saver)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #2000000000; $display("TIMEOUT"); $finish; end
endmodule
