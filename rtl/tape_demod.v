// Démodulateur cassette (CSAVE) : capture la forme d'onde tape-OUT que la ROM
// bit-bange sur PB7 (Timer 1) pendant un CSAVE, et la reconstruit en octets
// .tap. C'est le MIROIR EXACT de `tape_injector.v` (modulation) et le portage
// RTL du décodeur de référence ~/Oric1/src/io/cassette.c (tape_capture_*).
//
// Principe (identique au décodeur du testbench tb_tape) :
//   - La ROM émet DEUX demi-pulses par bit : BAS pendant HALF_ONE, puis HAUT
//     pendant HALF_ONE (bit '1') ou HALF_LONG (bit '0'). Elle chronomètre de
//     FRONT MONTANT à FRONT MONTANT — donc on ne compte QUE les fronts montants
//     de PB7, et la période front-à-front est la période bit complète
//     (2*HALF_ONE pour '1', HALF_ONE+HALF_LONG pour '0'). Compter tous les
//     fronts mesurerait des demi-pulses (tous < seuil -> tout lu comme '1').
//   - bit = (période < THRESH) ? 1 : 0. Seuil = 512 µs au 1 MHz Oric, soit
//     512*CYC_PER_US cycles clk (défaut 25 MHz -> 12800).
//   - Réassembleur d'octet SANS trame de longueur fixe (comme GetTapeByte
//     $E6C9) : on CHASSE le start (on saute les '1' de stop, le premier '0' long
//     est le start), on lit 8 bits data LSB d'abord (style ROR), puis on BRÛLE
//     une période (le bit de parité, valeur ignorée) et on rechasse le start.
//     Compter un nombre fixe de stops décalerait le framing d'un bit par trame
//     dès que le nombre réel de stops diffère du modèle.
//
// Sorties : byte_out/byte_valid (pulse 1 cycle par octet décodé) et `capturing`
// (haut tant qu'on reçoit des fronts ; retombe après GAP_CYCLES sans front ->
// fin de la sauvegarde, le consommateur peut écrire le .tap).

module tape_demod #(
    // Seuil période '1'/'0', en cycles clk. Défaut 25 MHz : 512 µs = 12800.
    parameter CYC_THRESH = 12800,
    // Silence (aucun front montant) qui clôt une capture. Défaut ~40 ms à
    // 25 MHz : bien plus long que la plus longue période bit (624 µs) et que
    // les gaps inter-blocs, mais assez court pour conclure vite après CSAVE.
    parameter GAP_CYCLES = 32'd1_000_000
)(
    input             clk,
    input             rst,
    input             tape_out,      // PB7 (niveau brut, échantillonné à `clk`)
    output reg [7:0]  byte_out,
    output reg        byte_valid,    // pulse 1 cycle : octet décodé disponible
    output reg        capturing      // haut pendant une capture en cours
);

    // ------------------------------------------------------------------
    // Détection de front montant + mesure de période (en cycles clk)
    // ------------------------------------------------------------------
    reg        pb7_d = 1'b1;         // dernier niveau (repos HAUT comme la bande)
    reg        primed = 1'b0;        // amorcé sur le 1er échantillon (pas de faux front)
    reg [31:0] since_edge = 0;       // cycles depuis le dernier front montant
    reg        have_prev = 1'b0;     // un front de référence a déjà été vu

    wire rising = (~pb7_d & tape_out);

    // ------------------------------------------------------------------
    // Réassembleur d'octet (chasse start / 8 data LSB / brûle parité)
    // ------------------------------------------------------------------
    localparam S_HUNT = 2'd0, S_DATA = 2'd1, S_PARITY = 2'd2;
    reg [1:0]  state = S_HUNT;
    reg [3:0]  bitcount = 0;
    reg [7:0]  cur = 0;

    // Injecte un bit décodé dans le réassembleur.
    task feed_bit(input bit_v);
        begin
            case (state)
                S_HUNT: if (bit_v == 1'b0) begin   // premier '0' long = start
                    state <= S_DATA; bitcount <= 0; cur <= 0;
                end
                S_DATA: begin                      // 8 bits data, LSB d'abord
                    cur <= {bit_v, cur[7:1]};
                    if (bitcount == 4'd7) begin
                        byte_out   <= {bit_v, cur[7:1]};
                        byte_valid <= 1'b1;        // octet complet
                        state      <= S_PARITY;
                    end else
                        bitcount <= bitcount + 4'd1;
                end
                S_PARITY: state <= S_HUNT;         // brûle 1 période (parité)
                default:  state <= S_HUNT;
            endcase
        end
    endtask

    always @(posedge clk) begin
        byte_valid <= 1'b0;

        if (rst) begin
            pb7_d <= 1'b1; primed <= 1'b0; since_edge <= 0; have_prev <= 1'b0;
            state <= S_HUNT; bitcount <= 0; cur <= 0;
            capturing <= 1'b0; byte_valid <= 1'b0;
        end else begin
            pb7_d <= tape_out;
            since_edge <= since_edge + 32'd1;

            // Amorçage : le 1er échantillon fixe le niveau de repos, aucun front
            // fabriqué quel que soit l'état initial de PB7.
            if (!primed) begin
                primed <= 1'b1;
                pb7_d  <= tape_out;
            end else if (rising) begin
                capturing  <= 1'b1;
                since_edge <= 0;
                if (have_prev) begin
                    // période = cycles écoulés depuis le front montant précédent
                    feed_bit(since_edge < CYC_THRESH ? 1'b1 : 1'b0);
                end
                have_prev <= 1'b1;
            end else if (capturing && since_edge >= GAP_CYCLES) begin
                // Silence prolongé : fin de la sauvegarde. On repart propre pour
                // une éventuelle capture suivante (le consommateur a l'octet
                // complet ; une trame partielle en fin est sans parité -> jamais
                // émise, conforme à la ROM qui ne clôt un octet qu'à 8 bits).
                capturing <= 1'b0;
                have_prev <= 1'b0;
                state     <= S_HUNT;
            end
        end
    end

endmodule
