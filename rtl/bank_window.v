// Fenêtre mémoire multibank $C000-$FFFF — « voie Telestrat fidèle ».
// Voir docs/MULTIBANK.md. Généralise oric_rom.v (2 banques figées) vers
// 8 banques LOGIQUES hétérogènes. Chaque banque a un RÔLE (2 bits) :
//   0 = non peuplée (bus ouvert -> lit $FF)
//   1 = ROM A        2 = ROM B
//   3 = RAM          (l'overlay est servie À L'EXTÉRIEUR, cf. ci-dessous)
//
// Côté LECTURE uniquement. L'écriture dans $C000-$FFFF et le basculement /MAP
// restent gérés par l'overlay RAM déjà en place (oric_ram + `rom_as_ram` dans
// oric_atmos.v) : les 16 Ko hauts de la RAM 64 Ko SONT l'overlay du Telestrat.
// La sortie `bank_is_ram` est le crochet pour router, plus tard, les lectures
// des banques RAM vers cet overlay (US-MBANK.4) sans dupliquer de RAM ici.
//
// US-MBANK.1 : par défaut bank0 = ROM A (BASIC 1.1b), bank1 = ROM B (1.0),
// banques 2..7 non peuplées. Piloté par `bank_sel = {2'b0, rom_bank}`, le
// comportement est STRICTEMENT identique à l'ancien oric_rom (zéro régression).
// La numérotation Telestrat (bank0 = RAM overlay, bank7 = TELEMON de boot) et
// le 2e VIA $0320 qui pilotera `bank_sel` viennent en US-MBANK.2/.3.

module bank_window #(
    parameter ROM_FILE_A = "basic11b.hex",   // image ROM A (défaut BASIC 1.1b)
    parameter ROM_FILE_B = "basic10.hex",    // image ROM B (BASIC 1.0)
    // Rôle des 8 banques logiques, 2 bits chacune, de bank7 (MSB) à bank0 (LSB).
    parameter [15:0] BANK_ROLE = {2'd0,2'd0,2'd0,2'd0,2'd0,2'd0,2'd2,2'd1}
)(
    input             clk,
    input      [2:0]  bank_sel,   // banque logique visible à $C000-$FFFF
    input      [13:0] addr,       // A0..A13 dans la fenêtre 16 Ko
    output reg [7:0]  dout,       // lecture (valide si banque de type ROM)
    output            bank_is_ram // banque sélectionnée = RAM -> overlay externe
);

    reg [7:0] mem_a [0:16383];
    reg [7:0] mem_b [0:16383];

    initial begin
        $readmemh(ROM_FILE_A, mem_a);
        $readmemh(ROM_FILE_B, mem_b);
    end

    reg [7:0] dout_a, dout_b;
    always @(posedge clk) begin
        dout_a <= mem_a[addr];
        dout_b <= mem_b[addr];
    end

    // Rôle de la banque actuellement sélectionnée.
    wire [1:0] role = BANK_ROLE[bank_sel*2 +: 2];

    always @(*) begin
        case (role)
            2'd1:    dout = dout_a;    // ROM A
            2'd2:    dout = dout_b;    // ROM B
            default: dout = 8'hFF;     // 0 = non peuplée ; 3 = RAM (overlay ext.)
        endcase
    end

    assign bank_is_ram = (role == 2'd3);

endmodule
