// FDC WD1793 (US-DISK.1) — fidèle à la référence ~/Oric1/src/storage/disk.c
// (modèle FDC_TIMING_REAL) : registres command/track/sector/data, commandes
// type I (restore/seek/step, délais pas-à-pas r1r0 + settling V), type II
// (read sector, simple et multiple, latence rotationnelle), type III (read
// address), type IV (force interrupt), status par type avec index pulse
// vivant, DRQ/INTRQ retardés, RNF après 5 tours d'index.
//
// v1 LECTURE SEULE : les commandes d'écriture répondent « write protect »
// (comme une disquette protégée — comportement réel du WD1793).
//
// Les données viennent d'un fournisseur de secteurs (buffer de piste + table
// d'IDs, cf. US-DISK.3) :
//   - req_track/req_side : piste/face que le fournisseur doit charger ;
//   - trk_loading : haut pendant le chargement SD — les délais du FDC sont
//     gelés (le délai mécanique du seek absorbe le temps réel du transfert) ;
//   - sec_id (= secteur courant, registré) -> sec_valid (présent dans la
//     table de la piste chargée, combinatoire) ; la validité est évaluée à
//     l'échéance du DRQ différé (sec_id posé depuis longtemps) ;
//   - sec_addr (offset 0..255) -> sec_byte (BRAM synchrone, 1 clk — large
//     marge : les octets sont consommés au rythme DRQ, ≥ 32 ticks cen).
//
// Tous les délais sont en ticks `cen` (1 MHz nominal ; en turbo tout le
// domaine accélère de concert, cohérence préservée comme pour la VIA).

module wd1793 #(
    parameter REV_CYCLES    = 200000,   // 1 tour à 300 RPM (1 MHz)
    parameter INDEX_CYCLES  = 4000,     // largeur d'impulsion d'index (~4 ms)
    parameter SETTLE_CYCLES = 30000,    // 30 ms (flags E/V)
    parameter RNF_CYCLES    = 1000000   // 5 tours d'index
)(
    input             clk,
    input             cen,          // tick 1 MHz (domaine CPU)
    input             rst,

    // Bus CPU (registres 0..3) : dout combinatoire, effets de bord (pop de
    // DATA, clear d'INTRQ sur STATUS) appliqués au tick cen.
    input             cs,
    input      [1:0]  addr,
    input             we,
    input      [7:0]  din,
    output reg [7:0]  dout,
    output reg        intrq,        // niveau (le wrapper Microdisc met en forme)
    output reg        drq,

    // Contrôle Microdisc
    input             side,

    // Fournisseur de secteurs
    input             disk_present,
    input      [6:0]  n_tracks,     // géométrie du .dsk (en-tête MFM_DISK)
    input      [4:0]  n_spt,        // secteurs/piste (17)
    output reg [6:0]  req_track,
    output            req_side,
    input             trk_loading,
    output     [4:0]  sec_id,
    input             sec_valid,
    output     [8:0]  sec_addr,
    input      [7:0]  sec_byte,

    // Écriture de secteur (US-DISK.5 phase 4) : pousse les octets reçus du CPU
    // dans le buffer de piste de dsk_track (sec_we), puis demande le write-back
    // (wr_commit) et attend wr_ok/wr_err.
    output reg        sec_we,
    output reg [7:0]  sec_wr_data,
    output reg        wr_commit,
    input             wr_busy,
    input             wr_ok,
    input             wr_err
);

    // Bits de status (réf. disk.h)
    localparam ST_BUSY = 8'h01, STI_PULSE = 8'h02, ST_DRQ = 8'h02,
               STI_TRK0 = 8'h04, STI_SEEK_ERR = 8'h10, ST_RNF = 8'h10,
               STI_HEADL = 8'h20, ST_WPROT = 8'h40, ST_NOT_READY = 8'h80;

    localparam OP_NONE = 3'd0, OP_RD_SEC = 3'd1, OP_RD_SECS = 3'd2,
               OP_RD_ADDR = 3'd3, OP_WR_SEC = 3'd4, OP_WR_WB = 3'd5;
    reg [2:0]  currentop;

    reg [7:0]  track, sector, data, status;
    reg        status_type1;
    reg        direction;                 // 0 = vers l'intérieur

    reg [17:0] rot_pos = 18'd0;           // le plateau tourne en permanence
                                          // (init à la mise sous tension ;
                                          // PAS remis à zéro par rst, réf.)

    // Délais différés (ticks cen). Seek max : 79 pas × 30 ms = 2,37 M -> 22 bits.
    reg [21:0] delayed_int, delayed_drq;
    reg        di_valid, dd_first;        // dd_first : 1er DRQ d'une commande
    reg [7:0]  di_status;

    reg [8:0]  cur_offset;                // 0..255
    reg [4:0]  cur_sec;

    assign req_side = side;
    assign sec_id   = cur_sec;
    assign sec_addr = cur_offset;

    // ------------------------------------------------------------------
    // Latence rotationnelle (réf. fdc_rot_wait) : tranches angulaires
    // égales, données à 1/8 de tranche après l'ID.
    // ------------------------------------------------------------------
    wire [17:0] slice = REV_CYCLES / ((n_spt != 0) ? n_spt : 5'd17);
    function [17:0] rot_wait;
        input [4:0] sid;
        reg [22:0] target, w;
        begin
            target = (sid - 5'd1) * slice + slice / 8;
            if (target >= REV_CYCLES) target = target - REV_CYCLES;
            if (target >= rot_pos) w = target - rot_pos;
            else                   w = target + REV_CYCLES - rot_pos;
            rot_wait = (w < 2) ? 18'd2 : w[17:0];
        end
    endfunction

    // Délais de pas type I (r1r0), ms -> ticks (réf. fdc_step_rate_ms)
    function [21:0] step_cycles;
        input [1:0] r;
        begin
            case (r)
                2'd0: step_cycles = 22'd6000;
                2'd1: step_cycles = 22'd12000;
                2'd2: step_cycles = 22'd20000;
                2'd3: step_cycles = 22'd30000;
            endcase
        end
    endfunction

    wire [6:0] max_track = (n_tracks != 0) ? n_tracks - 7'd1 : 7'd0;

    // Status type I « vivant » (réf. fdc_read STATUS, mode REAL)
    wire [7:0] live_status_t1 =
        (status & ~(STI_PULSE | STI_TRK0))
        | ((disk_present && rot_pos < INDEX_CYCLES) ? STI_PULSE : 8'h00)
        | ((req_track == 7'd0) ? STI_TRK0 : 8'h00);

    // dout combinatoire : la lecture de DATA pendant un op renvoie l'octet
    // COURANT (réf. : fdc->data = buf[offset++] puis retour) — le pop (avance
    // d'offset, gestion DRQ) s'applique au tick cen du même accès.
    always @(*) begin
        case (addr)
            2'd0: dout = (status_type1 && !(status[0])) ? live_status_t1 : status;
            2'd1: dout = track;
            2'd2: dout = sector;
            2'd3: dout = (currentop == OP_RD_SEC || currentop == OP_RD_SECS)
                             ? sec_byte
                         : (currentop == OP_RD_ADDR)
                             ? addr_field(cur_offset[2:0])
                             : data;
        endcase
    end

    // Cible de seek et nombre de pas (combinatoire, pour rester en
    // non-bloquant dans le séquenceur)
    reg  [6:0] seek_tgt_r;
    reg  [7:0] seek_cmd_r;
    reg        seek_req;                  // seek demandé ce tick
    wire [6:0] seek_tgt  = (seek_tgt_r > max_track) ? max_track : seek_tgt_r;
    wire       seek_err  = (seek_tgt_r > max_track);
    wire [6:0] seek_diff = (seek_tgt > req_track) ? seek_tgt - req_track
                                                  : req_track - seek_tgt;
    wire [6:0] seek_steps = (seek_diff == 0) ? 7'd1 : seek_diff;

    // ------------------------------------------------------------------
    // Séquenceur principal (tout au tick cen)
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            status <= 8'd0; status_type1 <= 1'b0;
            track <= 8'd0; sector <= 8'd1; data <= 8'd0;
            req_track <= 7'd0; direction <= 1'b0;
            currentop <= OP_NONE; cur_offset <= 9'd0; cur_sec <= 5'd1;
            delayed_int <= 22'd0; delayed_drq <= 22'd0;
            di_valid <= 1'b0; di_status <= 8'd0; dd_first <= 1'b0;
            intrq <= 1'b0; drq <= 1'b0;
            seek_req <= 1'b0;
            sec_we <= 1'b0; wr_commit <= 1'b0; sec_wr_data <= 8'd0;
            // rot_pos non remis à zéro : le plateau tourne toujours
        end else if (cen) begin
            seek_req <= 1'b0;
            sec_we <= 1'b0; wr_commit <= 1'b0;   // pulses (1 tick cen)

            // Rotation permanente (300 RPM)
            rot_pos <= (rot_pos == REV_CYCLES - 1) ? 18'd0 : rot_pos + 18'd1;

            // ---- Application d'un seek demandé au tick précédent ----
            if (seek_req) begin
                if (disk_present) begin
                    di_status <= STI_HEADL
                               | (seek_err ? STI_SEEK_ERR : STI_PULSE)
                               | ((seek_tgt == 7'd0) ? STI_TRK0 : 8'h00);
                    di_valid  <= 1'b1;
                    delayed_int <= seek_steps * step_cycles(seek_cmd_r[1:0])
                                 + (seek_cmd_r[2] ? SETTLE_CYCLES : 22'd0);
                    req_track <= seek_tgt;
                    track     <= {1'b0, seek_tgt};
                end else begin
                    intrq  <= 1'b1;
                    track  <= 8'd0;
                    status <= ST_NOT_READY | STI_SEEK_ERR;
                end
            end

            // ---- INTRQ différé (gelé pendant un chargement de piste) ----
            if (delayed_int != 0 && !trk_loading && !seek_req) begin
                delayed_int <= delayed_int - 22'd1;
                if (delayed_int == 22'd1) begin
                    if (di_valid) begin
                        status  <= di_status;
                        di_valid <= 1'b0;
                    end
                    intrq <= 1'b1;
                end
            end

            // ---- DRQ différé : à l'échéance, vérifier le secteur (la table
            // du fournisseur est alignée : cur_sec posé depuis longtemps) ----
            if (delayed_drq != 0 && !trk_loading) begin
                delayed_drq <= delayed_drq - 22'd1;
                if (delayed_drq == 22'd1) begin
                    if ((currentop == OP_RD_SEC || currentop == OP_RD_SECS ||
                         currentop == OP_WR_SEC) && !sec_valid) begin
                        if (dd_first || currentop == OP_RD_SEC ||
                            currentop == OP_WR_SEC) begin
                            // 1er secteur introuvable : RNF (réf.)
                            drq <= 1'b0;
                            currentop <= OP_NONE;
                            status <= ST_BUSY;
                            di_status <= ST_RNF; di_valid <= 1'b1;
                            delayed_int <= RNF_CYCLES;
                        end else begin
                            // multi-secteur : fin de piste, fin propre
                            currentop <= OP_NONE;
                            status <= 8'd0;
                            intrq <= 1'b1;
                        end
                    end else begin
                        status <= (status & ~ST_NOT_READY) | ST_DRQ;
                        drq <= 1'b1;
                        // écriture : avancer la position AVANT le prochain octet
                        // (hors du pulse sec_we -> pas de course avec dsk_track)
                        if (currentop == OP_WR_SEC && !dd_first)
                            cur_offset <= cur_offset + 9'd1;
                        dd_first <= 1'b0;
                    end
                end
            end

            // ---- Fin de write-back (US-DISK.5 ph.4) : attendre dsk_track ----
            if (currentop == OP_WR_WB && !wr_busy && !wr_commit) begin
                if (wr_err) status <= ST_WPROT;    // échec write-back
                else        status <= 8'd0;        // succès
                intrq <= 1'b1;
                currentop <= OP_NONE;
            end

            // ---- Accès registres ----
            if (cs && we) begin
                case (addr)
                    2'd0: begin                    // COMMAND
                        intrq <= 1'b0;
                        case (din[7:5])
                            3'b000: begin          // Restore / Seek
                                status <= ST_BUSY | (din[3] ? STI_HEADL : 8'h00);
                                status_type1 <= 1'b1;
                                seek_tgt_r <= din[4] ? data[6:0] : 7'd0;
                                seek_cmd_r <= din; seek_req <= 1'b1;
                                currentop <= OP_NONE;
                            end
                            3'b001: begin          // Step
                                status <= ST_BUSY | (din[3] ? STI_HEADL : 8'h00);
                                status_type1 <= 1'b1;
                                seek_tgt_r <= direction
                                    ? (req_track != 0 ? req_track - 7'd1 : 7'd0)
                                    : req_track + 7'd1;
                                seek_cmd_r <= din; seek_req <= 1'b1;
                                currentop <= OP_NONE;
                            end
                            3'b010: begin          // Step-in
                                status <= ST_BUSY | (din[3] ? STI_HEADL : 8'h00);
                                status_type1 <= 1'b1;
                                direction <= 1'b0;
                                seek_tgt_r <= req_track + 7'd1;
                                seek_cmd_r <= din; seek_req <= 1'b1;
                                currentop <= OP_NONE;
                            end
                            3'b011: begin          // Step-out
                                status <= ST_BUSY | (din[3] ? STI_HEADL : 8'h00);
                                status_type1 <= 1'b1;
                                direction <= 1'b1;
                                seek_tgt_r <= req_track != 0 ? req_track - 7'd1 : 7'd0;
                                seek_cmd_r <= din; seek_req <= 1'b1;
                                currentop <= OP_NONE;
                            end
                            3'b100: begin          // Read sector (II)
                                status_type1 <= 1'b0;
                                cur_offset <= 9'd0;
                                cur_sec <= sector[4:0];
                                if (!disk_present || sector == 8'd0 ||
                                    sector > {3'd0, n_spt}) begin
                                    drq <= 1'b0;
                                    currentop <= OP_NONE;
                                    status <= ST_BUSY;
                                    di_status <= ST_RNF; di_valid <= 1'b1;
                                    delayed_int <= RNF_CYCLES;
                                end else begin
                                    status <= ST_BUSY | ST_NOT_READY;
                                    delayed_drq <= {4'd0, rot_wait(sector[4:0])}
                                                 + (din[2] ? SETTLE_CYCLES : 22'd0);
                                    dd_first <= 1'b1;
                                    currentop <= din[4] ? OP_RD_SECS : OP_RD_SEC;
                                end
                            end
                            3'b101: begin          // Write sector (II)
                                status_type1 <= 1'b0;
                                cur_offset <= 9'd0;
                                cur_sec <= sector[4:0];
                                if (!disk_present || sector == 8'd0 ||
                                    sector > {3'd0, n_spt}) begin
                                    drq <= 1'b0;
                                    currentop <= OP_NONE;
                                    status <= ST_BUSY;
                                    di_status <= ST_RNF; di_valid <= 1'b1;
                                    delayed_int <= RNF_CYCLES;
                                end else begin
                                    status <= ST_BUSY | ST_NOT_READY;
                                    delayed_drq <= {4'd0, rot_wait(sector[4:0])}
                                                 + (din[2] ? SETTLE_CYCLES : 22'd0);
                                    dd_first <= 1'b1;
                                    currentop <= OP_WR_SEC;
                                end
                            end
                            3'b110: begin
                                if (!din[4]) begin // Read address (III)
                                    status_type1 <= 1'b0;
                                    cur_offset <= 9'd0;
                                    cur_sec <= 5'd1;
                                    if (!disk_present) begin
                                        drq <= 1'b0;
                                        currentop <= OP_NONE;
                                        status <= ST_BUSY;
                                        di_status <= ST_RNF; di_valid <= 1'b1;
                                        delayed_int <= RNF_CYCLES;
                                    end else begin
                                        status <= ST_NOT_READY | ST_BUSY;
                                        delayed_drq <= {4'd0, rot_wait(5'd1)};
                                        dd_first <= 1'b1;
                                        currentop <= OP_RD_ADDR;
                                    end
                                end else begin     // Force interrupt (IV)
                                    status <= 8'd0;
                                    status_type1 <= 1'b1;
                                    drq <= 1'b0;
                                    intrq <= 1'b1;
                                    delayed_int <= 22'd0;
                                    delayed_drq <= 22'd0;
                                    di_valid <= 1'b0;
                                    currentop <= OP_NONE;
                                end
                            end
                            3'b111: begin          // Read/Write track : v1 non
                                status_type1 <= 1'b0;              // supporté
                                if (din[4]) begin
                                    status <= ST_WPROT;
                                    intrq <= 1'b1;
                                end else begin
                                    drq <= 1'b0;
                                    status <= ST_BUSY;
                                    di_status <= ST_RNF; di_valid <= 1'b1;
                                    delayed_int <= RNF_CYCLES;
                                end
                                currentop <= OP_NONE;
                            end
                        endcase
                    end
                    2'd1: track  <= din;
                    2'd2: sector <= din;
                    2'd3: begin                    // DATA : write sector si actif
                        data <= din;
                        if (currentop == OP_WR_SEC && drq) begin
                            sec_we <= 1'b1;         // pousse l'octet dans tbuf
                            sec_wr_data <= din;     // (sec_addr=cur_offset, sec_id=cur_sec)
                            status <= status & ~ST_DRQ;
                            drq <= 1'b0;
                            if (cur_offset == 9'd255) begin
                                wr_commit <= 1'b1;  // secteur complet -> write-back
                                status <= ST_BUSY;
                                currentop <= OP_WR_WB;
                            end else begin
                                delayed_drq <= 22'd32;   // prochain DRQ (incrémente
                                                         // cur_offset à l'échéance)
                            end
                        end
                    end
                endcase
            end else if (cs && !we) begin
                case (addr)
                    2'd0: intrq <= 1'b0;           // lecture STATUS
                    2'd3: begin                    // lecture DATA : pop
                        case (currentop)
                            OP_RD_SEC, OP_RD_SECS: if (drq) begin
                                data <= sec_byte;
                                status <= status & ~ST_DRQ;
                                drq <= 1'b0;
                                if (cur_offset == 9'd255) begin
                                    if (currentop == OP_RD_SECS) begin
                                        sector <= sector + 8'd1;
                                        cur_sec <= cur_sec + 5'd1;
                                        cur_offset <= 9'd0;
                                        dd_first <= 1'b0;
                                        delayed_drq <= {4'd0, rot_wait(cur_sec + 5'd1)};
                                    end else begin
                                        delayed_int <= 22'd32;
                                        di_status <= 8'd0; di_valid <= 1'b1;
                                        currentop <= OP_NONE;
                                    end
                                end else begin
                                    cur_offset <= cur_offset + 9'd1;
                                    delayed_drq <= 22'd32;
                                end
                            end
                            OP_RD_ADDR: if (drq) begin
                                data <= addr_field(cur_offset[2:0]);
                                status <= status & ~ST_DRQ;
                                drq <= 1'b0;
                                if (cur_offset == 9'd5) begin
                                    delayed_int <= 22'd20;
                                    di_status <= 8'd0; di_valid <= 1'b1;
                                    currentop <= OP_NONE;
                                end else begin
                                    cur_offset <= cur_offset + 9'd1;
                                    delayed_drq <= 22'd32;
                                end
                            end
                            default: ;
                        endcase
                    end
                    default: ;
                endcase
            end
        end
    end

    // Champ d'adresse synthétique (réf. OP_READ_ADDRESS)
    function [7:0] addr_field;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: addr_field = {1'b0, req_track};
                3'd1: addr_field = {7'd0, side};
                3'd2: addr_field = sector;
                3'd3: addr_field = 8'd1;           // taille : 1 = 256 octets
                default: addr_field = 8'd0;
            endcase
        end
    endfunction

endmodule
