// ROM BASIC, 2 banques de 16 Ko en BRAM initialisées par $readmemh :
// banque 0 = BASIC 1.1b (Atmos, défaut), banque 1 = BASIC 1.0 (Oric-1).
// La banque 1.0 sert les jeux à loader protégé sensibles à la révision de la
// ROM (ex. Citadel : empreinte $FFF9/$E4B6 + sauts dans les entrailles de la
// ROM — incompatibles 1.1b). Sélection par `bank`, à ne changer qu'avec un
// reset (le vecteur $FFFC change de contenu).

module oric_rom #(
    parameter ROM_FILE   = "basic11b.hex",
    parameter ROM_FILE_B = "basic10.hex"
)(
    input             clk,
    input             bank,
    input      [13:0] addr,
    output     [7:0]  dout
);

    reg [7:0] mem_a [0:16383];
    reg [7:0] mem_b [0:16383];

    initial begin
        $readmemh(ROM_FILE,   mem_a);
        $readmemh(ROM_FILE_B, mem_b);
    end

    reg [7:0] dout_a, dout_b;
    always @(posedge clk) begin
        dout_a <= mem_a[addr];
        dout_b <= mem_b[addr];
    end

    assign dout = bank ? dout_b : dout_a;

endmodule
