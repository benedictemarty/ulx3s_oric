// Testbench bout-en-bout disquette (US-DISK.3) : carte-image FAT32 ->
// sd_spi -> fat32 (avec seek) -> dsk_track (piste + scan MFM) -> microdisc
// (WD1793). Insère TESTMFM.DSK (1 face, 3 pistes, 17 secteurs, motif
// (t*32+s)^i) puis lit des secteurs via les registres du Microdisc :
// piste 0 sec 1, seek piste 2 (rechargement de piste pendant le délai
// mécanique) sec 5, RNF sec 18.
`timescale 1ns/1ps

module tb_dsk;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;
    reg [1:0] cdiv = 0;
    always @(posedge clk) cdiv <= cdiv + 2'd1;
    wire cen = (cdiv == 2'd3);

    // ---- Chaîne SD ----
    wire        rd_start;
    wire [31:0] rd_sector;
    wire        sd_ready, sd_busy, sd_dvalid, sd_error;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start), .sector(rd_sector),
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
    wire        d_open_start, d_open_abort, d_fdata_ready;
    wire [5:0]  d_open_idx;
    wire [31:0] d_open_offset;
    wire        floading, feof, fdata_valid;
    wire [7:0]  fdata;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd0), .q_name(), .q_size(), .q_clus(), .q_isdsk(),
        .q2_idx(6'd0), .q2_name(),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid)
    );

    // ---- Fournisseur de pistes ----
    reg        insert = 0, eject = 0;
    reg [5:0]  tb_fidx = 6'd5;
    wire       inserted, bad_format, trk_loading, disk_present;
    wire [6:0] n_tracks, req_track;
    wire [4:0] n_spt, sec_id;
    wire       req_side, sec_valid;
    wire [8:0] sec_addr;
    wire [7:0] sec_byte;

    dsk_track dsk (
        .clk(clk), .rst(rst),
        .soft_rst(1'b0),
        .insert(insert), .file_idx(tb_fidx), .eject(eject),
        .inserted(inserted), .bad_format(bad_format),
        .bus_grant(1'b1), .fat_done(fat_done),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready), .fdata_valid(fdata_valid),
        .fdata(fdata), .feof(feof),
        .req_track(req_track), .req_side(req_side),
        .trk_loading(trk_loading), .disk_present(disk_present),
        .n_tracks(n_tracks), .n_spt(n_spt),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte)
    );

    // ---- Microdisc (WD1793) — timings réduits ----
    reg         io_sel = 0, we = 0;
    reg  [15:0] a = 0;
    reg  [7:0]  din = 0;
    wire [7:0]  dout, eprom_dout;
    wire        dout_valid, romdis, eprom_sel, irq;

    microdisc #(.ROM_FILE("roms/microdis.hex"),
                .REV_CYCLES(2000), .INDEX_CYCLES(40),
                .SETTLE_CYCLES(100), .RNF_CYCLES(5000)) md (
        .clk(clk), .cen(cen), .rst(rst), .enable(1'b1),
        .a(a), .io_sel(io_sel), .we(we), .din(din),
        .dout(dout), .dout_valid(dout_valid),
        .romdis(romdis), .eprom_sel(eprom_sel), .eprom_dout(eprom_dout),
        .rom_a(a[13:0]), .irq(irq),
        .disk_present(disk_present), .n_tracks(n_tracks), .n_spt(n_spt),
        .req_track(req_track), .req_side(req_side), .trk_loading(trk_loading),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    task bus_op(input w, input [15:0] ad, input [7:0] v);
        begin
            @(negedge clk); while (cdiv != 2'd2) @(negedge clk);
            io_sel = 1; we = w; a = ad; din = v;
            @(negedge clk); @(negedge clk);
            io_sel = 0; we = 0;
        end
    endtask

    reg [7:0] rd;
    task bus_read(input [15:0] ad);
        begin
            @(negedge clk); while (cdiv != 2'd2) @(negedge clk);
            io_sel = 1; we = 0; a = ad;
            @(negedge clk); rd = dout;
            @(negedge clk); io_sel = 0;
        end
    endtask

    task wait_drq;   // via $0318 (bit 7 actif bas)
        integer n;
        begin
            n = 0; rd = 8'hFF;
            while (rd[7] && n < 2000000) begin bus_read(16'h0318); n = n + 1; end
            check(!rd[7], "DRQ attendu ($0318)");
        end
    endtask

    task wait_intrq; // via $0314
        integer n;
        begin
            n = 0; rd = 8'hFF;
            while (rd[7] && n < 2000000) begin bus_read(16'h0314); n = n + 1; end
            check(!rd[7], "INTRQ attendu ($0314)");
        end
    endtask

    integer i;
    reg [7:0] expect;

    task read_sector(input [7:0] trk, input [7:0] sec);
        begin
            bus_op(1, 16'h0312, sec);            // SECTOR
            bus_op(1, 16'h0310, 8'h80);          // Read sector
            for (i = 0; i < 256; i = i + 1) begin
                wait_drq;
                bus_read(16'h0313);
                expect = (trk*8'd32 + sec) ^ i[7:0];
                if (rd !== expect && errors < 8) begin
                    $display("FAIL: t%0d s%0d octet %0d : lu %02x attendu %02x",
                             trk, sec, i, rd, expect);
                    errors = errors + 1;
                end
            end
            wait_intrq;
            bus_read(16'h0310);                  // status (clear INTRQ)
            check(rd[4:0] == 5'd0, "read: status propre");
        end
    endtask

    // Golden : secteurs attendus des vraies pistes Citadelle (réf. python)
    reg [7:0] golden [0:22*17*256-1];
    reg [7:0] gvalid [0:22*17-1];
    initial begin
        $readmemh("sim/out/cit_golden.hex", golden);
        $readmemh("sim/out/cit_valid.hex", gvalid);
    end

    integer t, s, gi;
    task read_sector_golden(input [7:0] trk, input [7:0] sec);
        begin
            bus_op(1, 16'h0312, sec);
            bus_op(1, 16'h0310, 8'h80);
            for (i = 0; i < 256; i = i + 1) begin
                wait_drq;
                bus_read(16'h0313);
                gi = (trk*17 + (sec-1))*256 + i;
                if (rd !== golden[gi] && errors < 10) begin
                    $display("FAIL: CIT t%0d s%0d octet %0d : lu %02x attendu %02x",
                             trk, sec, i, rd, golden[gi]);
                    errors = errors + 1;
                end
            end
            wait_intrq;
            bus_read(16'h0310);
        end
    endtask

    initial begin
        repeat (8) @(negedge clk); rst = 0;

        // 1) FAT
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        check(file_count == 8'd7, "7 fichiers listes");

        // 2) Insertion de TESTMFM.DSK (idx 5) -> en-tête + piste 0
        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        check(!bad_format, "signature MFM_DISK reconnue");
        check(n_tracks == 7'd3, "geometrie: 3 pistes");
        wait (trk_loading === 1'b0);             // piste 0 chargée + scannée
        $display("disquette inseree, piste 0 chargee");

        // 3) Restore (piste 0) puis lecture secteur 1
        bus_op(1, 16'h0310, 8'h08);
        wait_intrq; bus_read(16'h0310);
        read_sector(8'd0, 8'd1);
        $display("piste 0 secteur 1 OK");

        // 4) Lecture secteur 17 (dernier)
        read_sector(8'd0, 8'd17);
        $display("piste 0 secteur 17 OK");

        // 5) Seek piste 2 (recharge la piste pendant le délai mécanique)
        bus_op(1, 16'h0313, 8'd2);               // DATA = 2
        bus_op(1, 16'h0310, 8'h18);              // Seek
        wait_intrq; bus_read(16'h0310);
        check(req_track == 7'd2, "seek: piste 2");
        read_sector(8'd2, 8'd5);
        $display("piste 2 secteur 5 OK");

        // 6) RNF : secteur 18
        bus_op(1, 16'h0312, 8'd18);
        bus_op(1, 16'h0310, 8'h80);
        wait_intrq;
        bus_read(16'h0310);
        check(rd[4] == 1'b1, "rnf: Record Not Found");

        // ------------------------------------------------------------------
        // Scénario 2 : VRAIES pistes (Citadelle 0..3) — lecture WD1793
        // comparée octet à octet à l'extraction de référence.
        // ------------------------------------------------------------------
        tb_fidx = 6'd6;                          // CITREAL.DSK
        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        check(!bad_format, "citreal: signature reconnue");
        wait (trk_loading === 1'b1);   // le chargement de piste démarre
        wait (trk_loading === 1'b0);   // ... et se termine (scan compris)
        bus_op(1, 16'h0310, 8'h08);              // Restore
        wait_intrq; bus_read(16'h0310);
        for (t = 0; t < 22; t = t + 1) begin
            if (t != 0) begin
                bus_op(1, 16'h0313, t[7:0]);     // Seek piste t
                bus_op(1, 16'h0310, 8'h18);
                wait_intrq; bus_read(16'h0310);
            end
            for (s = 1; s <= 17; s = s + 1) begin
                if (gvalid[t*17 + (s-1)]) begin
                    read_sector_golden(t[7:0], s[7:0]);
                end else begin
                    bus_op(1, 16'h0312, s[7:0]); // secteur absent -> RNF
                    bus_op(1, 16'h0310, 8'h80);
                    wait_intrq; bus_read(16'h0310);
                    check(rd[4] == 1'b1, "citreal: RNF secteur absent");
                end
            end
            $display("citreal piste %0d OK", t);
        end

        if (errors == 0) $display("ALL TESTS PASSED (tb_dsk)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #6_000_000_000; $display("FAIL: timeout"); $finish;
    end

endmodule
