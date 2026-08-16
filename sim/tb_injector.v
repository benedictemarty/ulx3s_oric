// Testbench clavier série : uart_rx -> key_injector -> oric_keyboard.
// Envoie 'a', '!' (shift), CR+LF (RETURN unique) sur la ligne série modélisée
// et vérifie la matrice via le sense.
`timescale 1ns/1ps

module tb_injector;

    localparam CLK_HZ = 1_000_000;   // horloge réduite pour la sim
    localparam BAUD   = 100_000;
    localparam BITNS  = 1_000_000_000 / BAUD;

    reg clk = 0, rst = 1;
    reg rx = 1;

    wire [7:0] rx_data;
    wire rx_valid;
    wire inj_active, inj_shift, inj_ctrl;
    wire [2:0] inj_col, inj_row;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) uart (
        .clk(clk), .rst(rst), .rx(rx), .data(rx_data), .valid(rx_valid)
    );

    key_injector #(.PRESS_TICKS(400), .GAP_TICKS(200)) inj (
        .clk(clk), .rst(rst), .rx_data(rx_data), .rx_valid(rx_valid),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row),
        .inj_shift(inj_shift), .inj_ctrl(inj_ctrl)
    );

    reg [2:0] col_sel = 0;
    reg [7:0] ay_ioa = 8'hFF;
    wire sense;

    oric_keyboard kbd (
        .clk(clk), .azerty(1'b0), .mods(8'd0), .k1(8'd0), .k2(8'd0), .k3(8'd0), .k4(8'd0),
        .inj_active(inj_active), .inj_col(inj_col), .inj_row(inj_row),
        .inj_shift(inj_shift), .inj_ctrl(inj_ctrl),
        .col_sel(col_sel), .ay_ioa(ay_ioa), .sense(sense)
    );

    always #500 clk = ~clk;   // 1 MHz

    integer errors = 0;
    integer i;

    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    task send_byte(input [7:0] b);
        begin
            rx = 0; #BITNS;                       // start
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i]; #BITNS;
            end
            rx = 1; #BITNS;                       // stop
        end
    endtask

    task wait_press;
        integer guard;
        begin
            guard = 0;
            while (!inj_active && guard < 100000) begin
                @(posedge clk); guard = guard + 1;
            end
        end
    endtask

    task wait_release;
        integer guard;
        begin
            guard = 0;
            while (inj_active && guard < 100000) begin
                @(posedge clk); guard = guard + 1;
            end
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rst = 0;

        // 'a' -> (6,5) sans shift
        send_byte("a");
        wait_press;
        check(inj_active, "a : touche pressee");
        check(inj_col == 3'd6 && inj_row == 3'd5, "a : position (6,5)");
        check(!inj_shift, "a : sans shift");
        col_sel = 3'd6; ay_ioa = ~(8'h01 << 5);
        @(negedge clk); @(negedge clk);
        check(sense == 1'b1, "a : sense actif");
        wait_release;
        @(negedge clk); @(negedge clk);
        check(sense == 1'b0, "a : relachee");

        // '!' -> Shift+1 : (0,5) + LSHIFT (4,4)
        send_byte("!");
        wait_press;
        check(inj_col == 3'd0 && inj_row == 3'd5, "! : position (0,5)");
        check(inj_shift, "! : shift actif");
        col_sel = 3'd4; ay_ioa = ~(8'h01 << 4);
        @(negedge clk); @(negedge clk);
        check(sense == 1'b1, "! : LSHIFT presse dans la matrice");
        wait_release;

        // CR+LF -> un seul RETURN
        send_byte(8'h0D);
        send_byte(8'h0A);
        wait_press;
        check(inj_col == 3'd7 && inj_row == 3'd5, "CR : RETURN (7,5)");
        wait_release;
        // le LF ne doit pas produire une seconde frappe
        repeat (1500) @(posedge clk);
        check(!inj_active, "LF apres CR ignore");

        // LF seul -> RETURN
        send_byte(8'h0A);
        wait_press;
        check(inj_active && inj_col == 3'd7 && inj_row == 3'd5, "LF seul = RETURN");
        wait_release;

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_injector)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("FAIL: timeout");
        $finish;
    end

endmodule
