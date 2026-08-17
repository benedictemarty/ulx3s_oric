// Interface Microdisc (US-DISK.2) — fidèle à ~/Oric1/src/io/microdisc.c :
// relie le FDC WD1793 au bus de l'Oric.
//
//   $0310-$0313 : registres du WD1793
//   $0314 W     : contrôle — b0 INTENA, b1 /ROMDIS (0 = ROM BASIC coupée),
//                 b3 densité (ignoré), b4 side, b6:5 drive, b7 /EPROM
//                 (0 = overlay EPROM actif)
//   $0314 R     : b7 = /INTRQ (actif bas), b6:0 = 1
//   $0318 R     : b7 = /DRQ  (actif bas), b6:0 = 1
//
// Au boot/reset : ROMDIS actif + EPROM visible (la machine démarre sur
// l'EPROM Microdisc, comme le vrai matériel). EPROM 8 Ko (microdis.hex)
// mappée $E000-$FFFF quand romdis && diskrom ; $C000-$DFFF (et $E000-$FFFF
// hors EPROM) retombent sur la RAM overlay via la sémantique /ROMDIS
// existante d'oric_atmos.
//
// v1 : drive 0 uniquement (les bits drive sont décodés mais seuls les accès
// au drive 0 voient une disquette), side transmis au FDC.

module microdisc #(
    parameter ROM_FILE = "microdis.hex",
    // Paramètres de timing du WD1793 (réduits en simulation)
    parameter REV_CYCLES    = 200000,
    parameter INDEX_CYCLES  = 4000,
    parameter SETTLE_CYCLES = 30000,
    parameter RNF_CYCLES    = 1000000
)(
    input             clk,
    input             cen,           // tick 1 MHz (domaine CPU)
    input             rst,
    input             enable,        // interface « branchée » (SW1) —
                                     // à 0 : transparente, aucun décodage

    // Bus CPU : adresse complète, cs page 3 déjà décodée par oric_atmos
    input      [15:0] a,
    input             io_sel,        // $0310-$031B (page 3, hors VIA/ACIA)
    input             we,
    input      [7:0]  din,
    output reg [7:0]  dout,
    output            dout_valid,   // ce module répond à cette adresse

    // Overlay EPROM : $E000-$FFFF quand actif
    output            romdis,       // coupe la ROM BASIC (vers oric_atmos)
    output            eprom_sel,    // l'EPROM répond (a dans $E000-$FFFF)
    output     [7:0]  eprom_dout,
    input      [13:0] rom_a,        // = a[13:0] (lecture combinée au fetch)

    output            irq,          // vers le 6502 (si INTENA)

    // Fournisseur de secteurs (US-DISK.3 ; bouchon : disk_present = 0)
    input             disk_present,
    input      [6:0]  n_tracks,
    input      [4:0]  n_spt,
    output     [6:0]  req_track,
    output            req_side,
    input             trk_loading,
    output     [4:0]  sec_id,
    input             sec_valid,
    output     [8:0]  sec_addr,
    input      [7:0]  sec_byte,
    // Écriture de secteur (US-DISK.5 phase 4) — vers dsk_track
    output            sec_we,
    output     [7:0]  sec_wr_data,
    output            wr_commit,
    input             wr_busy,
    input             wr_ok,
    input             wr_err
);

    // ------------------------------------------------------------------
    // Registre de contrôle ($0314) — réf. microdisc_write
    // ------------------------------------------------------------------
    reg        intena, ctl_romdis, diskrom, side;
    reg [1:0]  drive;

    // Boot : ROMDIS + EPROM actifs (réf. microdisc_init/reset)
    always @(posedge clk) begin
        if (rst) begin
            intena     <= 1'b0;
            ctl_romdis <= 1'b1;      // ROM BASIC coupée
            diskrom    <= 1'b1;      // overlay EPROM visible
            side       <= 1'b0;
            drive      <= 2'd0;
        end else if (cen && enable && io_sel && we && a[3:0] == 4'h4) begin
            intena     <= din[0];
            ctl_romdis <= (din[1] == 1'b0);   // b1 : 0 = ROM coupée
            side       <= din[4];
            drive      <= din[6:5];
            diskrom    <= (din[7] == 1'b0);   // b7 : 0 = overlay actif
        end
    end

    assign romdis = enable && ctl_romdis;

    // ------------------------------------------------------------------
    // WD1793 ($0310-$0313)
    // ------------------------------------------------------------------
    wire        fdc_cs = enable && io_sel && (a[3:2] == 2'b00); // $0310-$0313
    wire [7:0]  fdc_dout;
    wire        fdc_intrq, fdc_drq;

    // v1 : seule l'unité 0 a une disquette
    wire        present0 = disk_present && (drive == 2'd0);

    wd1793 #(.REV_CYCLES(REV_CYCLES), .INDEX_CYCLES(INDEX_CYCLES),
             .SETTLE_CYCLES(SETTLE_CYCLES), .RNF_CYCLES(RNF_CYCLES)) fdc (
        .clk(clk), .cen(cen), .rst(rst),
        .cs(fdc_cs), .addr(a[1:0]), .we(we), .din(din), .dout(fdc_dout),
        .intrq(fdc_intrq), .drq(fdc_drq),
        .side(side),
        .disk_present(present0), .n_tracks(n_tracks), .n_spt(n_spt),
        .req_track(req_track), .req_side(req_side), .trk_loading(trk_loading),
        .sec_id(sec_id), .sec_valid(sec_valid),
        .sec_addr(sec_addr), .sec_byte(sec_byte),
        .sec_we(sec_we), .sec_wr_data(sec_wr_data), .wr_commit(wr_commit),
        .wr_busy(wr_busy), .wr_ok(wr_ok), .wr_err(wr_err)
    );

    // IRQ CPU si INTENA (réf. : INTRQ actif ET intena)
    assign irq = enable && intena && fdc_intrq;

    // ------------------------------------------------------------------
    // Lecture des registres (réf. microdisc_read) — conventions actives-bas
    // ------------------------------------------------------------------
    always @(*) begin
        if (a[3:2] == 2'b00)
            dout = fdc_dout;                          // $0310-$0313
        else if (a[3:0] == 4'h4)
            dout = {~fdc_intrq, 7'h7F};               // $0314 : /INTRQ
        else if (a[3:0] == 4'h8)
            dout = {~fdc_drq, 7'h7F};                 // $0318 : /DRQ
        else
            dout = 8'hFF;
    end
    assign dout_valid = enable && io_sel;

    // ------------------------------------------------------------------
    // EPROM 8 Ko, visible $E000-$FFFF quand romdis && diskrom
    // ------------------------------------------------------------------
    reg [7:0] eprom [0:8191];
    initial $readmemh(ROM_FILE, eprom);

    reg [7:0] eprom_q;
    always @(posedge clk) eprom_q <= eprom[rom_a[12:0]];
    assign eprom_dout = eprom_q;
    assign eprom_sel  = enable && ctl_romdis && diskrom && (a[15:13] == 3'b111);

endmodule
