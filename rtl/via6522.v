// VIA 6522 — implémentation Verilog pour le core Oric Atmos ULX3S.
// Réfère : ~/Oric1/src/io/via6522.c (émulateur de référence).
// Couvre : ports A/B + DDR, T1 (one-shot/free-run), T2 (one-shot),
// IFR/IER, PCR (CA2/CB2 modes manuels — suffisant pour le bus AY de l'Oric),
// latching d'entrée simple. Shift register : registre accessible mais sans
// décalage (cassette hors périmètre v1, cf. docs/BACKLOG.md).

module via6522 (
    input             clk,
    input             cen,       // enable 1 MHz (cycle CPU)
    input             rst,

    input       [3:0] addr,
    input             cs,
    input             we,
    input       [7:0] din,
    output reg  [7:0] dout,
    output            irq,       // actif haut (vers IRQ 6502)

    input       [7:0] pa_in,
    output      [7:0] pa_out,
    output      [7:0] ddra_o,
    input       [7:0] pb_in,
    output      [7:0] pb_out,
    output      [7:0] ddrb_o,

    input             ca1_in,
    output reg        ca2_out,
    input             cb1_in,
    output reg        cb2_out
);

    // Registres
    reg [7:0] orb, ora, ddrb, ddra;
    reg [7:0] t1ll, t1lh;          // latch T1
    reg [15:0] t1c;                // compteur T1
    reg        t1_oneshot_fired;
    reg [7:0] t2ll;
    reg [15:0] t2c;
    reg        t2_fired;
    reg [7:0] sr, acr, pcr;
    reg [6:0] ifr, ier;

    // Détection de fronts CA1/CB1
    reg ca1_q, cb1_q;
    wire ca1_edge = pcr[0] ? (ca1_in & ~ca1_q) : (~ca1_in & ca1_q);
    wire cb1_edge = pcr[4] ? (cb1_in & ~cb1_q) : (~cb1_in & cb1_q);

    localparam IFR_CA2 = 0, IFR_CA1 = 1, IFR_SR = 2, IFR_CB2 = 3,
               IFR_CB1 = 4, IFR_T2 = 5, IFR_T1 = 6;

    assign irq    = |(ifr & ier);
    assign pa_out = ora | ~ddra;   // bits en entrée relâchés à 1 (bus tiré haut)
    assign pb_out = orb | ~ddrb;
    assign ddra_o = ddra;
    assign ddrb_o = ddrb;

    wire [7:0] pa_mix = (ora & ddra) | (pa_in & ~ddra);
    wire [7:0] pb_mix = (orb & ddrb) | (pb_in & ~ddrb);

    // CA2/CB2 : modes manuels du PCR (110 = bas, 111 = haut).
    // L'Oric ne se sert que de ces modes pour piloter BC1/BDIR de l'AY.
    always @* begin
        case (pcr[3:1])
            3'b110: ca2_out = 1'b0;
            3'b111: ca2_out = 1'b1;
            default: ca2_out = 1'b1;
        endcase
        case (pcr[7:5])
            3'b110: cb2_out = 1'b0;
            3'b111: cb2_out = 1'b1;
            default: cb2_out = 1'b1;
        endcase
    end

    // Lecture registrée (brise la boucle combinatoire DI->AB du 6502 d'Arlet ;
    // l'adresse CPU est stable pendant tout le cycle 1 MHz, la donnée est
    // valide dès le 2e cycle de clk). Effets de bord appliqués au front cen.
    always @(posedge clk) begin
        case (addr)
            4'h0: dout <= pb_mix;
            4'h1: dout <= pa_mix;
            4'h2: dout <= ddrb;
            4'h3: dout <= ddra;
            4'h4: dout <= t1c[7:0];
            4'h5: dout <= t1c[15:8];
            4'h6: dout <= t1ll;
            4'h7: dout <= t1lh;
            4'h8: dout <= t2c[7:0];
            4'h9: dout <= t2c[15:8];
            4'hA: dout <= sr;
            4'hB: dout <= acr;
            4'hC: dout <= pcr;
            4'hD: dout <= {|(ifr & ier), ifr};
            4'hE: dout <= {1'b1, ier};
            4'hF: dout <= pa_mix;
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            orb <= 0; ora <= 0; ddrb <= 0; ddra <= 0;
            t1ll <= 8'hFF; t1lh <= 8'hFF; t1c <= 16'hFFFF;
            t2ll <= 8'hFF; t2c <= 16'hFFFF;
            sr <= 0; acr <= 0; pcr <= 0;
            ifr <= 0; ier <= 0;
            t1_oneshot_fired <= 1'b1;
            t2_fired <= 1'b1;
            ca1_q <= 1'b1; cb1_q <= 1'b1;
        end else if (cen) begin
            ca1_q <= ca1_in;
            cb1_q <= cb1_in;
            if (ca1_edge) ifr[IFR_CA1] <= 1'b1;
            if (cb1_edge) ifr[IFR_CB1] <= 1'b1;

            // Timer 1
            if (t1c == 16'd0) begin
                if (acr[6]) begin        // free-run : IRQ + rechargement
                    ifr[IFR_T1] <= 1'b1;
                    t1c <= {t1lh, t1ll};
                end else begin           // one-shot : IRQ une seule fois
                    if (!t1_oneshot_fired) ifr[IFR_T1] <= 1'b1;
                    t1_oneshot_fired <= 1'b1;
                    t1c <= t1c - 16'd1;
                end
            end else
                t1c <= t1c - 16'd1;

            // Timer 2 (mode timer ; le mode comptage PB6 n'est pas requis v1)
            if (!acr[5]) begin
                if (t2c == 16'd0) begin
                    if (!t2_fired) ifr[IFR_T2] <= 1'b1;
                    t2_fired <= 1'b1;
                end
                t2c <= t2c - 16'd1;
            end

            // Accès registre
            if (cs) begin
                if (we) begin
                    case (addr)
                        4'h0: begin orb <= din; ifr[IFR_CB1] <= 0; ifr[IFR_CB2] <= 0; end
                        4'h1: begin ora <= din; ifr[IFR_CA1] <= 0; ifr[IFR_CA2] <= 0; end
                        4'h2: ddrb <= din;
                        4'h3: ddra <= din;
                        4'h4: t1ll <= din;
                        4'h5: begin
                            t1lh <= din;
                            t1c  <= {din, t1ll};
                            ifr[IFR_T1] <= 0;
                            t1_oneshot_fired <= 0;
                        end
                        4'h6: t1ll <= din;
                        4'h7: begin t1lh <= din; ifr[IFR_T1] <= 0; end
                        4'h8: t2ll <= din;
                        4'h9: begin
                            t2c <= {din, t2ll};
                            ifr[IFR_T2] <= 0;
                            t2_fired <= 0;
                        end
                        4'hA: begin sr <= din; ifr[IFR_SR] <= 0; end
                        4'hB: acr <= din;
                        4'hC: pcr <= din;
                        4'hD: ifr <= ifr & ~din[6:0];
                        4'hE: ier <= din[7] ? (ier | din[6:0]) : (ier & ~din[6:0]);
                        4'hF: begin ora <= din; end
                    endcase
                end else begin
                    case (addr)
                        4'h0: begin ifr[IFR_CB1] <= 0; ifr[IFR_CB2] <= 0; end
                        4'h1: begin ifr[IFR_CA1] <= 0; ifr[IFR_CA2] <= 0; end
                        4'h4: ifr[IFR_T1] <= 0;
                        4'h8: ifr[IFR_T2] <= 0;
                        4'hA: ifr[IFR_SR] <= 0;
                        default: ;
                    endcase
                end
            end
        end
    end

endmodule
