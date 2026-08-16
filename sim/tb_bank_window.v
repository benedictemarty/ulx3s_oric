// Testbench de bank_window.v (US-MBANK.1).
// Vérifie : (1) config par défaut = comportement de l'ancien oric_rom
// (bank0 = ROM A, bank1 = ROM B, banques 2..7 non peuplées -> $FF) ;
// (2) généralisation 8 banques : remapping des rôles + signal bank_is_ram.
`timescale 1ns/1ps

module tb_bank_window;

    integer errors = 0;

    reg         clk = 0;
    reg  [2:0]  sel = 0;
    reg  [13:0] addr = 0;

    always #5 clk = ~clk;

    // DUT 1 : configuration PAR DÉFAUT (bank0=ROM A, bank1=ROM B, reste vide).
    wire [7:0] d_def;
    wire       ram_def;
    bank_window #(
        .ROM_FILE_A("roms/basic11b.hex"),
        .ROM_FILE_B("roms/basic10.hex")
    ) dut_def (
        .clk(clk), .bank_sel(sel), .addr(addr),
        .dout(d_def), .bank_is_ram(ram_def)
    );

    // DUT 2 : rôles REMAPPÉS -> bank3=ROM A, bank4=ROM B, bank5=RAM, reste vide.
    //   {bank7..bank0} = {0,0,3,2,1,0,0,0}
    wire [7:0] d_rm;
    wire       ram_rm;
    bank_window #(
        .ROM_FILE_A("roms/basic11b.hex"),
        .ROM_FILE_B("roms/basic10.hex"),
        .BANK_ROLE({2'd0,2'd0,2'd3,2'd2,2'd1,2'd0,2'd0,2'd0})
    ) dut_rm (
        .clk(clk), .bank_sel(sel), .addr(addr),
        .dout(d_rm), .bank_is_ram(ram_rm)
    );

    // Applique (sel, addr) et laisse 2 fronts pour verrouiller dout_a/dout_b.
    task apply;
        input [2:0] s;
        input [13:0] a;
        begin
            sel = s; addr = a;
            @(posedge clk); @(posedge clk); #1;
        end
    endtask

    task check8;
        input [7:0] got;
        input [7:0] exp;
        input [127:0] label;
        begin
            if (got !== exp) begin
                $display("FAIL %0s : got %02x, exp %02x", label, got, exp);
                errors = errors + 1;
            end else
                $display("ok   %0s = %02x", label, got);
        end
    endtask

    task check1;
        input got;
        input exp;
        input [127:0] label;
        begin
            if (got !== exp) begin
                $display("FAIL %0s : got %b, exp %b", label, got, exp);
                errors = errors + 1;
            end else
                $display("ok   %0s = %b", label, got);
        end
    endtask

    reg [7:0] romA, romB;
    integer k;
    reg [13:0] a;

    initial begin
        // Laisse $readmemh se faire.
        @(posedge clk);

        // --- Sur plusieurs adresses : capture ROM A/B et vérifie les rôles ---
        for (k = 0; k < 3; k = k + 1) begin
            a = (k == 0) ? 14'h0000 : (k == 1) ? 14'h1FFF : 14'h0ABC;

            // ROM A via bank0 (défaut), ROM B via bank1 (défaut)
            apply(3'd0, a); romA = d_def;
            apply(3'd1, a); romB = d_def;
            $display("-- addr=%04x : ROM A=%02x ROM B=%02x", a, romA, romB);

            // (1) DÉFAUT : bank0=ROM A, bank1=ROM B, is_ram=0 partout
            apply(3'd0, a); check8(d_def, romA, "def bank0=ROMA"); check1(ram_def,1'b0,"def bank0 !ram");
            apply(3'd1, a); check8(d_def, romB, "def bank1=ROMB"); check1(ram_def,1'b0,"def bank1 !ram");
            // banques 2..7 non peuplées -> $FF, jamais RAM
            apply(3'd2, a); check8(d_def, 8'hFF, "def bank2=FF");  check1(ram_def,1'b0,"def bank2 !ram");
            apply(3'd7, a); check8(d_def, 8'hFF, "def bank7=FF");  check1(ram_def,1'b0,"def bank7 !ram");

            // (2) REMAP : bank3=ROM A, bank4=ROM B, bank5=RAM, reste=$FF
            apply(3'd3, a); check8(d_rm, romA, "rm bank3=ROMA");   check1(ram_rm,1'b0,"rm bank3 !ram");
            apply(3'd4, a); check8(d_rm, romB, "rm bank4=ROMB");   check1(ram_rm,1'b0,"rm bank4 !ram");
            apply(3'd5, a); check1(ram_rm,1'b1,"rm bank5 = RAM");  check8(d_rm, 8'hFF, "rm bank5 dout=FF");
            apply(3'd0, a); check8(d_rm, 8'hFF, "rm bank0=FF");    check1(ram_rm,1'b0,"rm bank0 !ram");
            apply(3'd7, a); check8(d_rm, 8'hFF, "rm bank7=FF");    check1(ram_rm,1'b0,"rm bank7 !ram");
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED : %0d erreur(s)", errors);
        $finish;
    end

endmodule
