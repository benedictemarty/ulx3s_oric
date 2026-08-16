// Banc ciblé (diagnostic US-DISK) : lecture piste 13 FACE 1 de SEDBOOT.DSK
// (image sed_test.img, .dsk 2 faces x 80 pistes). Reproduit la lecture qui
// renvoie « 20 20 » dans tb_sedboot au lieu de « 95 0e » (contenu réel).
`timescale 1ns/1ps

module tb_side1;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;
    reg [1:0] cdiv = 0;
    always @(posedge clk) cdiv <= cdiv + 2'd1;
    wire cen = (cdiv == 2'd3);

    wire        rd_start;
    wire [31:0] rd_sector;
    wire        sd_ready, sd_busy, sd_dvalid, sd_error;
    wire [7:0]  sd_data, sd_status;
    wire        sck, mosi, miso, cs_n;

    sd_spi #(.HALF(2)) sd (
        .clk(clk), .rst(rst), .start_read(rd_start),
        .start_write(1'b0), .wr_data(8'd0), .sector(rd_sector),
        .ready(sd_ready), .busy(sd_busy), .error(sd_error),
        .data(sd_data), .data_valid(sd_dvalid), .status(sd_status),
        .sck(sck), .mosi(mosi), .miso(miso), .cs_n(cs_n)
    );
    sd_card_file #(.IMG("sim/out/sed_test.img")) card (
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
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid),
        .wblk_start(1'b0), .wblk_idx(6'd0), .wblk_offset(32'd0),
        .wblk_data(8'd0), .wr_idx(9'd0),
        .wblk_pos(), .wblk_done(), .wblk_error(), .wr_start(), .wr_data()
    );

    reg        insert = 0, eject = 0;
    reg [5:0]  tb_fidx = 6'd0;
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

    task wait_drq;
        integer n;
        begin
            n = 0; rd = 8'hFF;
            while (rd[7] && n < 2000000) begin bus_read(16'h0318); n = n + 1; end
        end
    endtask

    task wait_intrq;
        integer n;
        begin
            n = 0; rd = 8'hFF;
            while (rd[7] && n < 2000000) begin bus_read(16'h0314); n = n + 1; end
        end
    endtask

    integer i;
    reg [7:0] first [0:15];

    task dump_sector(input [7:0] sec);
        begin
            bus_op(1, 16'h0312, sec);
            bus_op(1, 16'h0310, 8'h80);
            for (i = 0; i < 256; i = i + 1) begin
                wait_drq;
                bus_read(16'h0313);
                if (i < 16) first[i] = rd;
            end
            wait_intrq;
            bus_read(16'h0310);
            $display("status=%02x  data[0..15] = %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x",
                     rd, first[0], first[1], first[2], first[3],
                     first[4], first[5], first[6], first[7],
                     first[8], first[9], first[10], first[11],
                     first[12], first[13], first[14], first[15]);
        end
    endtask

    initial begin
        repeat (8) @(negedge clk); rst = 0;

        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);
        $display("fat: %0d fichier(s)", file_count);

        @(negedge clk); insert = 1; @(negedge clk); insert = 0;
        wait (inserted === 1'b1);
        $display("insere : bad_format=%b n_tracks=%0d n_spt=%0d",
                 bad_format, n_tracks, n_spt);
        wait (trk_loading === 1'b0);

        // Seek piste 13 (face 0 pour l'instant)
        bus_op(1, 16'h0313, 8'd13);
        bus_op(1, 16'h0310, 8'h18);
        wait_intrq; bus_read(16'h0310);
        $display("seek 13 : req_track=%0d req_side=%b", req_track, req_side);

        // Face 0, secteur 13 : attendu 4c c3 1c ...
        $display("-- lecture (trk13, face 0, sec13), attendu 4c c3 1c ...");
        dump_sector(8'd13);

        // Face 1 (ctl b4), secteur 13 : attendu 95 0e 00 ...
        bus_op(1, 16'h0314, 8'h90);   // side=1, EPROM off, INTENA off
        $display("-- lecture (trk13, face 1, sec13), attendu 95 0e 00 ...");
        dump_sector(8'd13);

        $display("FIN tb_side1");
        $finish;
    end

    initial begin
        #4000000000;
        $display("TIMEOUT");
        $finish;
    end

    // Sondes : chaque (re)chargement de piste et l'état du buffer
    always @(posedge clk) begin
        if (d_open_start)
            $display("[DSK] open_start offset=%0d (wanted=%02x loaded=%02x req=%0d/%b)",
                     d_open_offset, dsk.wanted, dsk.loaded, req_track, req_side);
        if (d_open_abort)
            $display("[DSK] open_abort (state=%0d wpos=%0d)", dsk.state, dsk.wpos);
    end

endmodule
