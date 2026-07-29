// Framebuffer 240x224 x 4 bits, BRAM double horloge :
// écrit par la ULA (domaine système 24 MHz), lu par l'étage HDMI (25 MHz).

module framebuffer (
    input             wclk,
    input             we,
    input      [15:0] waddr,
    input      [3:0]  wdata,

    input             rclk,
    input      [15:0] raddr,
    output reg [3:0]  rdata
);

    reg [3:0] mem [0:53759];

    always @(posedge wclk)
        if (we)
            mem[waddr] <= wdata;

    always @(posedge rclk)
        rdata <= mem[raddr];

endmodule
