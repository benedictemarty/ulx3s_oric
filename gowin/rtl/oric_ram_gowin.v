// Variante Gowin de la RAM Oric : le GW2AR-18 n'a que 46 blocs BSRAM et
// yosys duplique une 1W2R (64 blocs). Ici :
//  - mémoire principale 64 Ko en SIMPLE PORT (32 blocs SP) pour le CPU ;
//  - miroir de la fenêtre vidéo $9800-$BFFF (10 Ko, écrit en parallèle)
//    en double port simple (5 blocs) pour la ULA.
// La ULA ne lit jamais hors de $9800-$BFFF (bitmap, charsets, écrans).
// Interface identique à rtl/oric_ram.v (le Makefile substitue le fichier).

module oric_ram (
    input             clk,
    // Port CPU
    input      [15:0] addr_a,
    input             we_a,
    input      [7:0]  din_a,
    output reg [7:0]  dout_a,
    // Port ULA
    input      [15:0] addr_b,
    output reg [7:0]  dout_b
);

    reg [7:0] mem [0:65535];
    reg [7:0] vshadow [0:10239];   // $9800..$BFFF

    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 8'h00;
        for (i = 0; i < 10240; i = i + 1)
            vshadow[i] = 8'h00;
    end

    // CPU : simple port, lecture/écriture exclusives
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        else
            dout_a <= mem[addr_a];
    end

    // Miroir vidéo : écrit quand le CPU écrit dans la fenêtre
    wire in_win_w = (addr_a >= 16'h9800) && (addr_a < 16'hC000);
    wire [13:0] wshadow_a = addr_a[13:0] - 14'h1800;   // - $9800 (mod 16K)
    always @(posedge clk)
        if (we_a && in_win_w)
            vshadow[wshadow_a] <= din_a;

    // ULA : lecture seule dans le miroir
    wire [13:0] rshadow_a = addr_b[13:0] - 14'h1800;
    always @(posedge clk)
        dout_b <= vshadow[rshadow_a];

endmodule
