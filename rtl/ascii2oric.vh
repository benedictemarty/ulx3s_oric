// ascii2oric.vh — table ASCII -> matrice clavier Oric, partagee.
// Fonction map_char(ascii) -> {valide, shift, col[2:0], rangee[2:0]}.
//   bit7 = touche valide (mappee)
//   bit6 = necessite Shift Oric (matrice[4][4])
//   bits[5:3] = colonne matrice (VIA ORB[2:0])
//   bits[2:0] = rangee (port A AY, active bas)
// Positions derivees de char_map de l'emulateur de reference
// (~/Oric1/src/io/keyboard.c, tables ROM $FF70/$FFB0).
//
// A inclure DANS un module (contient uniquement une `function`).
// Utilise par key_injector.v (clavier serie UART) et oric_keyboard.v
// (disposition AZERTY : (scancode,shift) -> ASCII FR -> map_char).

    function [7:0] map_char;
        input [7:0] c;
        begin
            casez (c)
                8'h0D, 8'h0A: map_char = {2'b10, 3'd7, 3'd5}; // CR/LF -> RETURN
                8'h1B: map_char = {2'b10, 3'd1, 3'd5};        // ESC
                8'h08, 8'h7F: map_char = {2'b10, 3'd5, 3'd5}; // BS/DEL -> DEL
                8'h20: map_char = {2'b10, 3'd4, 3'd0};        // espace
                8'h21: map_char = {2'b11, 3'd0, 3'd5};        // ! = Shift+1
                8'h22: map_char = {2'b11, 3'd3, 3'd7};        // " = Shift+'
                8'h23: map_char = {2'b11, 3'd0, 3'd7};        // # = Shift+3
                8'h24: map_char = {2'b11, 3'd2, 3'd3};        // $ = Shift+4
                8'h25: map_char = {2'b11, 3'd0, 3'd2};        // % = Shift+5
                8'h26: map_char = {2'b11, 3'd0, 3'd0};        // & = Shift+7
                8'h27: map_char = {2'b10, 3'd3, 3'd7};        // '
                8'h28: map_char = {2'b11, 3'd3, 3'd1};        // ( = Shift+9
                8'h29: map_char = {2'b11, 3'd7, 3'd2};        // ) = Shift+0
                8'h2A: map_char = {2'b11, 3'd7, 3'd0};        // * = Shift+8
                8'h2B: map_char = {2'b11, 3'd7, 3'd7};        // + = Shift+=
                8'h2C: map_char = {2'b10, 3'd4, 3'd1};        // ,
                8'h2D: map_char = {2'b10, 3'd3, 3'd3};        // -
                8'h2E: map_char = {2'b10, 3'd4, 3'd2};        // .
                8'h2F: map_char = {2'b10, 3'd7, 3'd3};        // /
                8'h30: map_char = {2'b10, 3'd7, 3'd2};        // 0
                8'h31: map_char = {2'b10, 3'd0, 3'd5};        // 1
                8'h32: map_char = {2'b10, 3'd2, 3'd6};        // 2
                8'h33: map_char = {2'b10, 3'd0, 3'd7};        // 3
                8'h34: map_char = {2'b10, 3'd2, 3'd3};        // 4
                8'h35: map_char = {2'b10, 3'd0, 3'd2};        // 5
                8'h36: map_char = {2'b10, 3'd2, 3'd1};        // 6
                8'h37: map_char = {2'b10, 3'd0, 3'd0};        // 7
                8'h38: map_char = {2'b10, 3'd7, 3'd0};        // 8
                8'h39: map_char = {2'b10, 3'd3, 3'd1};        // 9
                8'h3A: map_char = {2'b11, 3'd3, 3'd2};        // : = Shift+;
                8'h3B: map_char = {2'b10, 3'd3, 3'd2};        // ;
                8'h3C: map_char = {2'b11, 3'd4, 3'd1};        // < = Shift+,
                8'h3D: map_char = {2'b10, 3'd7, 3'd7};        // =
                8'h3E: map_char = {2'b11, 3'd4, 3'd2};        // > = Shift+.
                8'h3F: map_char = {2'b11, 3'd7, 3'd3};        // ? = Shift+/
                8'h40: map_char = {2'b11, 3'd2, 3'd6};        // @ = Shift+2
                8'h41, 8'h61: map_char = {2'b10, 3'd6, 3'd5}; // A
                8'h42, 8'h62: map_char = {2'b10, 3'd2, 3'd2}; // B
                8'h43, 8'h63: map_char = {2'b10, 3'd2, 3'd7}; // C
                8'h44, 8'h64: map_char = {2'b10, 3'd1, 3'd7}; // D
                8'h45, 8'h65: map_char = {2'b10, 3'd6, 3'd3}; // E
                8'h46, 8'h66: map_char = {2'b10, 3'd1, 3'd3}; // F
                8'h47, 8'h67: map_char = {2'b10, 3'd6, 3'd2}; // G
                8'h48, 8'h68: map_char = {2'b10, 3'd6, 3'd1}; // H
                8'h49, 8'h69: map_char = {2'b10, 3'd5, 3'd1}; // I
                8'h4A, 8'h6A: map_char = {2'b10, 3'd1, 3'd0}; // J
                8'h4B, 8'h6B: map_char = {2'b10, 3'd3, 3'd0}; // K
                8'h4C, 8'h6C: map_char = {2'b10, 3'd7, 3'd1}; // L
                8'h4D, 8'h6D: map_char = {2'b10, 3'd2, 3'd0}; // M
                8'h4E, 8'h6E: map_char = {2'b10, 3'd0, 3'd1}; // N
                8'h4F, 8'h6F: map_char = {2'b10, 3'd5, 3'd2}; // O
                8'h50, 8'h70: map_char = {2'b10, 3'd5, 3'd3}; // P
                8'h51, 8'h71: map_char = {2'b10, 3'd1, 3'd6}; // Q
                8'h52, 8'h72: map_char = {2'b10, 3'd1, 3'd2}; // R
                8'h53, 8'h73: map_char = {2'b10, 3'd6, 3'd6}; // S
                8'h54, 8'h74: map_char = {2'b10, 3'd1, 3'd1}; // T
                8'h55, 8'h75: map_char = {2'b10, 3'd5, 3'd0}; // U
                8'h56, 8'h76: map_char = {2'b10, 3'd0, 3'd3}; // V
                8'h57, 8'h77: map_char = {2'b10, 3'd6, 3'd7}; // W
                8'h58, 8'h78: map_char = {2'b10, 3'd0, 3'd6}; // X
                8'h59, 8'h79: map_char = {2'b10, 3'd6, 3'd0}; // Y
                8'h5A, 8'h7A: map_char = {2'b10, 3'd2, 3'd5}; // Z
                8'h5B: map_char = {2'b10, 3'd5, 3'd7};        // [
                8'h5C: map_char = {2'b10, 3'd3, 3'd6};        // backslash
                8'h5D: map_char = {2'b10, 3'd5, 3'd6};        // ]
                8'h5E: map_char = {2'b11, 3'd2, 3'd1};        // ^ = Shift+6
                8'h5F: map_char = {2'b11, 3'd3, 3'd3};        // _ = Shift+-
                8'h7B: map_char = {2'b11, 3'd5, 3'd7};        // { = Shift+[
                8'h7C: map_char = {2'b11, 3'd3, 3'd6};        // | = Shift+backslash
                8'h7D: map_char = {2'b11, 3'd5, 3'd6};        // } = Shift+]
                default: map_char = 8'h00;                    // non mappe
            endcase
        end
    endfunction
