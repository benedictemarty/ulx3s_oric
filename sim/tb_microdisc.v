// Testbench du wrapper Microdisc (US-DISK.2) : état de boot (ROMDIS + EPROM
// visibles), registre de contrôle $0314 (décodage des bits, réf.
// microdisc.c), flags /INTRQ ($0314) et /DRQ ($0318) actifs bas, IRQ CPU
// gouvernée par INTENA, contenu EPROM conforme à microdis.hex, interface
// transparente quand enable=0.
`timescale 1ns/1ps

module tb_microdisc;

    reg clk = 0, rst = 1;
    always #10 clk = ~clk;
    reg [1:0] cdiv = 0;
    always @(posedge clk) cdiv <= cdiv + 2'd1;
    wire cen = (cdiv == 2'd3);

    reg         enable = 1;
    reg  [15:0] a = 16'h0000;
    reg         io_sel = 0, we = 0;
    reg  [7:0]  din = 0;
    wire [7:0]  dout, eprom_dout;
    wire        dout_valid, romdis, eprom_sel, irq;
    wire [6:0]  req_track;
    wire        req_side;
    wire [4:0]  sec_id;
    wire [8:0]  sec_addr;

    microdisc #(.ROM_FILE("roms/microdis.hex"),
                .REV_CYCLES(2000), .INDEX_CYCLES(40),
                .SETTLE_CYCLES(300), .RNF_CYCLES(5000)) dut (
        .clk(clk), .cen(cen), .rst(rst), .enable(enable),
        .a(a), .io_sel(io_sel), .we(we), .din(din),
        .dout(dout), .dout_valid(dout_valid),
        .romdis(romdis), .eprom_sel(eprom_sel), .eprom_dout(eprom_dout),
        .rom_a(a[13:0]), .irq(irq),
        .disk_present(1'b0), .n_tracks(7'd42), .n_spt(5'd17),
        .req_track(req_track), .req_side(req_side), .trk_loading(1'b0),
        .sec_id(sec_id), .sec_valid(1'b0),
        .sec_addr(sec_addr), .sec_byte(8'h00)
    );

    // EPROM de contrôle (mêmes données)
    reg [7:0] ref_rom [0:8191];
    initial $readmemh("roms/microdis.hex", ref_rom);

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

    integer n;
    initial begin
        repeat (8) @(negedge clk); rst = 0; repeat (8) @(negedge clk);

        // ---- Boot : ROMDIS + EPROM actifs, EPROM lisible en $E000+ ----
        check(romdis, "boot: ROMDIS actif");
        a = 16'hE000; @(negedge clk); @(negedge clk);
        check(eprom_sel, "boot: EPROM visible en E000");
        check(eprom_dout === ref_rom[13'h0000], "boot: EPROM[0] conforme");
        a = 16'hE123; @(negedge clk); @(negedge clk);
        check(eprom_dout === ref_rom[13'h0123], "boot: EPROM[123] conforme");
        a = 16'hFFFC; @(negedge clk); @(negedge clk);   // vecteur reset -> EPROM
        check(eprom_sel, "boot: vecteur reset dans l'EPROM");
        check(eprom_dout === ref_rom[13'h1FFC], "boot: EPROM (miroir 8Ko) FFFC");
        a = 16'hC000; @(negedge clk); @(negedge clk);
        check(!eprom_sel, "boot: pas d'EPROM en C000 (RAM overlay)");

        // ---- Flags au repos : /INTRQ=1, /DRQ=1 (inactifs, bits 6:0 = 1) ----
        bus_read(16'h0314);
        check(rd === 8'hFF, "repos: $0314 = FF (pas d'INTRQ)");
        bus_read(16'h0318);
        check(rd === 8'hFF, "repos: $0318 = FF (pas de DRQ)");

        // ---- Restore sans disque : INTRQ (erreur), pas d'IRQ (INTENA=0) ----
        bus_op(1, 16'h0310, 8'h08);
        n = 0; while (!dut.fdc_intrq && n < 100000) begin @(negedge clk); n = n + 1; end
        check(dut.fdc_intrq, "restore sans disque: INTRQ");
        check(!irq, "INTENA=0: pas d'IRQ CPU");
        bus_read(16'h0314);
        check(rd === 8'h7F, "$0314 bit7=0 : /INTRQ actif");

        // ---- INTENA : l'IRQ passe ----
        bus_op(1, 16'h0314, 8'h01 | 8'h02 | 8'h80);   // INTENA, ROM ok, EPROM off
        check(irq, "INTENA=1: IRQ CPU suit INTRQ");
        check(!romdis, "ctrl b1=1: ROMDIS relâché");
        check(!eprom_sel, "ctrl b7=1: EPROM masquée");

        // ---- Side / drive décodés ----
        bus_op(1, 16'h0314, 8'h10 | 8'h20);           // side=1, drive=1
        check(req_side === 1'b1, "ctrl: side=1");
        check(dut.drive === 2'd1, "ctrl: drive=1");

        // ---- Retour boot : EPROM + ROMDIS ----
        bus_op(1, 16'h0314, 8'h00);
        check(romdis, "ctrl 00: ROMDIS actif");
        a = 16'hE000; @(negedge clk); @(negedge clk);
        check(eprom_sel, "ctrl 00: EPROM visible");

        // ---- enable=0 : transparent ----
        enable = 0; @(negedge clk);
        check(!romdis, "enable=0: pas de ROMDIS");
        check(!eprom_sel, "enable=0: pas d'EPROM");
        check(!dout_valid, "enable=0: pas de reponse bus");
        check(!irq, "enable=0: pas d'IRQ");

        if (errors == 0) $display("ALL TESTS PASSED (tb_microdisc)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #100_000_000; $display("FAIL: timeout"); $finish;
    end

endmodule
