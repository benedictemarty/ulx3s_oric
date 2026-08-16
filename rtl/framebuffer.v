// Framebuffer 240x224 x 4 bits, BRAM 2 ports (true dual-port ECP5) :
//   port A (wclk = clk_sys) : écriture ULA, ET lecture streamer écran quand
//     la ULA n'écrit pas (~90% des cycles) -> PAS de 3e accès, donc PAS de
//     duplication BRAM (cf. rtl/screen_stream.v qui attend rd2_valid) ;
//   port B (rclk = clk_pixel) : lecture par l'étage HDMI.

module framebuffer (
    input             wclk,
    input             we,
    input      [15:0] waddr,
    input      [3:0]  wdata,

    input             rclk,
    input      [15:0] raddr,
    output reg [3:0]  rdata,

    // Lecture 2 (streamer écran) partagée avec le port d'écriture (wclk)
    input      [15:0] raddr2,
    output reg [3:0]  rdata2,
    output reg        rd2_valid    // rdata2 tenu à jour ce cycle (pas d'écriture)
);

    reg [3:0] mem [0:53759];

    // Port A : écriture prioritaire ; sinon lecture de raddr2.
    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
        else    rdata2 <= mem[raddr2];
        rd2_valid <= ~we;          // aligné sur rdata2 (tous deux reflètent ce cycle)
    end

    // Port B : lecture HDMI.
    always @(posedge rclk)
        rdata <= mem[raddr];

endmodule
