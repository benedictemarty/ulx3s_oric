// Test du noise-shaper audio : pour plusieurs niveaux DC, la MOYENNE de la
// sortie 4 bits doit suivre la valeur 10 bits d'entrée (in/64), à ~1 LSB près,
// et rester bornée à pleine échelle (pas d'emballement).
`timescale 1ns/1ps

module tb_audio_dac_sd;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;
    reg  [9:0] in = 0;
    wire [3:0] out;

    audio_dac_sd dut (.clk(clk), .rst(rst), .in(in), .out(out));

    integer errors = 0;
    integer i, sum, exp_x64, got_x64, maxout;

    // Moyenne la sortie sur N cycles pour l'entrée DC courante.
    task measure(input [9:0] level, input integer expfloor);
        begin
            @(negedge clk); in = level;
            // purge de l'établissement
            repeat (64) @(negedge clk);
            sum = 0; maxout = 0;
            for (i = 0; i < 4096; i = i + 1) begin
                @(negedge clk);
                sum = sum + out;
                if (out > maxout) maxout = out;
            end
            // moyenne*64 attendue = min(level, 960) ; tolérance ±96 (1.5 LSB)
            got_x64 = (sum * 64) / 4096;
            exp_x64 = (level > 960) ? 960 : level;
            if (got_x64 > exp_x64 + 96 || got_x64 + 96 < exp_x64) begin
                $display("FAIL: in=%0d  moyenne*64=%0d attendu~%0d", level, got_x64, exp_x64);
                errors = errors + 1;
            end else
                $display("ok  : in=%0d  moyenne*64=%0d (~%0d), out_max=%0d",
                         level, got_x64, exp_x64, maxout);
            if (maxout > 15) begin
                $display("FAIL: out depasse 15 (%0d)", maxout); errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk); rst = 0;

        measure(10'd0,    0);
        measure(10'd64,   64);     // pile 1 LSB DAC
        measure(10'd100,  100);    // fractionnaire -> report SD
        measure(10'd512,  512);    // mi-échelle
        measure(10'd777,  777);
        measure(10'd960,  960);    // dernier code plein
        measure(10'd1023, 960);    // pleine échelle -> sature, pas d'emballement

        if (errors == 0) $display("ALL TESTS PASSED (tb_audio_dac_sd)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
