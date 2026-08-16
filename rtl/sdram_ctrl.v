// SPDX-License-Identifier: EUPL-1.2
// Copyright (c) 2026 Bénédicte Marty
//
// sdram_ctrl.v — contrôleur SDR SDRAM (VRAM Oric 2, ADR-19, HW-3).
//
// Contrôleur JEDEC SDR simple « closed-page » : chaque accès fait
// ACTIVE → (tRCD) → READ/WRITE avec **auto-precharge** (a[10]=1), burst 1 mot.
// Séquence d'init standard (NOP pause → PRECHARGE ALL → 2× AUTO_REFRESH →
// LOAD MODE REGISTER), auto-refresh périodique inséré à l'état IDLE. Interface
// système mot-à-mot (16-bit) à latence variable — pensée pour un wrapper qui
// expose au SoC un port **lecture synchrone** (résout le blocage BRAM du DMA,
// cf. `.dma_rd_data(0)` du SoC). Constantes de timing en cycles, paramétrables
// (calées au bring-up carte selon la fréquence et le chip ULX3S réel).

module sdram_ctrl #(
    parameter CAS         = 2,    // latence CAS
    parameter T_RCD       = 2,    // ACTIVE → READ/WRITE
    parameter T_RP        = 2,    // recovery precharge (auto-precharge)
    parameter T_RFC       = 7,    // durée auto-refresh
    parameter T_MRD       = 2,    // load mode → cmd
    parameter INIT_NOP    = 16,   // pause init (200µs réel ; réduit en sim)
    parameter REFRESH_INT = 64,   // intervalle entre refresh (cycles)
    parameter RD_DELAY    = 0     // cycles de capture lecture EN PLUS de CAS (marge bring-up)
)(
    input  wire        clk,
    input  wire        rst_n,
    // ── Interface système (mot 16-bit) ──
    input  wire        cmd_valid,
    input  wire        cmd_we,        // 1 = écriture, 0 = lecture
    input  wire [24:0] cmd_addr,      // adresse mot
    input  wire [15:0] cmd_wdata,
    input  wire [9:0]  cmd_blen,      // longueur rafale lecture (mots) ; 1 = mono-mot (défaut)
    output reg         cmd_ready,     // contrôleur prêt à accepter (IDLE, pas de refresh dû)
    output reg         cmd_accept,    // pulse 1 cyc : commande RÉELLEMENT acceptée (non ambigu vs refresh)
    output reg         rd_valid,      // pulse : rd_data valide
    output reg  [15:0] rd_data,
    // ── Interface SDRAM ──
    output reg         cke,
    output reg         cs_n, ras_n, cas_n, we_n,
    output reg  [1:0]  ba,
    output reg  [12:0] a,
    output reg  [1:0]  dqm,
    inout  wire [15:0] dq
);
    // Bus DQ tristate (le contrôleur ne pilote qu'en écriture).
    reg        dq_oe;
    reg [15:0] dq_out;
    assign dq = dq_oe ? dq_out : 16'hzzzz;

    // Codes commande {cs_n,ras_n,cas_n,we_n}.
    localparam C_NOP=4'b0111, C_ACT=4'b0011, C_READ=4'b0101, C_WRITE=4'b0100,
               C_PRE=4'b0010, C_REF=4'b0001, C_LMR=4'b0000;
    task setcmd; input [3:0] c; begin {cs_n,ras_n,cas_n,we_n}=c; end endtask

    // États.
    localparam S_INIT=4'd0, S_IPRE=4'd1, S_IREF=4'd2, S_ILMR=4'd3, S_IDLE=4'd4,
               S_ACT=4'd5, S_RW=4'd6, S_RDCAP=4'd7, S_RECOV=4'd8, S_REF=4'd9,
               S_BURST=4'd10, S_BWRITE=4'd11;

    // Lecture rafale (page ouverte) : pipeline READs consécutifs, capture CAS derrière.
    // CAP_POS = profondeur de capture (calée sur le mono-mot : setcmd→capture). b_pend
    // injecte 1 à l'émission, décale chaque cycle ; on capture quand b_pend[CAP_POS]=1.
    localparam CAP_POS = CAS + RD_DELAY + 1;
    reg  [9:0] l_blen;             // longueur rafale latchée
    reg  [9:0] b_col;             // colonne à émettre
    reg  [9:0] b_iss;             // READs émis
    reg  [9:0] b_cap;             // mots capturés
    reg  [7:0] b_pend;            // pipeline d'in-flight (8 profond, large)

    reg [3:0]  st;
    reg [15:0] tmr;            // compte à rebours de phase
    reg [1:0]  init_ref;       // 2 refresh d'init
    reg [15:0] ref_cnt;        // compteur intervalle refresh
    reg        ref_due;
    // accès latché
    reg        a_we;
    reg [15:0] a_wdata;
    wire [1:0]  m_ba  = cmd_addr[24:23];
    wire [12:0] m_row = cmd_addr[22:10];
    wire [9:0]  m_col = cmd_addr[9:0];
    reg [1:0]  l_ba;
    reg [9:0]  l_col;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st<=S_INIT; tmr<=INIT_NOP; init_ref<=2'd0; ref_cnt<=16'd0; ref_due<=1'b0;
            cke<=1'b0; setcmd(C_NOP); ba<=2'd0; a<=13'd0; dqm<=2'b00;
            dq_oe<=1'b0; dq_out<=16'd0; cmd_ready<=1'b0; cmd_accept<=1'b0; rd_valid<=1'b0; rd_data<=16'd0;
            a_we<=1'b0; a_wdata<=16'd0; l_ba<=2'd0; l_col<=10'd0;
            l_blen<=10'd1; b_col<=10'd0; b_iss<=10'd0; b_cap<=10'd0; b_pend<=8'd0;
        end else begin
            // défauts par cycle
            cke<=1'b1; setcmd(C_NOP); dqm<=2'b00; dq_oe<=1'b0;
            cmd_ready<=1'b0; cmd_accept<=1'b0; rd_valid<=1'b0;
            if (tmr!=16'd0) tmr<=tmr-16'd1;

            // horloge de refresh (sature ; consommée à IDLE)
            if (st!=S_INIT) begin
                if (ref_cnt>=REFRESH_INT) ref_due<=1'b1; else ref_cnt<=ref_cnt+16'd1;
            end

            case (st)
                // ── Séquence d'init JEDEC ──
                S_INIT: if (tmr==16'd0) begin
                    setcmd(C_PRE); a<=13'h0400;    // a[10]=1 : precharge all
                    tmr<=T_RP; st<=S_IPRE;
                end
                S_IPRE: if (tmr==16'd0) begin
                    setcmd(C_REF); tmr<=T_RFC; init_ref<=init_ref+2'd1; st<=S_IREF;
                end
                S_IREF: if (tmr==16'd0) begin
                    if (init_ref<2'd2) begin setcmd(C_REF); tmr<=T_RFC; init_ref<=init_ref+2'd1; end
                    else begin
                        // mode reg : burst length 1, CAS latency = CAS.
                        setcmd(C_LMR); ba<=2'd0; a<={3'd0, 3'd0, CAS[2:0], 1'b0, 3'd0};
                        tmr<=T_MRD; st<=S_ILMR;
                    end
                end
                S_ILMR: if (tmr==16'd0) begin st<=S_IDLE; ref_cnt<=16'd0; ref_due<=1'b0; end

                // ── Service ──
                S_IDLE: begin
                    // Commande présentée → PRIORITÉ sur le refresh (sinon cmd_ready=1 ne
                    // garantirait pas l'acceptation : un refresh devenu dû entre-temps
                    // volerait le cycle et perdrait la commande). Le refresh dû reste
                    // latché (ref_due) et passe au prochain idle libre — marge suffisante.
                    if (cmd_valid) begin
                        cmd_ready<=1'b0; cmd_accept<=1'b1;   // acceptation réelle (pulse)
                        a_we<=cmd_we; a_wdata<=cmd_wdata; l_ba<=m_ba; l_col<=m_col;
                        l_blen <= (cmd_blen==10'd0) ? 10'd1 : cmd_blen;   // rafale R ET W
                        setcmd(C_ACT); ba<=m_ba; a<=m_row;
                        tmr<=T_RCD; st<=S_ACT;
                    end else if (ref_due) begin
                        setcmd(C_REF); tmr<=T_RFC; ref_due<=1'b0; ref_cnt<=16'd0; st<=S_REF;
                    end else
                        cmd_ready<=1'b1;
                end
                S_REF: if (tmr==16'd0) st<=S_IDLE;

                S_ACT: if (tmr==16'd0) begin
                    ba<=l_ba; a<={2'b00, 1'b1, l_col};   // a[10]=1 : auto-precharge (mono-mot)
                    if (a_we && l_blen <= 10'd1) begin
                        setcmd(C_WRITE); dq_oe<=1'b1; dq_out<=a_wdata; dqm<=2'b00;
                        tmr<=T_RP; st<=S_RECOV;          // écriture mono-mot (inchangé)
                    end else if (a_we) begin
                        // rafale d'ÉCRITURE : réplique a_wdata sur N colonnes (fill solide)
                        setcmd(C_WRITE); a<={2'b00, 1'b0, l_col}; dq_oe<=1'b1; dq_out<=a_wdata; dqm<=2'b00;
                        b_col<=l_col+10'd1; b_iss<=10'd1; st<=S_BWRITE;
                    end else if (l_blen <= 10'd1) begin
                        setcmd(C_READ); tmr<=CAS+RD_DELAY; st<=S_RW;   // lecture mono-mot (inchangé)
                    end else begin
                        // rafale de LECTURE : 1ʳᵉ READ sans auto-precharge, pipeline
                        setcmd(C_READ); a<={2'b00, 1'b0, l_col};
                        b_col<=l_col+10'd1; b_iss<=10'd1; b_cap<=10'd0; b_pend<=8'd1;
                        st<=S_BURST;
                    end
                end
                // ── Rafale d'écriture page-ouverte : 1 WRITE/cycle (même donnée), puis precharge ──
                S_BWRITE: begin
                    if (b_iss < l_blen) begin
                        setcmd(C_WRITE); ba<=l_ba; a<={2'b00, 1'b0, b_col};
                        dq_oe<=1'b1; dq_out<=a_wdata; dqm<=2'b00;
                        b_col<=b_col+10'd1; b_iss<=b_iss+10'd1;
                    end else begin
                        setcmd(C_PRE); ba<=l_ba; a<=13'h0000; tmr<=T_RP; st<=S_RECOV;
                    end
                end
                S_RW: if (tmr==16'd0) st<=S_RDCAP;        // fin latence CAS
                S_RDCAP: begin
                    rd_data<=dq; rd_valid<=1'b1; tmr<=T_RP; st<=S_RECOV;
                end

                // ── Lecture rafale page-ouverte : émet 1 READ/cycle, capture CAS derrière ──
                S_BURST: begin
                    if (b_iss < l_blen) begin            // émet le READ suivant
                        setcmd(C_READ); ba<=l_ba; a<={2'b00, 1'b0, b_col};
                        b_col<=b_col+10'd1; b_iss<=b_iss+10'd1;
                        b_pend <= {b_pend[6:0], 1'b1};
                    end else
                        b_pend <= {b_pend[6:0], 1'b0};
                    if (b_pend[CAP_POS]) begin           // capture le mot revenu
                        rd_data<=dq; rd_valid<=1'b1; b_cap<=b_cap+10'd1;
                        if (b_cap == l_blen-10'd1) begin // dernier mot → precharge banque
                            setcmd(C_PRE); ba<=l_ba; a<=13'h0000;
                            tmr<=T_RP; st<=S_RECOV;
                        end
                    end
                end
                S_RECOV: if (tmr==16'd0) st<=S_IDLE;
            endcase
        end
    end

endmodule
