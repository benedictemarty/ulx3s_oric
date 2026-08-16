// SPDX-License-Identifier: EUPL-1.2
// Copyright (c) 2026 Bénédicte Marty
//
// tb_sdram.v — contrôleur SDR SDRAM (ADR-19, HW-3).
//
// Contrôleur + modèle. Après l'init JEDEC : écrit 4 mots (dont un sur une ligne
// ≠ 0 pour exercer ACTIVE), les relit, vérifie. Tourne assez longtemps pour
// déclencher ≥1 auto-refresh et confirme que les données survivent. Aucune
// violation READ/WRITE-sans-ACTIVE tolérée.

`timescale 1ns/1ps

module tb_sdram;
    reg        clk=1'b0, rst_n=1'b0;
    reg        cmd_valid=1'b0, cmd_we=1'b0;
    reg [24:0] cmd_addr=25'd0;
    reg [15:0] cmd_wdata=16'd0;
    wire       cmd_ready, rd_valid;
    wire [15:0] rd_data;
    wire       cke, cs_n, ras_n, cas_n, we_n;
    wire [1:0] ba, dqm;
    wire [12:0] a;
    wire [15:0] dq;

    sdram_ctrl #(.CAS(2)) dut (
        .clk(clk),.rst_n(rst_n),
        .cmd_valid(cmd_valid),.cmd_we(cmd_we),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),
        .cmd_blen(10'd1),
        .cmd_ready(cmd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .cke(cke),.cs_n(cs_n),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
        .ba(ba),.a(a),.dqm(dqm),.dq(dq));

    sdram_model #(.CAS(2)) mdl (
        .clk(clk),.cke(cke),.cs_n(cs_n),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),
        .ba(ba),.a(a),.dqm(dqm),.dq(dq));

    always #5 clk=~clk;

    integer errors=0, guard;
    reg [15:0] got;

    task wr; input [24:0] ad; input [15:0 ] d; begin
        cmd_addr=ad; cmd_wdata=d; cmd_we=1'b1; cmd_valid=1'b1;
        guard=0; @(posedge clk);
        while (!cmd_ready && guard<500) begin @(posedge clk); guard=guard+1; end
        @(negedge clk); cmd_valid=1'b0;       // handshake consommé
    end endtask

    task rd; input [24:0] ad; output [15:0] d; begin
        cmd_addr=ad; cmd_we=1'b0; cmd_valid=1'b1;
        guard=0; @(posedge clk);
        while (!cmd_ready && guard<500) begin @(posedge clk); guard=guard+1; end
        @(negedge clk); cmd_valid=1'b0;
        guard=0;
        while (!rd_valid && guard<500) begin @(posedge clk); guard=guard+1; end
        d = rd_data;
    end endtask

    task chk; input [24:0] ad; input [15:0] exp; begin
        rd(ad, got);
        if (got !== exp) begin errors=errors+1;
            $display("  FAIL rd[%0d]=%04X attendu %04X", ad, got, exp); end
    end endtask

    initial begin
        rst_n=1'b0; repeat(4) @(negedge clk); rst_n=1'b1;
        // attend la fin de l'init (1er cmd_ready)
        guard=0; while (!cmd_ready && guard<200) begin @(posedge clk); guard=guard+1; end

        wr(25'd5,    16'hBEEF);
        wr(25'd6,    16'h1234);
        wr(25'd1000, 16'hABCD);
        wr(25'd1031, 16'hF00D);    // col=7, row=1 → exerce une 2e ligne

        chk(25'd5,    16'hBEEF);
        chk(25'd6,    16'h1234);
        chk(25'd1000, 16'hABCD);
        chk(25'd1031, 16'hF00D);

        // tourne pour forcer des auto-refresh, puis revérifie la persistance
        repeat(200) @(posedge clk);
        chk(25'd5,    16'hBEEF);
        chk(25'd1031, 16'hF00D);

        $display("sdram : init + W/R 4 mots (2 lignes) + persistance post-refresh ; refresh=%0d viol=%0d",
                 mdl.refreshes, mdl.viol);
        if (errors==0 && mdl.viol==0 && mdl.refreshes>0)
            $display("RESULT: PASS (contrôleur SDR SDRAM : JEDEC init, R/W, auto-refresh, ADR-19)");
        else
            $display("RESULT: FAIL (%0d data, %0d viol, %0d refresh)", errors, mdl.viol, mdl.refreshes);
        $finish;
    end
endmodule
