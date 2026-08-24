// Test e2e de la VRAIE création FAT32 d'une sauvegarde cassette (US-CSAVE.4 D2).
// Chaîne complète : tape_injector -> tape_demod -> {tape_creator, tape_saver}
// -> fat32 -> sd_card_file. L'injecteur joue un flux CSAVE réaliste (amorce +
// marqueur 0x24 + 9 o d'en-tête + nom "TESTPROG" + 0x00 + 600 o de données).
// Le creator EXTRAIT le nom, ALLOUE un cluster, CRÉE l'entrée de répertoire,
// puis le saver écrit (avec extension de chaîne) ; à la fin la TAILLE est
// inscrite. On RE-PARSE l'image : le fichier "TESTPROGTAP" doit exister avec la
// bonne taille et un contenu identique au flux décodé.
`timescale 1ns/1ps

module tb_tape_create;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;

    localparam CH1 = 4, CHL = 8, LEAD = 4;
    localparam THRESH = (2*CH1 + (CH1+CHL)) / 2;
    localparam GAP    = 400;
    localparam NDATA  = 600;                 // données utiles (> 512 -> extension)
    localparam FLEN   = 1 + 9 + 8 + 1 + NDATA;   // marqueur+en-tête+nom+0+data
    localparam TOTAL  = LEAD + FLEN;             // flux décodé complet

    // ---- injecteur ----
    reg  [7:0] rx_data = 0;
    reg        rx_valid = 0;
    wire [7:0] tx_data;
    wire       tx_send, tape_line, tape_active;
    tape_injector #(.CYC_HALF_ONE(CH1), .CYC_HALF_LONG(CHL), .LEADER_SYNCS(LEAD),
                    .INTER_SYNCS(0)) inj (   // pas de ré-insertion d'amorce (flux propre)
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
    reg         open_start = 0, open_abort = 0;
    reg  [5:0]  open_idx = 0;
    reg  [31:0] open_offset = 0;
    reg         fdata_ready = 0;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;
    reg  [5:0]  q_idx = 0;
    wire [87:0] q_name;
    wire [31:0] q_size;

    // creator -> fat32
    wire        alloc_start, mkent_start, dsize_start;
    wire [31:0] alloc_prev, mkent_clus, mkent_size, dsize_val;
    wire [87:0] mkent_name;
    wire [5:0]  mkent_idx_w, dsize_idx;
    wire [31:0] alloc_clus;
    wire        alloc_done, alloc_error, mkent_done, mkent_error, dsize_done;
    // saver -> fat32
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
        .q_idx(q_idx), .q_name(q_name), .q_size(q_size), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(), .q3_idx(6'd0), .q3_name(), .q4_idx(6'd0), .q4_name(),
        .open_start(open_start), .open_idx(open_idx),
        .open_offset(open_offset), .open_abort(open_abort),
        .fdata_ready(fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(wblk_start), .wblk_idx(wblk_idx), .wblk_offset(wblk_offset),
        .wblk_data(wblk_data), .wblk_extend(1'b1), .wblk_pos(wblk_pos),
        .wblk_done(wblk_done), .wblk_error(wblk_error),
        .dsize_start(dsize_start), .dsize_idx(dsize_idx), .dsize_val(dsize_val),
        .dsize_done(dsize_done), .dsize_error(),
        .alloc_start(alloc_start), .alloc_prev(alloc_prev),
        .alloc_clus(alloc_clus), .alloc_done(alloc_done), .alloc_error(alloc_error),
        .mkent_start(mkent_start), .mkent_name(mkent_name),
        .mkent_clus(mkent_clus), .mkent_size(mkent_size),
        .mkent_idx(mkent_idx_w), .mkent_done(mkent_done), .mkent_error(mkent_error),
        .wr_start(wr_start), .wr_data(wr_data), .wr_idx(sd_wr_idx)
    );

    // ---- creator ----
    wire       cr_busy;
    wire       sav_busy, sav_done, sav_error;
    wire [31:0] sav_nbytes;
    wire [5:0] file_idx;
    wire       file_ready;
    tape_creator creator (
        .clk(clk), .rst(rst),
        .byte_in(dbyte), .byte_valid(dvalid), .capturing(capturing),
        .alloc_start(alloc_start), .alloc_prev(alloc_prev),
        .alloc_clus(alloc_clus), .alloc_done(alloc_done), .alloc_error(alloc_error),
        .mkent_start(mkent_start), .mkent_name(mkent_name),
        .mkent_clus(mkent_clus), .mkent_size(mkent_size),
        .mkent_idx(mkent_idx_w), .mkent_done(mkent_done), .mkent_error(mkent_error),
        .dsize_start(dsize_start), .dsize_idx(dsize_idx), .dsize_val(dsize_val),
        .dsize_done(dsize_done),
        .sav_done(sav_done), .sav_nbytes(sav_nbytes),
        .file_idx(file_idx), .file_ready(file_ready), .busy(cr_busy)
    );

    // ---- saver ----
    tape_saver saver (
        .clk(clk), .rst(rst),
        .byte_in(dbyte), .byte_valid(dvalid), .capturing(capturing),
        .file_idx(file_idx), .enable(1'b1), .file_ready(file_ready),
        .wblk_start(wblk_start), .wblk_idx(wblk_idx), .wblk_offset(wblk_offset),
        .wblk_data(wblk_data), .wblk_pos(wblk_pos),
        .wblk_done(wblk_done), .wblk_error(wblk_error),
        .busy(sav_busy), .done(sav_done), .error(sav_error), .nbytes(sav_nbytes)
    );

    // ---- crédits ----
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

    reg [7:0] flow [0:FLEN-1];
    integer errors = 0, i, rp, found;
    reg [7:0] rdbuf [0:2047];
    localparam [87:0] NM = "TESTPROGTAP";

    // Capture du flux décodé réellement sauvegardé (indépendant du modèle exact
    // injecteur/démod) : ce que le saver écrit doit se relire à l'identique.
    reg [7:0] cap [0:2047];
    integer   ccnt = 0;
    always @(posedge clk)
        if (!rst && dvalid && capturing && ccnt < 2048) begin
            cap[ccnt] = dbyte; ccnt = ccnt + 1;
        end

    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    initial begin
        // --- construit le flux CSAVE : marqueur + en-tête (end/start cohérents
        //     avec NDATA) + nom + data ---
        flow[0] = 8'h24;
        for (i = 0; i < 9; i = i + 1) flow[1+i] = 8'h00;      // 9 o d'en-tête
        flow[5] = (NDATA-1) >> 8;  flow[6] = (NDATA-1) & 8'hFF;   // end addr
        flow[7] = 8'h00;           flow[8] = 8'h00;               // start addr = 0
        flow[10] = "T"; flow[11] = "E"; flow[12] = "S"; flow[13] = "T";
        flow[14] = "P"; flow[15] = "R"; flow[16] = "O"; flow[17] = "G";
        flow[18] = 8'h00;                                     // fin de nom
        for (i = 0; i < NDATA; i = i + 1) flow[19+i] = 8'h80 | (i & 6'h3F);

        repeat (8) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("fat: %0d fichier(s)", file_count);

        // --- jouer le flux (un octet par crédit) ---
        send_byte(8'h01); send_byte(FLEN[7:0]); send_byte(FLEN[15:8]);
        for (i = 0; i < FLEN; i = i + 1) begin
            wait (credit_cnt > i);
            send_byte(flow[i]);
        end

        // --- fin de bande + clôture saver + création finalisée (dsize) ---
        wait (tape_active == 1'b0);
        wait (sav_done === 1'b1);
        $display("saver : %0d octets sauvegardes ; flux capture : %0d", sav_nbytes, ccnt);
        check(sav_error == 1'b0, "saver sans erreur");
        check(sav_nbytes == ccnt, "nbytes == flux decode capture");
        wait (cr_busy === 1'b0);                 // dsize terminé, creator au repos

        // --- RE-PARSE : le fichier créé doit exister ---
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("re-parse : %0d fichier(s)", file_count);
        found = -1;
        for (i = 0; i < file_count; i = i + 1) begin
            q_idx = i[5:0]; @(negedge clk); @(negedge clk);
            if (q_name === NM) found = i;
        end
        check(found >= 0, "fichier TESTPROGTAP present");

        if (found >= 0) begin
            q_idx = found[5:0]; @(negedge clk); @(negedge clk);
            $display("trouve idx=%0d taille=%0d (flux %0d)", found, q_size, ccnt);
            check(q_size === ccnt, "taille = flux capture");

            // --- relire tout le contenu et comparer au flux capturé ---
            open_idx = found[5:0]; open_offset = 0;
            @(negedge clk); open_start = 1; @(negedge clk); open_start = 0;
            rp = 0;
            while (rp < ccnt && !feof) begin
                fdata_ready = 1; @(negedge clk);
                if (fdata_valid) begin rdbuf[rp] = fdata; rp = rp + 1; end
            end
            fdata_ready = 0;
            check(rp == ccnt, "contenu relu complet");
            for (i = 0; i < ccnt; i = i + 1)
                if (rdbuf[i] !== cap[i] && errors < 12) begin
                    $display("FAIL: octet %0d : relu %02x capture %02x", i, rdbuf[i], cap[i]);
                    errors = errors + 1;
                end
        end

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape_create)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #4000000000; $display("TIMEOUT"); $finish; end
endmodule
