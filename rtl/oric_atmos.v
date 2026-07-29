// Système Oric Atmos complet (domaine clk_sys 24 MHz) :
// 6502 (Arlet) + RAM 48 Ko + ROM BASIC 1.1b + VIA 6522 + AY-3-8912 (jt49)
// + ULA + matrice clavier. Le CPU tourne à 1 MHz via RDY (un cycle bus par
// impulsion cen1) ; la ULA balaye la RAM sur le port B.
//
// Décodage : $0300-$03FF = VIA (miroirs), $C000-$FFFF = ROM, sinon RAM.

module oric_atmos #(
    parameter DIV      = 25,               // clk_sys / DIV = 1 MHz
    parameter ROM_FILE = "basic11b.hex"
)(
    input         clk,
    input         rst,

    // Clavier (rapport HID synchronisé)
    input  [7:0]  kbd_mods,
    input  [7:0]  kbd_k1, kbd_k2, kbd_k3, kbd_k4,

    // Framebuffer vidéo
    output        fb_we,
    output [15:0] fb_addr,
    output [3:0]  fb_data,
    output        frame_tick,

    // Audio AY (mix 10 bits non signé)
    output [9:0]  audio,

    // Debug
    output        cpu_irq_dbg
);

    // ------------------------------------------------------------------
    // Générateur de phases : tphase 0..DIV-1, cen1 = 1 MHz
    // ------------------------------------------------------------------
    reg [4:0] tphase;
    always @(posedge clk)
        if (rst)
            tphase <= 5'd0;
        else
            tphase <= (tphase == DIV - 1) ? 5'd0 : tphase + 5'd1;

    wire cen1 = (tphase == DIV - 1);

    // ------------------------------------------------------------------
    // CPU 6502
    // ------------------------------------------------------------------
    wire [15:0] cpu_ab;
    wire [7:0]  cpu_do;
    reg  [7:0]  cpu_di;
    wire        cpu_we;
    wire        via_irq;

    cpu cpu6502 (
        .clk   (clk),
        .reset (rst),
        .AB    (cpu_ab),
        .DI    (cpu_di),
        .DO    (cpu_do),
        .WE    (cpu_we),
        .IRQ   (via_irq),
        .NMI   (1'b0),
        .RDY   (cen1)
    );

    // Décodage d'adresses (stable pendant tout le cycle 1 MHz)
    wire sel_io  = (cpu_ab[15:8] == 8'h03);
    wire sel_rom = (cpu_ab[15:14] == 2'b11);
    wire sel_ram = ~sel_io & ~sel_rom;

    // ------------------------------------------------------------------
    // Mémoires
    // ------------------------------------------------------------------
    wire [7:0]  ram_dout, rom_dout, via_dout;
    wire [15:0] vram_addr;
    wire [7:0]  vram_dout;

    oric_ram ram (
        .clk    (clk),
        .addr_a (cpu_ab),
        .we_a   (cpu_we & sel_ram & cen1),
        .din_a  (cpu_do),
        .dout_a (ram_dout),
        .addr_b (vram_addr),
        .dout_b (vram_dout)
    );

    oric_rom #(.ROM_FILE(ROM_FILE)) rom (
        .clk  (clk),
        .addr (cpu_ab[13:0]),
        .dout (rom_dout)
    );

    // Mux DI registré : AB pilote combinatoirement DI->AB dans le core
    // d'Arlet, tout chemin AB->DI doit donc passer par un registre. La donnée
    // est stable dès le 3e cycle de clk, le CPU la consomme au front 1 MHz.
    always @(posedge clk) begin
        if (sel_io)       cpu_di <= via_dout;
        else if (sel_rom) cpu_di <= rom_dout;
        else              cpu_di <= ram_dout;
    end

    // ------------------------------------------------------------------
    // VIA 6522 + AY-3-8912 + clavier
    // ------------------------------------------------------------------
    wire [7:0] via_pa_out, via_pb_out;
    wire [7:0] via_ddra, via_ddrb;
    wire       via_ca2, via_cb2;          // BC1, BDIR de l'AY
    wire [7:0] ay_dout, ay_ioa;
    wire       kbd_sense;

    // Bus AY : lecture active quand BC1=1, BDIR=0
    wire [7:0] via_pa_in = (via_ca2 & ~via_cb2) ? ay_dout : 8'hFF;
    wire [7:0] via_pb_in = {4'b1111, kbd_sense, 3'b111};

    via6522 via (
        .clk     (clk),
        .cen     (cen1),
        .rst     (rst),
        .addr    (cpu_ab[3:0]),
        .cs      (sel_io),
        .we      (cpu_we),
        .din     (cpu_do),
        .dout    (via_dout),
        .irq     (via_irq),
        .pa_in   (via_pa_in),
        .pa_out  (via_pa_out),
        .ddra_o  (via_ddra),
        .pb_in   (via_pb_in),
        .pb_out  (via_pb_out),
        .ddrb_o  (via_ddrb),
        .ca1_in  (1'b1),                  // ACK imprimante, repos haut
        .ca2_out (via_ca2),
        .cb1_in  (1'b1),                  // entrée cassette (v2)
        .cb2_out (via_cb2)
    );

    jt49_bus #(.COMP(3'b000)) psg (
        .rst_n   (~rst),
        .clk     (clk),
        .clk_en  (cen1),
        .bdir    (via_cb2),
        .bc1     (via_ca2),
        .din     (via_pa_out),
        .sel     (1'b1),
        .dout    (ay_dout),
        .sound   (audio),
        .A       (),
        .B       (),
        .C       (),
        .sample  (),
        .IOA_in  (8'hFF),
        .IOA_out (ay_ioa),
        .IOA_oe  (),
        .IOB_in  (8'hFF),
        .IOB_out (),
        .IOB_oe  ()
    );

    oric_keyboard kbd (
        .clk     (clk),
        .mods    (kbd_mods),
        .k1      (kbd_k1),
        .k2      (kbd_k2),
        .k3      (kbd_k3),
        .k4      (kbd_k4),
        .col_sel (via_pb_out[2:0]),
        .ay_ioa  (ay_ioa),
        .sense   (kbd_sense)
    );

    // ------------------------------------------------------------------
    // ULA vidéo
    // ------------------------------------------------------------------
    oric_ula #(.DIV(DIV)) ula (
        .clk        (clk),
        .rst        (rst),
        .tphase     (tphase),
        .vram_addr  (vram_addr),
        .vram_din   (vram_dout),
        .fb_we      (fb_we),
        .fb_addr    (fb_addr),
        .fb_data    (fb_data),
        .frame_tick (frame_tick)
    );

    assign cpu_irq_dbg = via_irq;

endmodule
