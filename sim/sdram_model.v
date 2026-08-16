// SPDX-License-Identifier: EUPL-1.2
// Copyright (c) 2026 Bénédicte Marty
//
// sdram_model.v — modèle comportemental SDR SDRAM (banc de test, HW-3).
//
// Modèle JEDEC simplifié : décode les commandes, suit la ligne ouverte par banc,
// stocke les écritures, pilote `dq` après la latence CAS sur lecture, et signale
// tout READ/WRITE sans ACTIVE préalable (filet anti-bug du contrôleur). Mémoire
// tronquée à ADDRW bits ({row[1:0],col}) — suffisant pour un test fonctionnel.
//
// Lecture : **pipeline CAS fidèle** — chaque READ planifie sa donnée sur `dq`
// exactement CAS cycles après l'échantillonnage de la commande, 1 cycle (BL=1).
// Indispensable pour valider la lecture RAFALE (READs consécutifs sans écrasement).

`timescale 1ns/1ps

module sdram_model #(parameter CAS=2, ADDRW=12)(
    input  wire        clk, cke, cs_n, ras_n, cas_n, we_n,
    input  wire [1:0]  ba,
    input  wire [12:0] a,
    input  wire [1:0]  dqm,
    inout  wire [15:0] dq
);
    reg [15:0] mem [0:(1<<ADDRW)-1];
    reg [12:0] open_row [0:3];
    reg        row_act  [0:3];
    // pipeline de lecture : profondeur 8 (>= CAS), donnée à dq quand vpipe[CAS]=1
    reg [15:0] dpipe [0:8];
    reg [8:0]  vpipe;
    integer    refreshes, viol;
    assign dq = vpipe[CAS] ? dpipe[CAS] : 16'hzzzz;

    wire [3:0] cmd = {cs_n,ras_n,cas_n,we_n};
    wire [ADDRW-1:0] widx = {open_row[ba][1:0], a[9:0]};

    integer i;
    initial begin
        for (i=0;i<(1<<ADDRW);i=i+1) mem[i]=16'd0;
        open_row[0]=0; open_row[1]=0; open_row[2]=0; open_row[3]=0;
        row_act[0]=0; row_act[1]=0; row_act[2]=0; row_act[3]=0;
        for (i=0;i<9;i=i+1) dpipe[i]=16'd0;
        vpipe=9'd0; refreshes=0; viol=0;
    end

    integer k;
    always @(posedge clk) begin
        // décale le pipeline de lecture d'un cran (vieillit les READs en vol)
        for (k=8;k>0;k=k-1) dpipe[k]<=dpipe[k-1];
        vpipe <= {vpipe[7:0], 1'b0};
        if (cke) case (cmd)
            4'b0011: begin open_row[ba]<=a; row_act[ba]<=1'b1; end   // ACTIVE
            4'b0100: begin                                           // WRITE
                if (!row_act[ba]) begin viol=viol+1; $display("MODEL: WRITE sans ACTIVE ba=%0d",ba); end
                if (!dqm[0]) mem[widx][7:0]  <= dq[7:0];
                if (!dqm[1]) mem[widx][15:8] <= dq[15:8];
                if (a[10]) row_act[ba]<=1'b0;                        // auto-precharge
            end
            4'b0101: begin                                           // READ
                if (!row_act[ba]) begin viol=viol+1; $display("MODEL: READ sans ACTIVE ba=%0d",ba); end
                dpipe[0] <= mem[widx]; vpipe[0] <= 1'b1;             // donnée à dq CAS cycles plus tard
                if (a[10]) row_act[ba]<=1'b0;
            end
            4'b0010: begin                                           // PRECHARGE
                if (a[10]) begin row_act[0]<=0;row_act[1]<=0;row_act[2]<=0;row_act[3]<=0; end
                else row_act[ba]<=1'b0;
            end
            4'b0001: refreshes<=refreshes+1;                         // AUTO_REFRESH
            4'b0000: ;                                               // LOAD MODE
            default: ;
        endcase
    end
endmodule
