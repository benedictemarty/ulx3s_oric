// RAM 64 Ko de l'Oric : port A pour le CPU (lecture/écriture),
// port B en lecture seule pour la ULA (fetch écran + charset).
// Un port d'écriture + deux ports de lecture -> BRAM ECP5.

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

    // Motif d'init Oricutron (rampattern=0) : par page de 256 octets,
    // 128 x $00 puis 128 x $FF. Indispensable au boot Sedoric : le code
    // $B932 fait un checksum de $C980-$FFFF ; une RAM toute à zéro est
    // prise pour un boot à chaud -> mini-loader 4 secteurs -> gel sur
    // vecteur $D0A5 vide. (Même init en simulation et en synthèse.)
    integer i;
    initial
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = i[7] ? 8'hFF : 8'h00;

    // Lecture/écriture exclusives (mode NO_CHANGE) : évite la duplication
    // du bloc en BSRAM Gowin (le mapper refuse le read-during-write).
    // Équivalent pour notre bus : l'adresse est stable tout le cycle 1 MHz,
    // dout_a garde la valeur lue aux cycles précédents pendant l'écriture.
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        else
            dout_a <= mem[addr_a];
    end

    always @(posedge clk)
        dout_b <= mem[addr_b];

endmodule
