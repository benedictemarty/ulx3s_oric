// Noise-shaper (sigma-delta du 1er ordre) pour le DAC résistif 4 bits du jack
// 3.5 mm de l'ULX3S. Le mix AY fait 10 bits ; le DAC n'en prend que 4. Au lieu
// de tronquer bêtement (`in[9:6]`, 16 niveaux), on **suréchantillonne à clk**
// (25 MHz, très au-dessus de la bande audio) : les 6 bits de poids faible sont
// accumulés et reportés (carry) dans le LSB du code 4 bits, si bien que la
// MOYENNE temporelle de la sortie suit la valeur 10 bits complète. Résolution
// effective largement augmentée, le bruit de quantification étant repoussé
// hors bande.
//
// Modulateur stable et borné (accumulateur 6 bits) : aucun emballement même à
// pleine échelle. À `in >= 960` la sortie sature à 15 (comme la troncature),
// sans divergence.

module audio_dac_sd (
    input             clk,
    input             rst,
    input      [9:0]  in,       // échantillon audio non signé (mix AY)
    output reg [3:0]  out       // vers le DAC R-2R 4 bits
);
    reg [5:0] acc;              // accumulateur des 6 bits de poids faible

    // Somme des fractions (LSB) + report éventuel dans la partie entière.
    wire [6:0] frac_sum = {1'b0, acc} + {1'b0, in[5:0]};   // bit 6 = carry
    wire [4:0] q        = {1'b0, in[9:6]} + {4'b0, frac_sum[6]};

    always @(posedge clk) begin
        if (rst) begin
            acc <= 6'd0;
            out <= 4'd0;
        end else begin
            acc <= frac_sum[5:0];
            out <= (q > 5'd15) ? 4'd15 : q[3:0];   // clamp à pleine échelle
        end
    end

endmodule
