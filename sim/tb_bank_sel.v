// Testbench US-MBANK.2 : le port A du 2e VIA ($0320) pilote la banque $C000.
// Reproduit la sélection de oric_atmos.v :
//   via2_bank  = pa_out[2:0] & ddra_o[2:0]   (bits ORA en sortie)
//   bank_sel_w = (via2_bank != 0) ? via2_bank : {2'b0, rom_bank}
// et vérifie qu'écrire DDRA puis ORA au VIA-2 sélectionne bien la banque,
// avec repli sur rom_bank (BTN5) quand aucune banque n'est sélectionnée.
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

    reg        rom_bank = 0;   // chemin BTN5 (fallback)

    always #5 clk = ~clk;

    via6522 via2 (
        .clk(clk), .cen(cen), .rst(rst),
        .addr(addr), .cs(cs), .we(we), .din(din), .dout(dout), .irq(),
        .pa_in(8'hFF), .pa_out(pa_out), .ddra_o(ddra_o),
        .pb_in(8'hFF), .pb_out(pb_out), .ddrb_o(ddrb_o),
        .ca1_in(1'b1), .ca2_out(), .cb1_in(1'b1), .cb2_out()
    );

    // Réplique EXACTE de la logique de oric_atmos.v
    wire [2:0] via2_bank  = pa_out[2:0] & ddra_o[2:0];
    wire [2:0] bank_sel_w = (via2_bank != 3'd0) ? via2_bank : {2'b0, rom_bank};

    task wr;                       // écriture registre VIA (1 cycle CPU)
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

        // Au reset : DDRA=0 -> via2_bank=0 -> repli sur rom_bank
        expect(via2_bank, 3'd0, "reset via2_bank=0");
        rom_bank = 0; #1; expect(bank_sel_w, 3'd0, "reset,BTN5=0 -> bank0");
        rom_bank = 1; #1; expect(bank_sel_w, 3'd1, "reset,BTN5=1 -> bank1");
        rom_bank = 0;

        // DDRA = $07 (PA0-2 en sortie)
        wr(4'h3, 8'h07);

        // Sélection de chaque banque 1..7 via ORA ($1)
        for (b = 1; b <= 7; b = b + 1) begin
            wr(4'h1, b[7:0]);
            #1;
            expect(via2_bank, b[2:0], "via2_bank apres ORA");
            expect(bank_sel_w, b[2:0], "bank_sel_w = banque VIA");
        end

        // Banque 0 écrite au VIA : via2_bank=0 -> repli documenté sur rom_bank
        wr(4'h1, 8'h00);
        #1;
        expect(via2_bank, 3'd0, "ORA=0 -> via2_bank=0");
        rom_bank = 1; #1; expect(bank_sel_w, 3'd1, "banque VIA 0 -> repli BTN5=1");
        rom_bank = 0;

        // Seuls PA0-2 comptent : ORA=$0D (bit3 parasite) -> banque 5
        wr(4'h1, 8'h0D);
        #1;
        expect(via2_bank, 3'd5, "ORA=$0D masque -> banque 5");
        expect(bank_sel_w, 3'd5, "bank_sel_w = 5");

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED : %0d erreur(s)", errors);
        $finish;
    end

endmodule
