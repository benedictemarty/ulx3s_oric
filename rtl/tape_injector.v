// Injecteur cassette .tap : reçoit un fichier .tap par UART (contrôle de flux
// par crédits) et génère la forme d'onde cassette de l'Oric sur `tape_line`
// (relié à tape_in -> VIA CB1). Modulation strictement conforme au générateur
// de référence ~/Oric1/src/io/cassette.c :
//
//   - Trame de 14 bits, LSB d'abord : start(0), 8 data, parité IMPAIRE, 4 stop(1).
//   - Amorce : LEADER_SYNCS trames de l'octet de synchro 0x16, puis les données.
//   - Fichiers MULTI-PARTIES : le .tap ne garde que ~3 octets 0x16 entre les
//     blocs (la longue amorce de la vraie bande est supprimée). Or entre deux
//     parties l'Oric traite le bloc chargé moteur actif : les 3 syncs passent
//     dans le vide et le CLOAD suivant reste en « Searching... ». L'injecteur
//     parse donc la structure des blocs (sync -> 0x24 -> en-tête 9 octets avec
//     adresses fin/début -> nom terminé par 0x00 -> données de fin-début+1
//     octets) et RÉ-INSÈRE une longue amorce (INTER_SYNCS trames 0x16) à
//     chaque frontière de bloc. Sans risque : des 0x16 devant une amorce sont
//     transparents pour la ROM, et le parsing garantit de ne jamais insérer au
//     milieu des données. En cas de flux non conforme, le parseur se
//     désynchronise sans effet (aucune insertion = comportement d'avant).
//   - Chaque bit = 2 demi-pulses ; le front montant tombe toujours à +HALF_ONE :
//       demi 0 : niveau BAS pendant HALF_ONE ;
//       demi 1 : niveau HAUT pendant HALF_ONE (bit '1') ou HALF_LONG (bit '0').
//     -> période bit '1' = 2*HALF_ONE (courte), bit '0' = HALF_ONE+HALF_LONG (longue).
//   - Repos HAUT. La bande n'avance que lorsque `motor` (VIA PB6) est actif.
//
// Protocole UART (octets reçus, une fois routés ici) :
//   0x01, len_lo, len_hi, <len octets .tap>
// Contrôle de flux : pour chaque octet que le FIFO peut accepter (sans dépasser
// `len`), on émet un octet de crédit 0x5A vers le PC (uart_tx). Le PC envoie
// exactement un octet .tap par crédit reçu -> jamais de débordement, et l'UART
// (115200) suit largement le débit bande (~137 o/s).

module tape_injector #(
    // Durées en cycles de clk. Défaut 25 MHz : 208 µs et 416 µs.
    parameter CYC_HALF_ONE  = 5200,
    parameter CYC_HALF_LONG = 10400,
    // Mode turbo : mêmes durées × TURBO_DIV/DIV (6/25) — la bande accélère du
    // même ratio que le domaine CPU/VIA, donc en cycles CPU rien ne change
    // pour la routine CLOAD (Timer 2). 5200×6/25 = 1248 ; 10400×6/25 = 2496.
    parameter CYC_HALF_ONE_T  = 1248,
    parameter CYC_HALF_LONG_T = 2496,
    // STOP BITS SUPPLÉMENTAIRES en TURBO, sur les trames de DONNÉES uniquement
    // (trame 14 -> 18 bits : 4 bits '1' de plus, avec leurs fronts). D'après le
    // désassemblage de GetTapeByte ($E6C9, ROM 1.1b) : la ROM BRÛLE un front
    // (mesure jetée — c'est son amortisseur anti-retard), SAUTE les périodes
    // courtes (stops '1') puis prend la première période longue comme start.
    // Si son traitement inter-octets + une IRQ T1 dépassent les 4 stops
    // (1664 cycles), le start est fusionné-brûlé et elle raccroche 2 bits trop
    // tard (octet faux -> « Errors found »). 4 stops de plus => fenêtre de
    // 3328 cycles. Un GAP SILENCIEUX ne convient PAS : le front qui le termine
    // (= le vrai start) se fait manger par le brûleur (vérifié en sim). Des
    // '1' supplémentaires ne gênent ni la chasse au sync (fenêtre glissante)
    // ni la lecture d'octets. Comportement 1 MHz inchangé (validé sur carte).
    parameter LEADER_SYNCS  = 64,
    parameter INTER_SYNCS   = 255,   // amorce ré-insérée entre les blocs (~1,8 s)
    parameter SYNC_BYTE      = 8'h16,
    parameter START_BYTE     = 8'h01,
    parameter CREDIT_BYTE    = 8'h5A
)(
    input             clk,
    input             rst,
    // Flux UART entrant (déjà aiguillé vers la cassette par le routeur)
    input      [7:0]  rx_data,
    input             rx_valid,
    // Voie retour crédits (uart_tx)
    output reg [7:0]  tx_data,
    output reg        tx_send,
    input             tx_busy,
    // Signaux cassette
    input             turbo,        // demi-périodes réduites (chargement accéléré)
    input             motor,        // VIA PB6 (moteur)
    output reg        tape_line,    // -> tape_in (VIA CB1)
    // Aiguillage : haut pendant tout le chargement (supprime le clavier série)
    output            tape_active
);

    localparam integer FIFO_SIZE = 16;

    // ------------------------------------------------------------------
    // FSM de protocole
    // ------------------------------------------------------------------
    localparam S_IDLE = 3'd0, S_LEN0 = 3'd1, S_LEN1 = 3'd2,
               S_LOAD = 3'd3, S_DONE = 3'd4;
    reg [2:0]  state = S_IDLE;
    reg [15:0] len;
    reg [16:0] received, consumed, granted;

    assign tape_active = (state != S_IDLE);

    // ------------------------------------------------------------------
    // FIFO d'octets .tap (RAM distribuée)
    // ------------------------------------------------------------------
    (* ram_style = "distributed" *) reg [7:0] fifo [0:FIFO_SIZE-1];
    reg [3:0]  wptr = 0, rptr = 0;
    reg [4:0]  fcount = 0;
    wire fifo_empty = (fcount == 0);
    wire fifo_full  = (fcount == FIFO_SIZE);

    wire push = (state == S_LOAD) && rx_valid && !fifo_full;
    // `pop` est piloté par le générateur de forme d'onde (wf_pop ci-dessous).
    reg  wf_pop;

    // ------------------------------------------------------------------
    // Encodage d'un octet en trame 14 bits (parité impaire)
    // ------------------------------------------------------------------
    function [13:0] encode;
        input [7:0] b;
        begin
            //        stop(4)  parité      data(8)  start
            encode = {4'b1111, ~(^b),      b,       1'b0};
        end
    endfunction

    // ------------------------------------------------------------------
    // Générateur de forme d'onde
    // ------------------------------------------------------------------
    localparam W_LOAD = 2'd0, W_H0 = 2'd1, W_H1 = 2'd2;
    reg [1:0]  wf = W_LOAD;
    reg [17:0] frame;        // 14 bits + jusqu'à 4 stops turbo supplémentaires
    reg [4:0]  bitpos;
    reg [4:0]  lastbit;      // 13 (trame normale) ou 17 (turbo, données)
    reg [15:0] wf_cnt;
    reg [7:0]  leader_left;
    reg        cur_bit;

    // Demi-périodes effectives (turbo constant pendant tout un chargement :
    // piloté par tape_active au top, il ne change qu'entre deux fichiers)
    wire [15:0] half_one  = turbo ? CYC_HALF_ONE_T[15:0]  : CYC_HALF_ONE[15:0];
    wire [15:0] half_long = turbo ? CYC_HALF_LONG_T[15:0] : CYC_HALF_LONG[15:0];

    // ------------------------------------------------------------------
    // Parseur de blocs .tap (pour l'amorce inter-parties)
    // ------------------------------------------------------------------
    localparam P_SYNC = 2'd0, P_HDR = 2'd1, P_NAME = 2'd2, P_DATA = 2'd3;
    reg [1:0]  pstate;
    reg [3:0]  hcnt;                 // index dans l'en-tête (0..8)
    reg [15:0] end_a, start_a;
    reg [16:0] dcnt;                 // octets de données restants (max 65536)

    // ------------------------------------------------------------------
    // Séquenceur principal
    // ------------------------------------------------------------------
    integer k;
    always @(posedge clk) begin
        tx_send <= 1'b0;
        wf_pop  <= 1'b0;

        if (rst) begin
            state <= S_IDLE; wptr <= 0; rptr <= 0; fcount <= 0;
            received <= 0; consumed <= 0; granted <= 0;
            tape_line <= 1'b1; wf <= W_LOAD; leader_left <= 0;
        end else begin
            // ---- FSM de protocole + réception ----
            case (state)
                S_IDLE: if (rx_valid && rx_data == START_BYTE) begin
                    state <= S_LEN0;
                end
                S_LEN0: if (rx_valid) begin
                    len[7:0] <= rx_data; state <= S_LEN1;
                end
                S_LEN1: if (rx_valid) begin
                    len[15:8] <= rx_data;
                    received <= 0; consumed <= 0; granted <= 0;
                    leader_left <= LEADER_SYNCS[7:0];
                    pstate <= P_SYNC; hcnt <= 0;
                    wf <= W_LOAD; tape_line <= 1'b1;
                    state <= S_LOAD;
                end
                S_LOAD: begin
                    // Fin : tout consommé et plus rien d'utile à jouer. Le cas
                    // `bitpos >= 10` couvre les jeux autorun qui COUPENT LE
                    // MOTEUR dès leur dernier octet lu (parité comprise, bits
                    // 0-9) : il ne reste que des stop bits '1' (niveau haut,
                    // = repos) — sans cette clause, moteur coupé = forme
                    // d'onde gelée = tape_active (et le turbo) bloqués.
                    // Moteur en marche : on joue la trame jusqu'au bout
                    // (forme d'onde fidèle) ; moteur coupé sur les stops :
                    // on conclut malgré le gel.
                    if (consumed == {1'b0, len} && leader_left == 0 &&
                        fifo_empty &&
                        (wf == W_LOAD || (!motor && bitpos >= 5'd10)))
                        state <= S_DONE;    // toutes les données jouées
                end
                S_DONE: begin
                    tape_line <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase

            // ---- Écriture FIFO ----
            if (push) begin
                fifo[wptr] <= rx_data;
                wptr     <= wptr + 4'd1;
                received <= received + 17'd1;
            end

            // ---- Lecture FIFO (par la forme d'onde) ----
            if (wf_pop) begin
                rptr     <= rptr + 4'd1;
                consumed <= consumed + 17'd1;
            end

            // ---- Compteur FIFO (gère push/pop simultanés) ----
            case ({push, wf_pop})
                2'b10: fcount <= fcount + 5'd1;
                2'b01: fcount <= fcount - 5'd1;
                default: ; // 00 ou 11 : inchangé
            endcase

            // ---- Générateur de crédits ----
            // On autorise le PC à envoyer un octet de plus si : encore des
            // octets à demander (granted<len) ET la place « en vol + FIFO »
            // (granted-consumed) reste < FIFO_SIZE, ET l'émetteur est libre.
            if (state == S_LOAD && !tx_busy && !tx_send &&
                granted < {1'b0, len} &&
                (granted - consumed) < FIFO_SIZE) begin
                tx_data <= CREDIT_BYTE;
                tx_send <= 1'b1;
                granted <= granted + 17'd1;
            end

            // ---- Forme d'onde (n'avance que moteur actif) ----
            if (state == S_LOAD && motor) begin
                case (wf)
                    W_LOAD: begin
                        if (leader_left != 0) begin
                            frame       <= {4'b1111, encode(SYNC_BYTE)};
                            lastbit     <= 5'd13;  // amorce : trame 14 bits pure
                                                   // (chasse au sync bit à bit)
                            leader_left <= leader_left - 8'd1;
                            bitpos      <= 0;
                            cur_bit     <= 1'b0;   // bit0 = start
                            tape_line   <= 1'b0;   // demi 0 : BAS
                            wf_cnt      <= half_one - 16'd1;
                            wf          <= W_H0;
                        end else if (consumed < {1'b0, len}) begin
                            if (!fifo_empty) begin
                                frame     <= {4'b1111, encode(fifo[rptr])};
                                lastbit   <= turbo ? 5'd17 : 5'd13; // stops
                                                    // supplémentaires en turbo
                                wf_pop    <= 1'b1;
                                bitpos    <= 0;
                                cur_bit   <= 1'b0;
                                tape_line <= 1'b0;
                                wf_cnt    <= half_one - 16'd1;
                                wf        <= W_H0;
                                // ---- parseur de blocs : suit la structure du
                                // .tap sur l'octet consommé ----
                                case (pstate)
                                    P_SYNC: if (fifo[rptr] == 8'h24) begin
                                        hcnt <= 4'd0; pstate <= P_HDR;
                                    end                     // 0x16/autre : attendre
                                    P_HDR: begin
                                        if (hcnt == 4'd4) end_a[15:8]   <= fifo[rptr];
                                        if (hcnt == 4'd5) end_a[7:0]    <= fifo[rptr];
                                        if (hcnt == 4'd6) start_a[15:8] <= fifo[rptr];
                                        if (hcnt == 4'd7) start_a[7:0]  <= fifo[rptr];
                                        if (hcnt == 4'd8) pstate <= P_NAME;
                                        else hcnt <= hcnt + 4'd1;
                                    end
                                    P_NAME: if (fifo[rptr] == 8'h00) begin
                                        dcnt <= {1'b0, end_a} - {1'b0, start_a} + 17'd1;
                                        pstate <= P_DATA;
                                    end
                                    P_DATA: begin
                                        if (dcnt <= 17'd1) begin
                                            // dernier octet du bloc : ré-armer
                                            // l'amorce avant le bloc suivant
                                            // (sauf fin de fichier : rien après)
                                            if ((consumed + 17'd1) < {1'b0, len})
                                                leader_left <= INTER_SYNCS[7:0];
                                            pstate <= P_SYNC;
                                        end else
                                            dcnt <= dcnt - 17'd1;
                                    end
                                endcase
                            end
                            // sinon : sous-alimentation (attend des données)
                        end
                        // consumed==len : reste en W_LOAD, S_LOAD -> S_DONE
                    end
                    W_H0: begin                    // demi 0 : niveau BAS
                        if (wf_cnt == 0) begin
                            tape_line <= 1'b1;     // demi 1 : HAUT
                            wf_cnt    <= (cur_bit ? half_one : half_long) - 16'd1;
                            wf        <= W_H1;
                        end else
                            wf_cnt <= wf_cnt - 16'd1;
                    end
                    W_H1: begin                    // demi 1 : niveau HAUT
                        if (wf_cnt == 0) begin
                            if (bitpos == lastbit) begin
                                wf <= W_LOAD;      // trame finie
                            end else begin
                                bitpos    <= bitpos + 5'd1;
                                cur_bit   <= frame[bitpos + 5'd1];
                                tape_line <= 1'b0; // demi 0 du bit suivant
                                wf_cnt    <= half_one - 16'd1;
                                wf        <= W_H0;
                            end
                        end else
                            wf_cnt <= wf_cnt - 16'd1;
                    end
                    default: wf <= W_LOAD;
                endcase
            end
        end
    end

endmodule
