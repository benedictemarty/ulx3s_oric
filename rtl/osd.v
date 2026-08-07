// Incrustation à l'écran (OSD) : affiche la liste des fichiers de la carte SD
// par-dessus la vidéo, avec un curseur sur le fichier sélectionné. Police 8x8
// (roms/font8x8.hex). Le texte de chaque ligne vient de fat32 (nom 8.3 lu via
// name_idx/name). Combinatoire sur (hc, vc) : à incruster avant l'encodeur TMDS.

module osd #(
    parameter OSD_X = 24,     // origine X (pixels)
    parameter OSD_Y = 32,     // origine Y
    parameter COLS  = 11,     // caractères par ligne (nom 8.3)
    parameter ROWS  = 13,     // lignes max
    parameter ZL    = 1       // zoom = 2^ZL (1 => caractères 16x16)
) (
    input        [9:0] hc,
    input        [9:0] vc,
    input              enable,
    input        [7:0] file_count,
    input        [5:0] sel_idx,

    // Lecture du nom du fichier de la ligne courante (vers fat32)
    output       [5:0] name_idx,
    input       [87:0] name,      // 11 octets, name[87:80] = 1er caractère

    output             osd_on,    // ce pixel appartient à l'OSD
    output reg   [7:0] osd_r,
    output reg   [7:0] osd_g,
    output reg   [7:0] osd_b
);
    // Police 8x8
    reg [7:0] font [0:1023];
    initial $readmemh("font8x8.hex", font);

    localparam CW    = 8 << ZL;      // taille caractère (16)
    localparam LINEH = CW << 1;      // hauteur de ligne = texte + interligne (32)
    wire in_x = (hc >= OSD_X) && (hc < OSD_X + COLS*CW);
    wire in_y = (vc >= OSD_Y) && (vc < OSD_Y + ROWS*LINEH);

    wire [9:0] rx = hc - OSD_X;
    wire [9:0] ry = vc - OSD_Y;
    wire [4:0] line  = ry >> (4 + ZL);       // ry / LINEH  (LINEH=32)
    wire [5:0] ry_in = ry & (LINEH - 1);     // 0..LINEH-1
    wire       glyph_v = (ry_in < CW);       // partie texte (sinon interligne)
    wire [3:0] col  = rx >> (3 + ZL);        // colonne (0..COLS-1)
    wire [2:0] crow = ry_in[ZL +: 3];        // ligne du glyphe (0..7)
    wire [2:0] ccol = (rx >> ZL) & 3'd7;     // colonne du glyphe

    assign name_idx = {1'b0, line};

    wire visible = enable && in_x && in_y && ({3'b0, line} < file_count);

    // Caractère de la colonne : octet `col` du nom (MSB = 1er caractère)
    wire [3:0] inv = 4'd10 - col;
    wire [7:0] ch  = (col <= 4'd10) ? name[inv*8 +: 8] : 8'h20;

    wire [7:0] glyph = font[{ch[6:0], crow}];
    wire       pix   = glyph_v ? glyph[7 - ccol] : 1'b0;   // interligne = fond
    wire       selrow = ({2'b0, line} == sel_idx);

    assign osd_on = visible;

    always @* begin
        // ligne sélectionnée : fond clair, texte foncé ; sinon texte clair sur bleu
        if (selrow) begin
            if (pix) begin osd_r=8'h00; osd_g=8'h00; osd_b=8'h00; end
            else     begin osd_r=8'hFF; osd_g=8'hFF; osd_b=8'hFF; end
        end else begin
            if (pix) begin osd_r=8'hFF; osd_g=8'hFF; osd_b=8'hFF; end
            else     begin osd_r=8'h00; osd_g=8'h00; osd_b=8'h30; end
        end
    end

endmodule
