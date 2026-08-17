// Testbench du cœur WD1793 (US-DISK.1) : fournisseur de secteurs simulé
// (17 secteurs × 256, motif = sec ^ offset), timings réduits. Vérifie :
// restore/seek (délais type I, TRK0, INTRQ), read sector simple (DRQ par
// octet, données exactes, INTRQ final), multi-secteur (enchaînement + fin de
// piste), RNF (secteur hors piste, délai 5 tours), read address, force
// interrupt, write sector -> write protect (v1), status type I vivant.
`timescale 1ns/1ps

module tb_wd1793;

    // Timings réduits : tour = 2000 ticks, pas = quelques ticks
    localparam REV = 2000, IDX = 40, SETTLE = 300, RNF = 5000;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;

    // cen : 1 tick sur 4
    reg [1:0] cdiv = 0;
    always @(posedge clk) cdiv <= cdiv + 2'd1;
    wire cen = (cdiv == 2'd3);

    reg        cs = 0, we = 0;
    reg  [1:0] addr = 0;
    reg  [7:0] din = 0;
    wire [7:0] dout;
    wire       intrq, drq;
    wire [6:0] req_track;
    wire       req_side;
    wire [4:0] sec_id;
    wire [8:0] sec_addr;
    reg  [7:0] sec_byte;

    // Écriture (US-DISK.5 ph.4) : capture des octets poussés + backend simulé
    // (wr_busy=0, wr_ok=1 -> le write-back « réussit » immédiatement).
    wire       sec_we, wr_commit;
    wire [7:0] sec_wr_data;
    reg  [7:0] wrote [0:255];
    always @(posedge clk) if (sec_we) wrote[sec_addr[7:0]] <= sec_wr_data;

    localparam SPT = 17;
    wire sec_valid = (sec_id >= 1) && (sec_id <= SPT);
    always @(posedge clk) sec_byte <= {3'b000, sec_id} ^ sec_addr[7:0];

    wd1793 #(.REV_CYCLES(REV), .INDEX_CYCLES(IDX),
             .SETTLE_CYCLES(SETTLE), .RNF_CYCLES(RNF)) dut (
        .clk(clk), .cen(cen), .rst(rst),
        .cs(cs), .addr(addr), .we(we), .din(din), .dout(dout),
        .intrq(intrq), .drq(drq),
        .side(1'b0),
        .disk_present(1'b1), .n_tracks(7'd42), .n_spt(5'd17),
        .req_track(req_track), .req_side(req_side), .trk_loading(1'b0),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte),
        .sec_we(sec_we), .sec_wr_data(sec_wr_data), .wr_commit(wr_commit),
        .wr_busy(1'b0), .wr_ok(1'b1), .wr_err(1'b0)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
    endtask

    // Un accès bus dure exactement un tick cen : cs posé pendant cdiv==3
    // (cen haut), l'action du DUT tombe au posedge 3->0, cs relâché après.
    task bus_op(input w, input [1:0] a, input [7:0] v);
        begin
            @(negedge clk);
            while (cdiv != 2'd2) @(negedge clk);
            cs = 1; we = w; addr = a; din = v;
            @(negedge clk);                        // cdiv==3 : cen haut
            @(negedge clk);                        // action faite au posedge
            cs = 0; we = 0;
        end
    endtask

    reg [7:0] rd;
    task bus_read(input [1:0] a);
        begin
            @(negedge clk);
            while (cdiv != 2'd2) @(negedge clk);
            cs = 1; we = 0; addr = a;
            @(negedge clk);                        // cdiv==3 : dout stable
            rd = dout;                             // échantillon avant l'action
            @(negedge clk);
            cs = 0;
        end
    endtask

    task wait_intrq;
        integer n;
        begin
            n = 0;
            while (!intrq && n < 4_000_000) begin @(negedge clk); n = n + 1; end
            check(intrq, "INTRQ attendu");
        end
    endtask

    task wait_drq;
        integer n;
        begin
            n = 0;
            while (!drq && n < 4_000_000) begin @(negedge clk); n = n + 1; end
            check(drq, "DRQ attendu");
        end
    endtask

    integer i;
    reg [7:0] expect;

    initial begin
        repeat (8) @(negedge clk); rst = 0;
        repeat (8) @(negedge clk);

        // ---- Restore (type I) ----
        bus_op(1, 2'd0, 8'h08);                     // Restore, h=1, r=00
        wait_intrq;
        bus_read(2'd0);                             // status (clear INTRQ)
        check(rd[2] == 1'b1, "restore: TRK0");
        check(rd[4] == 1'b0, "restore: pas de seek error");
        check(req_track == 0, "restore: piste 0");
        @(negedge clk);
        check(!intrq, "lecture status efface INTRQ");

        // ---- Seek piste 2 (via DATA) ----
        bus_op(1, 2'd3, 8'd2);                      // DATA = 2
        bus_op(1, 2'd0, 8'h18);                     // Seek, h=1
        wait_intrq;
        bus_read(2'd0);
        check(req_track == 7'd2, "seek: piste 2");
        bus_read(2'd1);
        check(rd == 8'd2, "seek: registre track = 2");

        // ---- Read sector 5 (simple) ----
        bus_op(1, 2'd2, 8'd5);                      // SECTOR = 5
        bus_op(1, 2'd0, 8'h80);                     // Read sector
        bus_read(2'd0);
        check(rd[0] == 1'b1, "read: BUSY pendant la latence");
        for (i = 0; i < 256; i = i + 1) begin
            wait_drq;
            bus_read(2'd3);
            expect = 8'd5 ^ i[7:0];
            check(rd == expect, "read: donnee attendue");
        end
        wait_intrq;
        bus_read(2'd0);
        check(rd == 8'h00, "read: status final propre");

        // ---- Multi-secteur : 16 puis 17, fin de piste ----
        bus_op(1, 2'd2, 8'd16);
        bus_op(1, 2'd0, 8'h90);                     // Read sectors (m=1)
        for (i = 0; i < 512; i = i + 1) begin
            wait_drq;
            bus_read(2'd3);
            expect = ((i < 256) ? 8'd16 : 8'd17) ^ i[7:0];
            check(rd == expect, "multi: donnee attendue");
        end
        wait_intrq;                                 // fin de piste (sec 18)
        bus_read(2'd2);
        check(rd == 8'd18, "multi: registre sector avance");

        // ---- RNF : secteur 20 (> spt) ----
        bus_op(1, 2'd2, 8'd20);
        bus_op(1, 2'd0, 8'h80);
        bus_read(2'd0);
        check(rd[0] == 1'b1, "rnf: BUSY pendant la recherche");
        wait_intrq;
        bus_read(2'd0);
        check(rd[4] == 1'b1, "rnf: Record Not Found");
        check(rd[0] == 1'b0, "rnf: plus BUSY");

        // ---- Read address ----
        bus_op(1, 2'd2, 8'd3);                      // SECTOR = 3 (champ addr)
        bus_op(1, 2'd0, 8'hC0);                     // Read address
        wait_drq; bus_read(2'd3);
        check(rd == 8'd2, "readaddr: piste");
        wait_drq; bus_read(2'd3);
        check(rd == 8'd0, "readaddr: face");
        wait_drq; bus_read(2'd3);
        check(rd == 8'd3, "readaddr: secteur");
        wait_drq; bus_read(2'd3);
        check(rd == 8'd1, "readaddr: taille 256");
        wait_drq; bus_read(2'd3);
        wait_drq; bus_read(2'd3);                   // CRC (0, 0)
        wait_intrq;
        bus_read(2'd0);

        // ---- Write sector (US-DISK.5 ph.4) : 256 octets -> commit -> OK ----
        bus_op(1, 2'd2, 8'd5);                      // SECTOR = 5
        bus_op(1, 2'd0, 8'hA0);                     // Write sector
        for (i = 0; i < 256; i = i + 1) begin
            wait_drq;
            bus_op(1, 2'd3, 8'hA5 ^ i[7:0]);        // DATA
        end
        wait_intrq;
        bus_read(2'd0);
        check(rd[6] == 1'b0, "write: pas de WRITE PROTECT");
        check(rd[4:0] == 5'd0, "write: status propre");
        for (i = 0; i < 256; i = i + 1)
            if (wrote[i] !== (8'hA5 ^ i[7:0]) && errors < 8) begin
                $display("FAIL: write octet %0d = %02x att %02x", i, wrote[i], 8'hA5^i[7:0]);
                errors = errors + 1;
            end

        // ---- Force interrupt ----
        bus_op(1, 2'd2, 8'd5);
        bus_op(1, 2'd0, 8'h80);                     // read en cours...
        bus_op(1, 2'd0, 8'hD0);                     // Force interrupt
        check(intrq, "fint: INTRQ");
        bus_read(2'd0);
        check(rd[0] == 1'b0, "fint: plus BUSY");
        // status type I vivant : index pulse une fois par tour
        i = 0;
        while (i < 3*REV*4 && !(dout[1] && addr == 2'd0)) begin
            @(negedge clk); addr = 2'd0; i = i + 1;
        end
        bus_read(2'd0);
        // (le pulse dure IDX ticks : on doit finir par le voir)
        check(i < 3*REV*4, "type I: index pulse vivant");

        if (errors == 0) $display("ALL TESTS PASSED (tb_wd1793)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #400_000_000; $display("FAIL: timeout"); $finish;
    end

endmodule
