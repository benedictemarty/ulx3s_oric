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

    // La BRAM ECP5 démarre à zéro ; on reproduit cet état en simulation
    // (sinon les X de la RAM indéfinie corrompent l'état du 6502 simulé).
    integer i;
    initial
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 8'h00;

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
