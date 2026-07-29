// Traduction clavier USB HID -> matrice 8x8 Oric.
// Câblage d'époque (cf. ~/Oric1/src/io/keyboard.c) :
//   - VIA ORB[2:0] sélectionne la colonne matérielle (74LS138) ;
//   - le port A de l'AY-3-8912 pilote les rangées, actives à l'état bas ;
//   - VIA PB3 (sense, actif haut) = au moins une touche pressée dans la
//     colonne sélectionnée ET dont la rangée est activée par l'AY.
// Mapping positionnel QWERTY : les positions viennent des tables ROM
// $FF70/$FFB0 (via char_map de l'émulateur de référence).

module oric_keyboard (
    input        clk,
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

    // HID usage -> {valide, col[2:0], rangée[2:0]}
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

    reg [7:0] matrix [0:7];   // matrix[col], bit = rangée, actif haut
    integer i;
    reg [6:0] m0, m1, m2, m3;

    always @* begin
        for (i = 0; i < 8; i = i + 1)
            matrix[i] = 8'h00;

        m0 = hid2oric(k1);
        m1 = hid2oric(k2);
        m2 = hid2oric(k3);
        m3 = hid2oric(k4);
        if (m0[6]) matrix[m0[5:3]][m0[2:0]] = 1'b1;
        if (m1[6]) matrix[m1[5:3]][m1[2:0]] = 1'b1;
        if (m2[6]) matrix[m2[5:3]][m2[2:0]] = 1'b1;
        if (m3[6]) matrix[m3[5:3]][m3[2:0]] = 1'b1;

        // Modificateurs HID : LCTRL, LSHIFT, LALT(FUNCT), RCTRL, RSHIFT, RALT(FUNCT)
        if (mods[0]) matrix[2][4] = 1'b1;   // LCTRL  -> CTRL (2,4)
        if (mods[1]) matrix[4][4] = 1'b1;   // LSHIFT -> (4,4)
        if (mods[2]) matrix[5][4] = 1'b1;   // LALT   -> FUNCT (5,4)
        if (mods[4]) matrix[0][4] = 1'b1;   // RCTRL  -> (0,4)
        if (mods[5]) matrix[7][4] = 1'b1;   // RSHIFT -> (7,4)
        if (mods[6]) matrix[5][4] = 1'b1;   // RALT   -> FUNCT (5,4)

        // Touche injectée par le lien série
        if (inj_active) begin
            matrix[inj_col][inj_row] = 1'b1;
            if (inj_shift) matrix[4][4] = 1'b1;   // LSHIFT Oric
        end
    end

    always @(posedge clk)
        sense <= |(matrix[col_sel] & ~ay_ioa);

endmodule
