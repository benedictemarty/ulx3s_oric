// Test de l'interface joystick IJK : vérifie la contribution Port A (`pins`)
// contre le comportement de référence oric_joystick_port_a_pins().
`timescale 1ns/1ps

module tb_joystick_ijk;
    reg up=0, down=0, left=0, right=0, fire=0, present=0, pb4_low=0;
    reg [7:0] pa_out = 8'h00;
    wire [7:0] pins;

    joystick_ijk dut (
        .up(up), .down(down), .left(left), .right(right), .fire(fire),
        .present(present), .pa_out(pa_out), .pb4_low(pb4_low), .pins(pins)
    );

    integer errors = 0;
    task chk(input [7:0] exp, input [255:0] msg);
        begin #1;
        if (pins !== exp) begin
            $display("FAIL: %0s : got %02x exp %02x", msg, pins, exp);
            errors = errors + 1;
        end end
    endtask

    task clr; begin up=0;down=0;left=0;right=0;fire=0; end endtask

    initial begin
        // 1) pas de gamepad -> neutre quoi qu'il arrive
        present=0; pb4_low=1; pa_out=8'h40; up=1;
        chk(8'hFF, "absent -> 0xFF");
        clr; present=1;

        // 2) gamepad present mais interface non activee (pb4 haut)
        pb4_low=0; pa_out=8'h40;
        chk(8'hFF, "pb4 haut -> 0xFF");

        // 3) active, selection = aucun (bits 7:6 = 11) -> presence seule
        pb4_low=1; pa_out=8'hC0; fire=1;
        chk(8'hDF, "select aucun -> presence 0xDF");

        // 4) active, stick A (bit6=1,bit7=0), rien d'appuye -> 0xDF
        clr; pa_out=8'h40;
        chk(8'hDF, "stick A idle -> 0xDF");

        // 5) stick A, FIRE (bit2) -> 0xDB
        fire=1;
        chk(8'hDB, "stick A + fire -> 0xDB");

        // 6) stick A, UP (bit4) -> 0xCF
        clr; up=1;
        chk(8'hCF, "stick A + up -> 0xCF");

        // 7) stick A, RIGHT (bit0) -> 0xDE
        clr; right=1;
        chk(8'hDE, "stick A + right -> 0xDE");

        // 8) stick A, tout appuye (bits0-4) -> 0xC0
        up=1;down=1;left=1;right=1;fire=1;
        chk(8'hC0, "stick A + tout -> 0xC0");

        // 9) bit6=0 -> presence seule meme avec boutons
        pa_out=8'h00;
        chk(8'hDF, "bit6=0 -> presence seule 0xDF");

        if (errors == 0) $display("ALL TESTS PASSED (tb_joystick_ijk)");
        else             $display("%0d ERREUR(S)", errors);
        $finish;
    end
endmodule
