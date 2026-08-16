// Traduction clavier USB HID -> matrice 8x8 Oric.
// Câblage d'époque (cf. ~/Oric1/src/io/keyboard.c) :
//   - VIA ORB[2:0] sélectionne la colonne matérielle (74LS138) ;
//   - le port A de l'AY-3-8912 pilote les rangées, actives à l'état bas ;
//   - VIA PB3 (sense, actif haut) = au moins une touche pressée dans la
//     colonne sélectionnée ET dont la rangée est activée par l'AY.
//
// Deux dispositions physiques, sélectionnées par l'entrée `azerty`
// (basculée par un bouton de la carte, cf. top_ulx3s) :
//   - azerty=0 : QWERTY positionnel. Le scancode HID (déjà positionnel)
//     est traduit directement en position matrice via hid2oric ; le Shift
//     physique est reporté tel quel sur le Shift Oric.
//   - azerty=1 : AZERTY français. (scancode, shift) -> ASCII français
//     (azerty_ascii) puis ASCII -> matrice via la table partagée map_char
//     (ascii2oric.vh, la même que le clavier série).
//
// Shift synthétisé (glyphes AZERTY du type `&` = Shift+7) : contrairement à
// un Shift physique — que l'utilisateur enfonce AVANT la touche — un Shift
// dérivé du même scancode monterait exactement en même temps que la touche.
// Le scan clavier de la ROM attrape alors parfois la touche sans le Shift
// (symptôme : `7` au lieu de `&`). Ces glyphes sont donc séquencés par une
// petite FSM qui fait PRÉCÉDER le Shift (LEAD), le MAINTIENT pendant la
// touche (HOLD, avec un minimum garanti pour être vu par au moins un
// balayage), puis le PROLONGE au relâché (TAIL) — comme un vrai doigt.
// Lettres, touches non-Shift, modificateurs, clavier série et Shift physique
// QWERTY restent purement combinatoires (déjà fiables).

module oric_keyboard #(
    // Durées du séquencement du Shift synthétisé (en cycles de clk = clk_sys).
    // Défaut à 25 MHz : ~20 ms d'avance, ~20 ms de maintien mini, ~10 ms de
    // traîne. Un balayage clavier Oric dure ~10-20 ms : l'avance garantit que
    // le Shift est vu au moins un balayage avant la touche.
    parameter LEAD_TICKS     = 500_000,
    parameter HOLD_MIN_TICKS = 500_000,
    parameter TAIL_TICKS     = 250_000
)(
    input        clk,
    // Disposition : 0 = QWERTY positionnel, 1 = AZERTY français
    input        azerty,
    // Rapport HID (déjà synchronisé dans le domaine clk)
    input  [7:0] mods,
    input  [7:0] k1,
    input  [7:0] k2,
    input  [7:0] k3,
    input  [7:0] k4,
    // Injection d'une touche (clavier série UART depuis le PC)
    input        inj_active,
    input  [2:0] inj_col,
    input  [2:0] inj_row,
    input        inj_shift,
    input        inj_ctrl,
    // Interface matrice
    input  [2:0] col_sel,     // VIA ORB[2:0]
    input  [7:0] ay_ioa,      // rangées actives bas
    output reg   sense        // VIA PB3
);

    // HID usage -> {valide, col[2:0], rangée[2:0]} — QWERTY positionnel
    function [6:0] hid2oric;
        input [7:0] c;
        begin
            case (c)
                8'h04: hid2oric = {1'b1, 3'd6, 3'd5}; // A
                8'h05: hid2oric = {1'b1, 3'd2, 3'd2}; // B
                8'h06: hid2oric = {1'b1, 3'd2, 3'd7}; // C
                8'h07: hid2oric = {1'b1, 3'd1, 3'd7}; // D
                8'h08: hid2oric = {1'b1, 3'd6, 3'd3}; // E
                8'h09: hid2oric = {1'b1, 3'd1, 3'd3}; // F
                8'h0A: hid2oric = {1'b1, 3'd6, 3'd2}; // G
                8'h0B: hid2oric = {1'b1, 3'd6, 3'd1}; // H
                8'h0C: hid2oric = {1'b1, 3'd5, 3'd1}; // I
                8'h0D: hid2oric = {1'b1, 3'd1, 3'd0}; // J
                8'h0E: hid2oric = {1'b1, 3'd3, 3'd0}; // K
                8'h0F: hid2oric = {1'b1, 3'd7, 3'd1}; // L
                8'h10: hid2oric = {1'b1, 3'd2, 3'd0}; // M
                8'h11: hid2oric = {1'b1, 3'd0, 3'd1}; // N
                8'h12: hid2oric = {1'b1, 3'd5, 3'd2}; // O
                8'h13: hid2oric = {1'b1, 3'd5, 3'd3}; // P
                8'h14: hid2oric = {1'b1, 3'd1, 3'd6}; // Q
                8'h15: hid2oric = {1'b1, 3'd1, 3'd2}; // R
                8'h16: hid2oric = {1'b1, 3'd6, 3'd6}; // S
                8'h17: hid2oric = {1'b1, 3'd1, 3'd1}; // T
                8'h18: hid2oric = {1'b1, 3'd5, 3'd0}; // U
                8'h19: hid2oric = {1'b1, 3'd0, 3'd3}; // V
                8'h1A: hid2oric = {1'b1, 3'd6, 3'd7}; // W
                8'h1B: hid2oric = {1'b1, 3'd0, 3'd6}; // X
                8'h1C: hid2oric = {1'b1, 3'd6, 3'd0}; // Y
                8'h1D: hid2oric = {1'b1, 3'd2, 3'd5}; // Z
                8'h1E: hid2oric = {1'b1, 3'd0, 3'd5}; // 1
                8'h1F: hid2oric = {1'b1, 3'd2, 3'd6}; // 2
                8'h20: hid2oric = {1'b1, 3'd0, 3'd7}; // 3
                8'h21: hid2oric = {1'b1, 3'd2, 3'd3}; // 4
                8'h22: hid2oric = {1'b1, 3'd0, 3'd2}; // 5
                8'h23: hid2oric = {1'b1, 3'd2, 3'd1}; // 6
                8'h24: hid2oric = {1'b1, 3'd0, 3'd0}; // 7
                8'h25: hid2oric = {1'b1, 3'd7, 3'd0}; // 8
                8'h26: hid2oric = {1'b1, 3'd3, 3'd1}; // 9
                8'h27: hid2oric = {1'b1, 3'd7, 3'd2}; // 0
                8'h28: hid2oric = {1'b1, 3'd7, 3'd5}; // Enter -> RETURN
                8'h29: hid2oric = {1'b1, 3'd1, 3'd5}; // Esc
                8'h2A: hid2oric = {1'b1, 3'd5, 3'd5}; // Backspace -> DEL
                8'h2C: hid2oric = {1'b1, 3'd4, 3'd0}; // Espace
                8'h2D: hid2oric = {1'b1, 3'd3, 3'd3}; // -
                8'h2E: hid2oric = {1'b1, 3'd7, 3'd7}; // =
                8'h2F: hid2oric = {1'b1, 3'd5, 3'd7}; // [
                8'h30: hid2oric = {1'b1, 3'd5, 3'd6}; // ]
                8'h31: hid2oric = {1'b1, 3'd3, 3'd6}; // backslash
                8'h33: hid2oric = {1'b1, 3'd3, 3'd2}; // ;
                8'h34: hid2oric = {1'b1, 3'd3, 3'd7}; // '
                8'h36: hid2oric = {1'b1, 3'd4, 3'd1}; // ,
                8'h37: hid2oric = {1'b1, 3'd4, 3'd2}; // .
                8'h38: hid2oric = {1'b1, 3'd7, 3'd3}; // /
                8'h4F: hid2oric = {1'b1, 3'd4, 3'd7}; // fleche droite
                8'h50: hid2oric = {1'b1, 3'd4, 3'd5}; // fleche gauche
                8'h51: hid2oric = {1'b1, 3'd4, 3'd6}; // fleche bas
                8'h52: hid2oric = {1'b1, 3'd4, 3'd3}; // fleche haut
                default: hid2oric = 7'd0;
            endcase
        end
    endfunction

    // ASCII -> matrice Oric (table partagée avec le clavier série)
    `include "ascii2oric.vh"

    // Disposition AZERTY française : scancode HID (positionnel) + Shift
    // physique -> {reconnue, ASCII}.
    //   bit8 = la touche APPARTIENT à la disposition AZERTY (même si son
    //          glyphe est hors ASCII) ; si 0, l'appelant retombe sur le
    //          positionnel hid2oric (Entrée, flèches, espace…).
    //   bits[7:0] = ASCII produit, ou 0 si le glyphe est hors ASCII
    //          (é è à ç ù ° £ § µ, accents morts) -> aucune sortie, PAS de
    //          repli QWERTY (sinon la touche accentuée donnerait le chiffre
    //          QWERTY, cf. bug « touche 2 reste à 2 »).
    //
    // Rangée du haut : CHIFFRE en accès direct (pratique pour le BASIC),
    // symbole en Shift.
    function [8:0] azerty_map;
        input [7:0] c;
        input      sh;   // Shift physique maintenu
        begin
            case (c)
                // --- rangée des lettres (positions permutées vs QWERTY) ---
                8'h14: azerty_map = {1'b1, "A"};              // (QWERTY Q) -> A
                8'h1A: azerty_map = {1'b1, "Z"};              // (QWERTY W) -> Z
                8'h1D: azerty_map = {1'b1, "W"};              // (QWERTY Z) -> W
                8'h04: azerty_map = {1'b1, "Q"};              // (QWERTY A) -> Q
                8'h33: azerty_map = {1'b1, "M"};              // (QWERTY ;) -> M
                // --- rangée du haut : chiffre direct / symbole en Shift ---
                8'h1E: azerty_map = {1'b1, sh ? "&"    : "1"};
                8'h1F: azerty_map = {1'b1, sh ? 8'h00  : "2"}; // Shift = é (indispo)
                8'h20: azerty_map = {1'b1, sh ? 8'h22  : "3"}; // Shift = "
                8'h21: azerty_map = {1'b1, sh ? "'"    : "4"};
                8'h22: azerty_map = {1'b1, sh ? "("    : "5"};
                8'h23: azerty_map = {1'b1, sh ? "-"    : "6"};
                8'h24: azerty_map = {1'b1, sh ? 8'h00  : "7"}; // Shift = è (indispo)
                8'h25: azerty_map = {1'b1, sh ? "_"    : "8"};
                8'h26: azerty_map = {1'b1, sh ? 8'h00  : "9"}; // Shift = ç (indispo)
                8'h27: azerty_map = {1'b1, sh ? 8'h00  : "0"}; // Shift = à (indispo)
                8'h2D: azerty_map = {1'b1, sh ? 8'h00  : ")"}; // ) / ° (indispo)
                8'h2E: azerty_map = {1'b1, sh ? "+"    : "="}; // = / +
                // --- symboles à droite ---
                8'h30: azerty_map = {1'b1, sh ? 8'h00  : "$"}; // $ / £ (indispo)
                8'h31: azerty_map = {1'b1, sh ? 8'h00  : "*"}; // * / µ (indispo)
                8'h32: azerty_map = {1'b1, sh ? 8'h00  : "*"}; // *µ variante ISO (= 0x31)
                8'h55: azerty_map = {1'b1, "*"};              // * du pave numerique
                8'h34: azerty_map = {1'b1, sh ? "%"    : 8'h00}; // ù (indispo) / %
                // --- rangée du bas ---
                8'h10: azerty_map = {1'b1, sh ? "?"    : ","}; // , ?   (QWERTY M)
                8'h36: azerty_map = {1'b1, sh ? "."    : ";"}; // ; .
                8'h37: azerty_map = {1'b1, sh ? "/"    : ":"}; // : /
                8'h38: azerty_map = {1'b1, sh ? 8'h00  : "!"}; // ! / § (indispo)
                8'h64: azerty_map = {1'b1, sh ? ">"    : "<"}; // < >   (touche ISO)
                default: azerty_map = {1'b0, 8'h00};          // non AZERTY -> repli
            endcase
        end
    endfunction

    // Résout un scancode en {valide, shift_oric, col[2:0], rangée[2:0]}
    // selon la disposition courante.
    function [7:0] key_map;
        input [7:0] c;
        input      sh;   // Shift physique maintenu
        reg  [8:0] am;
        reg  [6:0] h;
        begin
            am = azerty ? azerty_map(c, sh) : 9'b0;
            if (azerty && am[8]) begin
                // Touche AZERTY reconnue : son glyphe (ou rien si hors ASCII),
                // JAMAIS de repli positionnel.
                key_map = (am[7:0] != 8'h00) ? map_char(am[7:0]) : 8'h00;
            end else begin
                h = hid2oric(c);                  // {valide, col, row}
                key_map = {h[6], 1'b0, h[5:0]};   // pas de Shift Oric imposé
            end
        end
    endfunction

    wire phys_shift = mods[1] | mods[5];   // LSHIFT | RSHIFT

    // Décodage combinatoire des 4 touches HID.
    reg [7:0] e0, e1, e2, e3;              // {valide, shift, col, row}
    // Premier glyphe nécessitant un Shift synthétisé (géré par la FSM).
    reg       sg_valid;
    reg [2:0] sg_col, sg_row;

    always @* begin
        e0 = key_map(k1, phys_shift);
        e1 = key_map(k2, phys_shift);
        e2 = key_map(k3, phys_shift);
        e3 = key_map(k4, phys_shift);

        sg_valid = 1'b0; sg_col = 3'd0; sg_row = 3'd0;
        if      (e0[7] && e0[6]) begin sg_valid = 1'b1; sg_col = e0[5:3]; sg_row = e0[2:0]; end
        else if (e1[7] && e1[6]) begin sg_valid = 1'b1; sg_col = e1[5:3]; sg_row = e1[2:0]; end
        else if (e2[7] && e2[6]) begin sg_valid = 1'b1; sg_col = e2[5:3]; sg_row = e2[2:0]; end
        else if (e3[7] && e3[6]) begin sg_valid = 1'b1; sg_col = e3[5:3]; sg_row = e3[2:0]; end
    end

    // FSM du Shift synthétisé : PRÉCÈDE le Shift, MAINTIENT, puis PROLONGE.
    localparam FSM_IDLE = 2'd0, FSM_LEAD = 2'd1, FSM_HOLD = 2'd2, FSM_TAIL = 2'd3;
    reg [1:0]  fstate = FSM_IDLE;
    reg [19:0] ftimer = 20'd0;
    reg [2:0]  sg_col_l = 3'd0, sg_row_l = 3'd0;

    always @(posedge clk) begin
        case (fstate)
            FSM_IDLE:
                if (sg_valid) begin
                    sg_col_l <= sg_col; sg_row_l <= sg_row;
                    ftimer   <= LEAD_TICKS[19:0];
                    fstate   <= FSM_LEAD;         // Shift seul, la touche attend
                end
            FSM_LEAD:                             // avance : Shift présenté avant la touche
                if (ftimer == 0) begin
                    ftimer <= HOLD_MIN_TICKS[19:0];
                    fstate <= FSM_HOLD;
                end else
                    ftimer <= ftimer - 20'd1;
            FSM_HOLD: begin                        // Shift + touche
                if (ftimer != 0)
                    ftimer <= ftimer - 20'd1;      // maintien minimal garanti
                else if (!sg_valid)                // relâchée après le minimum
                    { fstate, ftimer } <= { FSM_TAIL, TAIL_TICKS[19:0] };
            end
            FSM_TAIL:                              // traîne : Shift maintenu au relâché
                if (ftimer == 0)
                    fstate <= FSM_IDLE;
                else
                    ftimer <= ftimer - 20'd1;
            default: fstate <= FSM_IDLE;
        endcase
    end

    wire fsm_shift = (fstate != FSM_IDLE);         // cellule Shift Oric pilotée
    wire fsm_char  = (fstate == FSM_HOLD);         // cellule glyphe pilotée

    reg [7:0] matrix [0:7];   // matrix[col], bit = rangée, actif haut
    integer i;

    always @* begin
        for (i = 0; i < 8; i = i + 1)
            matrix[i] = 8'h00;

        // Touches sans Shift synthétisé (lettres, chiffres directs, non-alphanum.) :
        // posées immédiatement. Les glyphes à Shift synthétisé sont exclus ici et
        // pilotés par la FSM ci-dessous.
        if (e0[7] && !e0[6]) matrix[e0[5:3]][e0[2:0]] = 1'b1;
        if (e1[7] && !e1[6]) matrix[e1[5:3]][e1[2:0]] = 1'b1;
        if (e2[7] && !e2[6]) matrix[e2[5:3]][e2[2:0]] = 1'b1;
        if (e3[7] && !e3[6]) matrix[e3[5:3]][e3[2:0]] = 1'b1;

        // Modificateurs HID : CTRL et FUNCT (ALT) reportés dans les deux modes.
        if (mods[0]) matrix[2][4] = 1'b1;   // LCTRL  -> CTRL (2,4)
        if (mods[4]) matrix[0][4] = 1'b1;   // RCTRL  -> (0,4)
        if (mods[2]) matrix[5][4] = 1'b1;   // LALT   -> FUNCT (5,4)
        if (mods[6]) matrix[5][4] = 1'b1;   // RALT   -> FUNCT (5,4)

        // Shift physique : reporté tel quel en QWERTY (l'utilisateur le tient
        // déjà avant la touche) ; consommé par le décodage en AZERTY.
        if (!azerty) begin
            if (mods[1]) matrix[4][4] = 1'b1;   // LSHIFT -> (4,4)
            if (mods[5]) matrix[7][4] = 1'b1;   // RSHIFT -> (7,4)
        end

        // Shift synthétisé séquencé (glyphes AZERTY type `&` = Shift+7).
        if (fsm_shift) matrix[4][4] = 1'b1;
        if (fsm_char)  matrix[sg_col_l][sg_row_l] = 1'b1;

        // Touche injectée par le lien série
        if (inj_active) begin
            matrix[inj_col][inj_row] = 1'b1;
            if (inj_shift) matrix[4][4] = 1'b1;   // LSHIFT Oric
            if (inj_ctrl)  matrix[2][4] = 1'b1;   // LCTRL Oric (2,4)
        end
    end

    always @(posedge clk)
        sense <= |(matrix[col_sel] & ~ay_ioa);

endmodule
