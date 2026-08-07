// Assembleur de data island packet HDMI (Verilog-2005).
//
// Un data island packet occupe 32 pixels. Il transporte :
//   - un header de 24 bits (HB0,HB1,HB2) + 8 bits d'ECC BCH  = 32 bits
//   - 4 subpackets de 56 bits (SB0..SB6) + 8 bits d'ECC BCH  = 64 bits chacun
//
// L'ECC est un code BCH systématique calculé par LFSR à division polynomiale,
// polynôme 0x83 (spec HDMI 1.4, référence hdl-util/hdmi) :
//     ecc <- (ecc >> 1) ^ ((ecc[0] ^ bit) ? 8'h83 : 0)
//
// Sérialisation sur `counter` = 0..31 (mapping vérifié sur la référence) :
//   packet_data[0]   = header (1 bit/pixel)          -> canal 0
//   packet_data[4:1] = subpackets, bit 2*counter     -> canal 1
//   packet_data[8:5] = subpackets, bit 2*counter+1   -> canal 2
//
// Combinatoire : packet_data ne dépend que des données et de counter.

module hdmi_packet_assembler (
    input  [23:0] header,
    input  [55:0] sub0,
    input  [55:0] sub1,
    input  [55:0] sub2,
    input  [55:0] sub3,
    input  [4:0]  counter,        // pixel courant dans le packet (0..31)
    output [8:0]  packet_data
);

    // Division BCH (polynôme 0x83) sur `nbits` bits de `data`, LSB d'abord.
    function [7:0] bch_ecc;
        input [55:0] data;
        input integer nbits;
        integer k;
        reg [7:0] ecc;
        begin
            ecc = 8'd0;
            for (k = 0; k < nbits; k = k + 1)
                ecc = (ecc >> 1) ^ (((ecc[0] ^ data[k]) == 1'b1) ? 8'h83 : 8'h00);
            bch_ecc = ecc;
        end
    endfunction

    // Mots complets data+parité (le header n'utilise que 24 bits de données)
    wire [31:0] bch4 = {bch_ecc({32'd0, header}, 24), header};
    wire [63:0] bch0 = {bch_ecc(sub0, 56), sub0};
    wire [63:0] bch1 = {bch_ecc(sub1, 56), sub1};
    wire [63:0] bch2 = {bch_ecc(sub2, 56), sub2};
    wire [63:0] bch3 = {bch_ecc(sub3, 56), sub3};

    wire [5:0] c2   = {counter, 1'b0};        // 2*counter
    wire [5:0] c2p1 = {counter, 1'b0} | 6'd1; // 2*counter + 1

    assign packet_data[0]   = bch4[counter];
    assign packet_data[4:1] = {bch3[c2],   bch2[c2],   bch1[c2],   bch0[c2]};
    assign packet_data[8:5] = {bch3[c2p1], bch2[c2p1], bch1[c2p1], bch0[c2p1]};

endmodule
