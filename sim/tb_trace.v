// Trace de mise au point : 300 premiers cycles bus du 6502 (hors make test).
`timescale 1ns/1ps

module tb_trace;

    localparam DIV = 13;
    reg clk = 0, rst = 1;

    oric_atmos #(.DIV(DIV), .ROM_FILE("roms/basic11b.hex")) dut (
        .clk(clk), .rst(rst), .turbo(1'b0),
        .kbd_azerty(1'b0), .kbd_mods(8'd0), .kbd_k1(8'd0), .kbd_k2(8'd0), .kbd_k3(8'd0), .kbd_k4(8'd0),
        .inj_active(1'b0), .inj_col(3'd0), .inj_row(3'd0), .inj_shift(1'b0),
        .exp_addr(), .exp_we(), .exp_do(), .exp_io_page(), .exp_tphase(),
        .ext_din(8'hFF), .ext_irq(1'b0), .ext_romdis(1'b0), .ext_map(1'b0),
        .ext_ioctl(1'b0),
        .prn_data(), .prn_strobe_n(), .prn_ack(1'b1),
        .tape_out(), .tape_motor(), .tape_in(1'b1),
        .fb_we(), .fb_addr(), .fb_data(), .frame_tick(), .audio(),
        .cpu_irq_dbg()
    );

    always #10 clk = ~clk;

    integer n = 0;

    initial begin
        repeat (10) @(negedge clk);
        rst = 0;
        forever begin
            @(posedge clk);
            if (dut.cen1) begin
                n = n + 1;
                if (n <= 300)
                    $display("%0d AB=%04x DI=%02x DO=%02x WE=%b IRQ=%b",
                             n, dut.cpu_ab, dut.cpu_di, dut.cpu_do,
                             dut.cpu_we, dut.via_irq);
                if (n == 300) $finish;
            end
        end
    end

endmodule
