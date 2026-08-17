// Testbench US-MBANK.2/.3 : sélection de banque $C000 par le 2e VIA ($0320).
// Réplique la logique de oric_atmos.v :
//   via2_drives  = (ddra_o[2:0] != 0)
//   via2_bank    = pa_out[2:0] & ddra_o[2:0]
//   bank_default = telestrat_mode ? 7 : {2'b0, rom_bank}
//   bank_sel_w   = via2_drives ? via2_bank : bank_default
// Vérifie : gate DDRA (banque 0 sélectionnable une fois DDRA piloté), repli
// BTN5 en Atmos, et défaut banque 7 en mode Telestrat (boot TELEMON/ORIX).
`timescale 1ns/1ps

module tb_bank_sel;

    integer errors = 0;

    reg        clk = 0;
    reg        rst = 1;
    reg        cen = 1;
    reg  [3:0] addr = 0;
    reg        cs = 0;
    reg        we = 0;
    reg  [7:0] din = 0;
    wire [7:0] dout;
    wire [7:0] pa_out, ddra_o, pb_out, ddrb_o;

    reg        rom_bank = 0;         // chemin BTN5 (fallback Atmos)
    reg        telestrat_mode = 0;   // 0 = Atmos, 1 = Telestrat (boot bank7)

    always #5 clk = ~clk;

    via6522 via2 (
        .clk(clk), .cen(cen), .rst(rst),
        .addr(addr), .cs(cs), .we(we), .din(din), .dout(dout), .irq(),
        .pa_in(8'hFF), .pa_out(pa_out), .ddra_o(ddra_o),
        .pb_in(8'hFF), .pb_out(pb_out), .ddrb_o(ddrb_o),
        .ca1_in(1'b1), .ca2_out(), .cb1_in(1'b1), .cb2_out()
    );

    // Réplique EXACTE de la logique de oric_atmos.v (US-MBANK.3)
    wire       via2_drives  = (ddra_o[2:0] != 3'd0);
    wire [2:0] via2_bank    = pa_out[2:0] & ddra_o[2:0];
    wire [2:0] bank_default = telestrat_mode ? 3'd7 : {2'b0, rom_bank};
    wire [2:0] bank_sel_w   = via2_drives ? via2_bank : bank_default;

    task wr;
        input [3:0] a;
        input [7:0] d;
        begin
            @(negedge clk); cs=1; we=1; addr=a; din=d;
            @(posedge clk); #1;
            @(negedge clk); cs=0; we=0;
        end
    endtask

    task expect;
        input [2:0] got;
        input [2:0] exp;
        input [127:0] label;
        begin
            if (got !== exp) begin
                $display("FAIL %0s : got %0d, exp %0d", label, got, exp);
                errors = errors + 1;
            end else
                $display("ok   %0s = %0d", label, got);
        end
    endtask

    integer b;

    initial begin
        repeat (4) @(negedge clk);
        rst = 0;
        repeat (2) @(negedge clk);

        // --- DDRA=0 (reset) : banque par défaut ---
        expect(bank_sel_w, 3'd0, "Atmos,BTN5=0 -> bank0");
        rom_bank = 1; #1; expect(bank_sel_w, 3'd1, "Atmos,BTN5=1 -> bank1");
        rom_bank = 0;
        // mode Telestrat : défaut = banque 7 (TELEMON), indépendant de BTN5
        telestrat_mode = 1; #1; expect(bank_sel_w, 3'd7, "Telestrat -> bank7 (boot)");
        rom_bank = 1; #1; expect(bank_sel_w, 3'd7, "Telestrat ignore BTN5");
        rom_bank = 0; telestrat_mode = 0; #1;

        // --- DDRA=$07 : le port A PILOTE la banque (gate) ---
        wr(4'h3, 8'h07);
        for (b = 0; b <= 7; b = b + 1) begin      // banque 0..7, dont 0 (fix)
            wr(4'h1, b[7:0]);
            #1;
            expect(bank_sel_w, b[2:0], "DDRA pilote -> banque VIA");
        end

        // Banque 0 explicitement sélectionnée (DDRA piloté) : PAS de repli BTN5
        wr(4'h1, 8'h00); #1;
        rom_bank = 1; #1;
        expect(bank_sel_w, 3'd0, "bank0 piloté (pas de repli BTN5)");
        rom_bank = 0;

        // Masquage : seuls PA0-2 comptent (ORA=$0D -> banque 5)
        wr(4'h1, 8'h0D); #1;
        expect(bank_sel_w, 3'd5, "ORA=$0D masqué -> banque 5");

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED : %0d erreur(s)", errors);
        $finish;
    end

endmodule
