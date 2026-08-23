// Test du monostable re-déclenchable led_activity : une impulsion allume la
// LED, elle reste allumée ~2^WIDTH cycles APRÈS le dernier trig, un train
// d'impulsions la maintient allumée (retriggerable), le reset l'éteint.
// WIDTH réduit (=4 -> 16 cycles) pour garder la simulation courte.
`timescale 1ns/1ps

module tb_led_activity;
    localparam WIDTH = 4;               // rémanence = 16 cycles
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;
    reg trig = 0;
    wire active;

    led_activity #(.WIDTH(WIDTH)) dut (.clk(clk), .rst(rst), .trig(trig), .active(active));

    integer errors = 0;
    integer i, life;

    task expect(input got, input exp, input [255:0] msg);
        begin
            if (got !== exp) begin
                $display("FAIL: %0s (got=%b exp=%b)", msg, got, exp);
                errors = errors + 1;
            end else
                $display("ok  : %0s", msg);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk); rst = 0;
        @(negedge clk);
        expect(active, 1'b0, "eteint au repos");

        // 1) impulsion unique -> allumage immediat, extinction apres ~2^WIDTH
        @(negedge clk); trig = 1;
        @(negedge clk); trig = 0;
        expect(active, 1'b1, "allume juste apres le trig");

        // compte le nombre de cycles ou active reste haut
        life = 0;
        while (active) begin @(negedge clk); life = life + 1; end
        // recharge a 2^WIDTH-1 puis decroit jusqu'a 0 : ~2^WIDTH cycles de vie
        if (life < (1<<WIDTH)-2 || life > (1<<WIDTH)+1) begin
            $display("FAIL: duree de vie %0d hors [%0d..%0d]", life, (1<<WIDTH)-2, (1<<WIDTH)+1);
            errors = errors + 1;
        end else
            $display("ok  : duree de vie = %0d cycles (~2^%0d)", life, WIDTH);

        // 2) train d'impulsions -> reste allume tout du long (retriggerable)
        for (i = 0; i < 40; i = i + 1) begin
            @(negedge clk); trig = 1;
            @(negedge clk); trig = 0;
            if (!active) begin
                $display("FAIL: eteint pendant le train a l'iteration %0d", i);
                errors = errors + 1;
            end
        end
        expect(active, 1'b1, "toujours allume apres le train");

        // 3) reset asynchrone de niveau -> extinction
        @(negedge clk); rst = 1;
        @(negedge clk); rst = 0;
        expect(active, 1'b0, "eteint apres reset");

        if (errors == 0) $display("ALL TESTS PASSED (tb_led_activity)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
