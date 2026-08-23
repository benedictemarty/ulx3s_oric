// Test de l'extracteur de nom (US-CSAVE.4 phase D1) : injecte un flux .tap
// synthétique (amorce 0x16, marqueur 0x24, 9 octets d'en-tête, nom ASCII + 0x00,
// données) et vérifie le nom 8.3 reconstruit. Couvre : nom normal, minuscules
// + caractères invalides, nom > 8 (troncature), nom vide (défaut).
`timescale 1ns/1ps

module tb_tape_name;
    reg clk = 0; always #10 clk = ~clk;
    reg rst = 1;
    reg [7:0] byte_in = 0;
    reg       byte_valid = 0;
    reg       capturing = 0;
    wire [87:0] name83;
    wire        name_ready;

    tape_name dut (
        .clk(clk), .rst(rst), .byte_in(byte_in), .byte_valid(byte_valid),
        .capturing(capturing), .name83(name83), .name_ready(name_ready)
    );

    integer errors = 0;

    task send(input [7:0] b);
        begin
            @(negedge clk); byte_in = b; byte_valid = 1;
            @(negedge clk); byte_valid = 0;
        end
    endtask

    // Envoie amorce + en-tête + nom (chaîne, jusqu'à 0x00) + 1 octet data
    task feed_name(input [8*16-1:0] nm, input integer len);
        integer j;
        begin
            capturing = 1;
            repeat (5) send(8'h16);          // amorce
            send(8'h24);                     // marqueur
            for (j = 0; j < 9; j = j + 1) send(8'h00);   // 9 octets d'en-tête
            for (j = 0; j < len; j = j + 1)
                send(nm[8*(len-1-j) +: 8]);  // caractères du nom
            send(8'h00);                     // terminateur
            send(8'hAA);                     // 1 octet de données
        end
    endtask

    task check(input [87:0] got, input [87:0] exp, input [255:0] label);
        begin
            if (got !== exp) begin
                $display("FAIL: %0s : %h != %h", label, got, exp);
                errors = errors + 1;
            end else $display("ok  : %0s -> \"%s\"", label, got);
        end
    endtask

    task reset_cap;
        begin capturing = 0; repeat (2) @(negedge clk); end
    endtask

    initial begin
        repeat (4) @(negedge clk); rst = 0;

        // 1) nom normal
        feed_name("HELLO", 5);
        wait (name_ready === 1'b1);
        check(name83, "HELLO   TAP", "nom HELLO");
        reset_cap;

        // 2) minuscules + caractère invalide -> majuscule / '_'
        feed_name("ab.c", 4);
        wait (name_ready === 1'b1);
        check(name83, "AB_C    TAP", "ab.c -> AB_C");
        reset_cap;

        // 3) nom trop long (>8) : troncature à 8
        feed_name("LONGFILENAME", 12);
        wait (name_ready === 1'b1);
        check(name83, "LONGFILETAP", "troncature 8");
        reset_cap;

        // 4) nom vide : défaut
        feed_name("", 0);
        wait (name_ready === 1'b1);
        check(name83, "NONAME  TAP", "nom vide -> NONAME");
        reset_cap;

        if (errors == 0) $display("ALL TESTS PASSED (tb_tape_name)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin #50000000; $display("TIMEOUT"); $finish; end
endmodule
