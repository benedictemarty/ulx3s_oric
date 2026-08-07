// Testbench du chargeur cassette SD (rtl/tape_loader.v) bout-en-bout :
// fat32 + sd_spi + carte-image lisent TEST.TAP, le loader l'injecte selon le
// protocole cassette. Un mock du tape_injector émet des crédits lentement et
// capture le flux : on vérifie l'en-tête (0x01,len) + les 600 octets du motif.
`timescale 1ns/1ps

module tb_tape_loader;

    reg clk = 0;
    always #10 clk = ~clk;
    reg rst = 1;

    // SD + FAT
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

    reg         fat_start;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;
    wire [87:0] q_name;
    wire [31:0] q_size, q_clus;
    wire        q_isdsk;
    wire        open_start;
    wire [5:0]  open_idx;
    wire        fdata_ready, floading, feof, fdata_valid;
    wire [7:0]  fdata;

    fat32 fat (
        .clk(clk), .rst(rst), .start(fat_start),
        .rd_start(rd_start), .rd_sector(rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy), .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error), .file_count(file_count), .status(fat_status),
        .q_idx(6'd3), .q_name(q_name), .q_size(q_size), .q_clus(q_clus), .q_isdsk(q_isdsk),
        .open_start(open_start), .open_idx(open_idx), .fdata_ready(fdata_ready),
        .floading(floading), .feof(feof), .fdata(fdata), .fdata_valid(fdata_valid)
    );

    // Loader
    reg         load_trigger;
    wire [7:0]  tape_rx_data;
    wire        tape_rx_valid, ld_active;
    reg         tape_credit;

    tape_loader ld (
        .clk(clk), .rst(rst), .load_trigger(load_trigger),
        .sel_idx(6'd3), .file_size(q_size), .fat_ready(fat_done),
        .open_start(open_start), .open_idx(open_idx), .fdata_ready(fdata_ready),
        .fdata_valid(fdata_valid), .fdata(fdata), .feof(feof),
        .tape_rx_data(tape_rx_data), .tape_rx_valid(tape_rx_valid),
        .tape_credit(tape_credit), .active(ld_active)
    );

    // Mock tape_injector : émet un crédit toutes les ~40 cycles (jusqu'à 600),
    // capture tout ce qui arrive en rx_valid.
    integer credit_timer = 0, credits_sent = 0;
    always @(posedge clk) begin
        tape_credit <= 1'b0;
        if (ld_active && credits_sent < 600) begin
            credit_timer <= credit_timer + 1;
            if (credit_timer == 40) begin
                tape_credit <= 1'b1; credit_timer <= 0; credits_sent <= credits_sent + 1;
            end
        end
    end

    reg [7:0] cap [0:1023];
    integer   nc = 0;
    always @(posedge clk) if (tape_rx_valid) begin cap[nc] = tape_rx_data; nc = nc + 1; end

    integer errors = 0, i, bad;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    initial begin
        fat_start = 0; load_trigger = 0; tape_credit = 0;
        repeat (4) @(negedge clk); rst = 0;
        wait (sd_ready === 1'b1);
        @(negedge clk); fat_start = 1; @(negedge clk); fat_start = 0;
        wait (fat_done === 1'b1);

        @(negedge clk); load_trigger = 1; @(negedge clk); load_trigger = 0;

        wait (nc == 603);                 // 3 (en-tête) + 600 (données)
        @(negedge clk);

        check(cap[0] === 8'h01,  "en-tete START 0x01");
        check(cap[1] === 8'h58,  "len_lo = 600 & 0xFF");
        check(cap[2] === 8'h02,  "len_hi = 600 >> 8");
        bad = 0;
        for (i = 0; i < 600; i = i + 1)
            if (cap[3+i] !== (i & 8'hFF)) bad = bad + 1;
        check(bad == 0, "600 octets de donnees conformes au motif");

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape_loader)");
        else $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #800_000_000; $display("FAIL: timeout (nc=%0d)", nc); $finish;
    end

endmodule
