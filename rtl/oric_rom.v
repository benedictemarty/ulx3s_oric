// ROM BASIC 1.1b (Atmos), 16 Ko en BRAM, initialisée par $readmemh.

module oric_rom #(
    parameter ROM_FILE = "basic11b.hex"
)(
    input             clk,
    input      [13:0] addr,
    output reg [7:0]  dout
);

    reg [7:0] mem [0:16383];

    initial $readmemh(ROM_FILE, mem);

    always @(posedge clk)
        dout <= mem[addr];

endmodule
