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
//     (ascii2oric.vh, la même que le clavier série). Le Shift physique est
//     CONSOMMÉ par le décodage AZERTY (il choisit le glyphe) ; le Shift Oric
//     est alors déterminé par map_char (ex. '(' = Shift+9). Les touches non
//     alphanumériques (Entrée, Échap, flèches, espace…) retombent sur la
//     table positionnelle.

module oric_keyboard (
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
    // physique -> ASCII français. Renvoie 0 si la touche n'est pas
    // réaffectée par l'AZERTY (l'appelant retombe alors sur hid2oric).
    // Les glyphes hors ASCII (é è à ç ù ° £ § µ, accents morts) renvoient 0.
    function [7:0] azerty_ascii;
        input [7:0] c;
        input      sh;   // Shift physique maintenu
        begin
            case (c)
                // --- rangée des lettres (positions permutées vs QWERTY) ---
                8'h14: azerty_ascii = "A";               // (QWERTY Q) -> A
                8'h1A: azerty_ascii = "Z";               // (QWERTY W) -> Z
                8'h1D: azerty_ascii = "W";               // (QWERTY Z) -> W
                8'h04: azerty_ascii = "Q";               // (QWERTY A) -> Q
                8'h33: azerty_ascii = "M";               // (QWERTY ;) -> M
                // --- rangée des chiffres : symbole direct / chiffre en Shift ---
                8'h1E: azerty_ascii = sh ? "1" : "&";    // & 1
                8'h1F: azerty_ascii = sh ? "2" : 8'h00;  // é 2   (é hors ASCII)
                8'h20: azerty_ascii = sh ? "3" : 8'h22;  // " 3
                8'h21: azerty_ascii = sh ? "4" : "'";    // ' 4
                8'h22: azerty_ascii = sh ? "5" : "(";    // ( 5
                8'h23: azerty_ascii = sh ? "6" : "-";    // - 6
                8'h24: azerty_ascii = sh ? "7" : 8'h00;  // è 7   (è hors ASCII)
                8'h25: azerty_ascii = sh ? "8" : "_";    // _ 8
                8'h26: azerty_ascii = sh ? "9" : 8'h00;  // ç 9   (ç hors ASCII)
                8'h27: azerty_ascii = sh ? "0" : 8'h00;  // à 0   (à hors ASCII)
                8'h2D: azerty_ascii = sh ? 8'h00 : ")";  // ) °   (° hors ASCII)
                8'h2E: azerty_ascii = sh ? "+" : "=";    // = +
                // --- symboles à droite ---
                8'h30: azerty_ascii = sh ? 8'h00 : "$";  // $ £   (£ hors ASCII)
                8'h31: azerty_ascii = sh ? 8'h00 : "*";  // * µ   (µ hors ASCII)
                8'h34: azerty_ascii = sh ? "%" : 8'h00;  // ù %   (ù hors ASCII)
                // --- rangée du bas ---
                8'h10: azerty_ascii = sh ? "?" : ",";    // , ?   (QWERTY M)
                8'h36: azerty_ascii = sh ? "." : ";";    // ; .
                8'h37: azerty_ascii = sh ? "/" : ":";    // : /
                8'h38: azerty_ascii = sh ? 8'h00 : "!";  // ! §   (§ hors ASCII)
                8'h64: azerty_ascii = sh ? ">" : "<";    // < >   (touche ISO)
                default: azerty_ascii = 8'h00;           // non réaffectée
            endcase
        end
    endfunction

    // Résout un scancode en {valide, shift_oric, col[2:0], rangée[2:0]}
    // selon la disposition courante.
    function [7:0] key_map;
        input [7:0] c;
        input      sh;   // Shift physique maintenu
        reg  [7:0] a;
        reg  [6:0] h;
        begin
            a = 8'h00;
            if (azerty) a = azerty_ascii(c, sh);
            if (azerty && a != 8'h00) begin
                key_map = map_char(a);            // {valide, shift, col, row}
            end else begin
                h = hid2oric(c);                  // {valide, col, row}
                key_map = {h[6], 1'b0, h[5:0]};   // pas de Shift Oric imposé
            end
        end
    endfunction

    reg [7:0] matrix [0:7];   // matrix[col], bit = rangée, actif haut
    integer i;
    reg [7:0] e0, e1, e2, e3;
    wire phys_shift = mods[1] | mods[5];   // LSHIFT | RSHIFT
    reg  shift_oric;

    always @* begin
        for (i = 0; i < 8; i = i + 1)
            matrix[i] = 8'h00;

        e0 = key_map(k1, phys_shift);
        e1 = key_map(k2, phys_shift);
        e2 = key_map(k3, phys_shift);
        e3 = key_map(k4, phys_shift);

        shift_oric = 1'b0;
        if (e0[7]) begin matrix[e0[5:3]][e0[2:0]] = 1'b1; shift_oric = shift_oric | e0[6]; end
        if (e1[7]) begin matrix[e1[5:3]][e1[2:0]] = 1'b1; shift_oric = shift_oric | e1[6]; end
        if (e2[7]) begin matrix[e2[5:3]][e2[2:0]] = 1'b1; shift_oric = shift_oric | e2[6]; end
        if (e3[7]) begin matrix[e3[5:3]][e3[2:0]] = 1'b1; shift_oric = shift_oric | e3[6]; end

        // Modificateurs HID : CTRL et FUNCT (ALT) reportés dans les deux modes.
        if (mods[0]) matrix[2][4] = 1'b1;   // LCTRL  -> CTRL (2,4)
        if (mods[4]) matrix[0][4] = 1'b1;   // RCTRL  -> (0,4)
        if (mods[2]) matrix[5][4] = 1'b1;   // LALT   -> FUNCT (5,4)
        if (mods[6]) matrix[5][4] = 1'b1;   // RALT   -> FUNCT (5,4)

        // Shift : en QWERTY le Shift physique est reporté tel quel ; en AZERTY
        // il est consommé par le décodage (shift_oric issu de map_char).
        if (!azerty) begin
            if (mods[1]) matrix[4][4] = 1'b1;   // LSHIFT -> (4,4)
            if (mods[5]) matrix[7][4] = 1'b1;   // RSHIFT -> (7,4)
        end
        if (shift_oric) matrix[4][4] = 1'b1;    // Shift Oric requis par le glyphe

        // Touche injectée par le lien série
        if (inj_active) begin
            matrix[inj_col][inj_row] = 1'b1;
            if (inj_shift) matrix[4][4] = 1'b1;   // LSHIFT Oric
        end
    end

    always @(posedge clk)
        sense <= |(matrix[col_sel] & ~ay_ioa);

endmodule
