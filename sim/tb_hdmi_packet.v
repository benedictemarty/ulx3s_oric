// Testbench de l'assembleur de data island packet (rtl/hdmi_packet_assembler.v).
//
// Le module est combinatoire : on lit packet_data pour counter = 0..31,
// on reconstitue les mots complets (header 32 bits, subpackets 64 bits) puis
// on vérifie :
//   1. FRAMING — les bits de données reconstitués valent exactement les
//      entrées (ordre / mapping des canaux corrects) ;
//   2. ECC — le syndrome BCH du mot complet (données + parité) est nul, ce qui
//      prouve que la parité est le reste de la division par le polynôme et que
//      la sérialisation place les bits au bon endroit.
// Répété sur plusieurs jeux de données pseudo-aléatoires.
`timescale 1ns/1ps

module tb_hdmi_packet;

    reg  [23:0] header;
    reg  [55:0] sub0, sub1, sub2, sub3;
    reg  [4:0]  counter;
    wire [8:0]  packet_data;

    hdmi_packet_assembler dut (
        .header(header), .sub0(sub0), .sub1(sub1), .sub2(sub2), .sub3(sub3),
        .counter(counter), .packet_data(packet_data)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    // Passage de `nbits` bits (LSB d'abord) dans le LFSR BCH 0x83.
    function [7:0] lfsr_run;
        input [63:0] bits;
        input integer nbits;
        integer k; reg [7:0] e;
        begin
            e = 8'd0;
            for (k = 0; k < nbits; k = k + 1)
                e = (e >> 1) ^ (((e[0] ^ bits[k]) == 1'b1) ? 8'h83 : 8'h00);
            lfsr_run = e;
        end
    endfunction

    // Mots reconstitués depuis la sérialisation
    reg [31:0] r_bch4;
    reg [63:0] r_bch0, r_bch1, r_bch2, r_bch3;
    integer i, t;

    // xorshift 32 bits pour générer des vecteurs
    reg [31:0] rng = 32'h1234_5678;
    function [31:0] nextrng;
        input [31:0] x;
        begin
            x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
            nextrng = x;
        end
    endfunction

    initial begin
        for (t = 0; t < 8; t = t + 1) begin
            // Nouveau jeu de données
            rng = nextrng(rng); header      = rng[23:0];
            rng = nextrng(rng); sub0[31:0]  = rng; rng = nextrng(rng); sub0[55:32] = rng[23:0];
            rng = nextrng(rng); sub1[31:0]  = rng; rng = nextrng(rng); sub1[55:32] = rng[23:0];
            rng = nextrng(rng); sub2[31:0]  = rng; rng = nextrng(rng); sub2[55:32] = rng[23:0];
            rng = nextrng(rng); sub3[31:0]  = rng; rng = nextrng(rng); sub3[55:32] = rng[23:0];

            // Reconstitution sur les 32 pixels
            r_bch4 = 0; r_bch0 = 0; r_bch1 = 0; r_bch2 = 0; r_bch3 = 0;
            for (i = 0; i < 32; i = i + 1) begin
                counter = i[4:0];
                #1;
                r_bch4[i]        = packet_data[0];
                r_bch0[2*i]      = packet_data[1];
                r_bch1[2*i]      = packet_data[2];
                r_bch2[2*i]      = packet_data[3];
                r_bch3[2*i]      = packet_data[4];
                r_bch0[2*i+1]    = packet_data[5];
                r_bch1[2*i+1]    = packet_data[6];
                r_bch2[2*i+1]    = packet_data[7];
                r_bch3[2*i+1]    = packet_data[8];
            end

            // 1. Framing : les bits de données correspondent aux entrées
            check(r_bch4[23:0] === header, "framing header");
            check(r_bch0[55:0] === sub0,   "framing sub0");
            check(r_bch1[55:0] === sub1,   "framing sub1");
            check(r_bch2[55:0] === sub2,   "framing sub2");
            check(r_bch3[55:0] === sub3,   "framing sub3");

            // 2. ECC : syndrome BCH nul sur le mot complet (données + parité)
            check(lfsr_run({32'd0, r_bch4}, 32) === 8'd0, "syndrome header nul");
            check(lfsr_run(r_bch0, 64) === 8'd0, "syndrome sub0 nul");
            check(lfsr_run(r_bch1, 64) === 8'd0, "syndrome sub1 nul");
            check(lfsr_run(r_bch2, 64) === 8'd0, "syndrome sub2 nul");
            check(lfsr_run(r_bch3, 64) === 8'd0, "syndrome sub3 nul");
        end

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_hdmi_packet)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
