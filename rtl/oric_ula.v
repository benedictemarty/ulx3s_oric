// ULA Oric Atmos — réimplémentation d'après l'analyse de ~/Oric1/src/video/.
// Timing PAL authentique : 64 µs/ligne (64 cellules), 312 lignes, 50 Hz.
// Zone visible : 40 cellules x 224 lignes (TEXT 40x28 / HIRES 240x200 + 3
// rangées TEXT en bas). Sortie : écriture dans un framebuffer 240x224 x 4 bits
// (index couleur 0-7), relu par l'étage HDMI dans son propre domaine.
//
// La cellule (1 µs = DIV cycles de clk) est pipelinée sur le compteur tphase :
//   t0 : adresse écran        t2 : capture octet écran
//   t3 : décodage attribut / adresse charset
//   t5 : capture octet charset
//   t6..t11 : écriture des 6 pixels dans le framebuffer
//   t(DIV-1) : avancement des compteurs de balayage
// La RAM (port B, BRAM 1 cycle de latence) est dédiée à la ULA : aucune
// contention avec le CPU.

module oric_ula #(
    parameter DIV = 24          // cycles clk par cellule (>= 13)
)(
    input                 clk,
    input                 rst,
    input  [4:0]          tphase,       // 0..DIV-1

    // Port vidéo de la RAM 64 Ko
    output reg [15:0]     vram_addr,
    input      [7:0]      vram_din,

    // Écriture framebuffer 240x224
    output reg            fb_we,
    output reg [15:0]     fb_addr,
    output reg [3:0]      fb_data,

    output reg            frame_tick    // impulsion en fin de trame
);

    wire cell_end = (tphase == DIV - 1);

    // Compteurs de balayage
    reg [5:0] xcell;      // 0..63 cellules par ligne
    reg [8:0] yline;      // 0..311
    reg [7:0] frame_cnt;

    // État attributs série
    reg [2:0] ink, paper, tattr, vmode;

    // Pipeline cellule
    reg [7:0] scr_byte;
    reg       cell_is_attr;
    reg [2:0] fill_col;           // couleur de remplissage cellule attribut
    reg [2:0] fg, bg;
    reg       blank_char;         // clignotement : phase masquée
    reg [2:0] px_idx;
    reg       px_active;
    reg [5:0] px_bits;

    wire visible    = (xcell < 6'd40) && (yline < 9'd224);
    wire hires_zone = vmode[2] && (yline < 9'd200);

    // Rangée texte + ligne de glyphe
    wire [8:0] ybot   = yline - 9'd200;
    wire [4:0] trow   = (yline < 9'd200) ? yline[7:3] : (5'd25 + {2'd0, ybot[5:3]});
    wire [2:0] chline = (yline < 9'd200) ? yline[2:0] : ybot[2:0];

    // Adresses écran
    wire [15:0] text_addr  = 16'hBB80 + {11'd0, trow} * 16'd40 + {10'd0, xcell};
    wire [15:0] hires_addr = 16'hA000 + {7'd0, yline} * 16'd40 + {10'd0, xcell};
    wire [15:0] scr_addr   = hires_zone ? hires_addr : text_addr;

    // Adresse charset
    wire        alt_charset = tattr[0];
    wire [2:0]  erow = tattr[1] ? ({1'b0, chline[2:1]} + (trow[0] ? 3'd4 : 3'd0))
                                : chline;
    wire [15:0] chr_base = hires_zone ? (alt_charset ? 16'h9C00 : 16'h9800)
                                      : (alt_charset ? 16'hB800 : 16'hB400);
    wire [15:0] chr_addr = chr_base + {6'd0, scr_byte[6:0], 3'd0} + {13'd0, erow};

    wire is_attr = (scr_byte & 8'h60) == 8'h00;
    wire inv     = scr_byte[7];

    // Adresse framebuffer du pixel courant
    wire [15:0] fb_pix_addr = {7'd0, yline} * 16'd240
                              + {10'd0, xcell} * 16'd6 + {13'd0, px_idx};

    always @(posedge clk) begin
        frame_tick <= 1'b0;
        fb_we <= 1'b0;

        if (rst) begin
            xcell <= 0; yline <= 0; frame_cnt <= 0;
            ink <= 3'd7; paper <= 3'd0; tattr <= 3'd0; vmode <= 3'd0;
            px_active <= 1'b0;
        end else begin
            // Avancement du balayage en toute fin de cellule
            if (cell_end) begin
                if (xcell == 6'd63) begin
                    xcell <= 0;
                    // Reset des attributs en début de ligne (pas vmode)
                    ink <= 3'd7; paper <= 3'd0; tattr <= 3'd0;
                    if (yline == 9'd311) begin
                        yline <= 0;
                        frame_cnt <= frame_cnt + 8'd1;
                        frame_tick <= 1'b1;
                    end else
                        yline <= yline + 9'd1;
                end else
                    xcell <= xcell + 6'd1;
            end

            // Pipeline de la cellule visible
            if (visible) begin
                case (tphase)
                    5'd0: vram_addr <= scr_addr;
                    5'd2: scr_byte  <= vram_din;
                    5'd3: begin
                        cell_is_attr <= is_attr;
                        if (is_attr) begin
                            // Application immédiate de l'attribut ; la cellule
                            // elle-même s'affiche couleur papier (à jour)
                            case (scr_byte[4:3])
                                2'b00: begin
                                    ink <= scr_byte[2:0];
                                    fill_col <= inv ? (paper ^ 3'd7) : paper;
                                end
                                2'b01: begin
                                    tattr <= scr_byte[2:0];
                                    fill_col <= inv ? (paper ^ 3'd7) : paper;
                                end
                                2'b10: begin
                                    paper <= scr_byte[2:0];
                                    fill_col <= inv ? (scr_byte[2:0] ^ 3'd7)
                                                    : scr_byte[2:0];
                                end
                                2'b11: begin
                                    vmode <= scr_byte[2:0];
                                    fill_col <= inv ? (paper ^ 3'd7) : paper;
                                end
                            endcase
                        end else begin
                            vram_addr  <= chr_addr;
                            fg <= inv ? (ink ^ 3'd7) : ink;
                            bg <= inv ? (paper ^ 3'd7) : paper;
                            blank_char <= tattr[2] & frame_cnt[4];
                        end
                    end
                    5'd5: begin
                        px_idx    <= 3'd0;
                        px_active <= 1'b1;
                        px_bits   <= hires_zone ? scr_byte[5:0] : vram_din[5:0];
                    end
                    default: ;
                endcase

                // Écriture des 6 pixels (t6..t11)
                if (px_active && tphase >= 5'd6 && tphase <= 5'd11) begin
                    fb_we   <= 1'b1;
                    fb_addr <= fb_pix_addr;
                    if (cell_is_attr)
                        fb_data <= {1'b0, fill_col};
                    else if (blank_char && !hires_zone)
                        fb_data <= {1'b0, bg};
                    else
                        fb_data <= px_bits[3'd5 - px_idx] ? {1'b0, fg} : {1'b0, bg};
                    px_idx <= px_idx + 3'd1;
                    if (tphase == 5'd11) px_active <= 1'b0;
                end
            end
        end
    end

endmodule
