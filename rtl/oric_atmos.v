// Système Oric Atmos complet (domaine clk_sys 24 MHz) :
// 6502 (Arlet) + RAM 48 Ko + ROM BASIC 1.1b + VIA 6522 + AY-3-8912 (jt49)
// + ULA + matrice clavier. Le CPU tourne à 1 MHz via RDY (un cycle bus par
// impulsion cen1) ; la ULA balaye la RAM sur le port B.
//
// Décodage : $0300-$03FF = VIA (miroirs), $C000-$FFFF = ROM, sinon RAM.

module oric_atmos #(
    parameter DIV      = 25,               // clk_sys / DIV = 1 MHz
    parameter TURBO_DIV = 6,               // clk_sys / TURBO_DIV en mode turbo
                                           // (min 6 : DI verrouillé à t4, cen1 à t5)
    parameter ROM_FILE   = "basic11b.hex",
    parameter ROM_FILE_B = "basic10.hex",
    parameter MD_ROM_FILE = "microdis.hex"
)(
    input         clk,
    input         rst,
    input         rom_bank,     // 0 = BASIC 1.1b (défaut), 1 = BASIC 1.0 —
                                // à ne changer qu'avec un reset
    input         turbo,        // accélère TOUT le domaine cen1 (CPU+VIA+AY) :
                                // la cohérence interne (Timer 2 vs cassette,
                                // délais ROM) est préservée si la source
                                // cassette accélère du même ratio. NB : les
                                // phases d'échantillonnage cartouche (t22/t23)
                                // ne sont pas atteintes en turbo — réservé aux
                                // chargements, sans cartouche active.

    // Clavier (rapport HID synchronisé)
    input         kbd_azerty,   // 0 = QWERTY positionnel, 1 = AZERTY français
    input  [7:0]  kbd_mods,
    input  [7:0]  kbd_k1, kbd_k2, kbd_k3, kbd_k4,

    // Injection clavier série (UART)
    input         inj_active,
    input  [2:0]  inj_col,
    input  [2:0]  inj_row,
    input         inj_shift,

    // Framebuffer vidéo
    output        fb_we,
    output [15:0] fb_addr,
    output [3:0]  fb_data,
    output [8:0]  scan_y,
    output [5:0]  scan_x,
    output        frame_tick,

    // Audio AY (mix 10 bits non signé)
    output [9:0]  audio,

    // Port d'extension : bus exporté + retours cartouche
    output [15:0] exp_addr,
    output        exp_we,
    output [7:0]  exp_do,
    output        exp_io_page,
    output [4:0]  exp_tphase,
    input  [7:0]  ext_din,        // donnée cartouche (valide phase 23)
    input         ext_irq,
    input         ext_romdis,
    input         ext_map,
    input         ext_ioctl,

    // Imprimante (Centronics via VIA : PA data, PB4 strobe, CA1 ack)
    output [7:0]  prn_data,
    output        prn_strobe_n,
    input         prn_ack,

    // Cassette (PB7 sortie, PB6 moteur, CB1 entrée)
    output        tape_out,
    output        tape_motor,
    input         tape_in,

    // 6551 ACIA ($031C-$031F) : pont série vers l'ESP32 (modem WiFi)
    output [7:0]  acia_tx_data,
    output        acia_tx_send,
    input         acia_tx_busy,
    input  [7:0]  acia_rx_data,
    input         acia_rx_valid,
    input         acia_dcd,
    input         acia_dsr,

    // Microdisc (US-DISK) : interface « branchée » + fournisseur de secteurs
    input         md_enable,
    input         md_disk_present,
    input  [6:0]  md_n_tracks,
    input  [4:0]  md_n_spt,
    output [6:0]  md_req_track,
    output        md_req_side,
    input         md_trk_loading,
    output [4:0]  md_sec_id,
    input         md_sec_valid,
    output [8:0]  md_sec_addr,
    input  [7:0]  md_sec_byte,

    // Debug
    output        cpu_irq_dbg
);

    // ------------------------------------------------------------------
    // Générateur de phases : tphase 0..DIV-1, cen1 = 1 MHz
    // (turbo : 0..TURBO_DIV-1). Comparaison >= et remise à zéro sur cen1 :
    // un basculement de `turbo` en cours de cycle donne au pire un cycle bus
    // unique raccourci (jamais < t5, DI déjà verrouillé à t4) ou rallongé.
    // ------------------------------------------------------------------
    reg [4:0] tphase;
    wire [4:0] wrapv = turbo ? TURBO_DIV[4:0] - 5'd1 : DIV[4:0] - 5'd1;
    wire cen1 = (tphase >= wrapv);

    always @(posedge clk)
        if (rst)
            tphase <= 5'd0;
        else
            tphase <= cen1 ? 5'd0 : tphase + 5'd1;

    // Phase VIDÉO : toujours à 1 MHz, indépendante du turbo. L'ULA balaye la
    // RAM (port B, sans contention) et nourrit le framebuffer/HDMI à cadence
    // réelle — en turbo, l'écran reste vivant (sinon : image figée, l'ULA ne
    // voyant plus les phases 6..24). Sert aussi au port d'extension
    // (échantillonnage cartouche t22/t23 = temps réel).
    reg [4:0] tphase_v;
    always @(posedge clk)
        if (rst)
            tphase_v <= 5'd0;
        else
            tphase_v <= (tphase_v == DIV - 1) ? 5'd0 : tphase_v + 5'd1;

    // ------------------------------------------------------------------
    // CPU 6502
    // ------------------------------------------------------------------
    wire [15:0] cpu_ab;
    wire [7:0]  cpu_do;
    reg  [7:0]  cpu_di;
    wire        cpu_we;
    wire        via_irq;
    wire        md_irq;
    wire [7:0]  md_dout, md_eprom_dout;
    wire        md_eprom_sel;

    cpu cpu6502 (
        .clk   (clk),
        .reset (rst),
        .AB    (cpu_ab),
        .DI    (cpu_di),
        .DO    (cpu_do),
        .WE    (cpu_we),
        .IRQ   (via_irq | ext_irq | acia_irq | md_irq),
        .NMI   (1'b0),
        .RDY   (cen1)
    );

    // Protocole bus du core d'Arlet sous RDY — re-temporisation exacte de son
    // environnement natif (mémoire synchrone pleine vitesse) :
    //  - AB/WE/DO ne sont garantis corrects que pendant la phase RDY (DIMUX
    //    bascule sur DI vivant) : on les capture AU front cen1, comme la BRAM
    //    native qui échantillonne AB au front de fin de cycle ;
    //  - le fetch mem[addr_q] s'effectue au début du cycle suivant, DI est
    //    verrouillé à t4 et consommé au front cen1 suivant — soit exactement
    //    « adresse cycle k -> donnée consommée fin de cycle k+1 » du natif ;
    //  - les écritures RAM et les accès VIA (effets de bord) s'appliquent au
    //    front cen1 avec le snapshot, un cycle bus après le natif : l'ordre
    //    écriture -> lecture est préservé (le fetch suivant part après).
    reg [15:0] bus_addr_q;
    reg        bus_we_q;
    reg [7:0]  bus_do_q;

    always @(posedge clk)
        if (cen1) begin
            bus_addr_q <= cpu_ab;
            bus_we_q   <= cpu_we;
            bus_do_q   <= cpu_do;
        end

    // Décodage — sémantique du port d'extension (wiki Defence Force) :
    // $C000-$FFFF : ROM interne si /ROMDIS inactif ; RAM cachée si /ROMDIS
    // seul ; périphérique externe si /ROMDIS ET /MAP. La VIA ne répond qu'à
    // $0300-$030F (le reste de la page 3 appartient au bus d'extension),
    // et /IOCTRL l'inhibe totalement.
    wire sel_io   = (bus_addr_q[15:8] == 8'h03);
    wire rom_area = (bus_addr_q[15:14] == 2'b11);
    wire sel_via  = sel_io & (bus_addr_q[7:4] == 4'h0) & ~ext_ioctl;
    wire sel_acia = sel_io & (bus_addr_q[7:2] == 6'b000111) & ~ext_ioctl; // $031C-$031F
    // Microdisc : $0310-$031B (la fenêtre $031C-$031F reste à l'ACIA)
    wire sel_md   = md_enable & sel_io & (bus_addr_q[7:4] == 4'h1)
                  & ~sel_acia & ~ext_ioctl;
    // /ROMDIS effectif : port d'extension OU Microdisc (EPROM de boot)
    wire md_romdis;
    wire eff_romdis = ext_romdis | md_romdis;
    wire sel_rom  = rom_area & ~eff_romdis;
    wire sel_ram  = ~sel_io & ~rom_area;
    wire rom_as_ram = rom_area & eff_romdis & ~ext_map;   // RAM cachée
    wire sel_ext  = (sel_io & ~sel_via & ~sel_acia & ~sel_md)
                  | (rom_area & ext_romdis & ext_map);    // overlay cartouche

    assign exp_addr    = bus_addr_q;
    assign exp_we      = bus_we_q;
    assign exp_do      = bus_do_q;
    assign exp_io_page = sel_io;
    assign exp_tphase  = tphase_v;

    // ------------------------------------------------------------------
    // Mémoires
    // ------------------------------------------------------------------
    wire [7:0]  ram_dout, rom_dout, via_dout, acia_dout;
    wire        acia_irq;
    wire [15:0] vram_addr;
    wire [7:0]  vram_dout;

    oric_ram ram (
        .clk    (clk),
        .addr_a (bus_addr_q),
        .we_a   (bus_we_q & (sel_ram | rom_as_ram) & cen1),
        .din_a  (bus_do_q),
        .dout_a (ram_dout),
        .addr_b (vram_addr),
        .dout_b (vram_dout)
    );

    oric_rom #(.ROM_FILE(ROM_FILE), .ROM_FILE_B(ROM_FILE_B)) rom (
        .clk  (clk),
        .bank (rom_bank),
        .addr (bus_addr_q[13:0]),
        .dout (rom_dout)
    );

    // DI verrouillé à t4 : donnée du cycle courant, stable bien avant le
    // front RDY où le CPU la consomme. Ce registre casse aussi la boucle
    // combinatoire AB->DI->AB du core d'Arlet. Les lectures du port
    // d'extension arrivent plus tard (échantillon cartouche phase 22) et
    // écrasent DI à t23 — toujours avant le front cen1 (t24).
    always @(posedge clk) begin
        if (tphase == 5'd4) begin
            if (sel_via)        cpu_di <= via_dout;
            else if (sel_acia)  cpu_di <= acia_dout;
            else if (sel_md)    cpu_di <= md_dout;
            else if (sel_rom)   cpu_di <= rom_dout;
            else if (md_eprom_sel) cpu_di <= md_eprom_dout; // EPROM Microdisc
            else if (rom_as_ram) cpu_di <= ram_dout;
            else if (sel_ext)   cpu_di <= 8'hFF;   // provisoire, écrasé à t23
            else                cpu_di <= ram_dout;
        end
        if (tphase == 5'd23 && sel_ext)
            cpu_di <= ext_din;
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
        .addr    (bus_addr_q[3:0]),
        .cs      (sel_via),
        .we      (bus_we_q),
        .din     (bus_do_q),
        .dout    (via_dout),
        .irq     (via_irq),
        .pa_in   (via_pa_in),
        .pa_out  (via_pa_out),
        .ddra_o  (via_ddra),
        .pb_in   (via_pb_in),
        .pb_out  (via_pb_out),
        .ddrb_o  (via_ddrb),
        .ca1_in  (prn_ack),               // ACK imprimante
        .ca2_out (via_ca2),
        .cb1_in  (tape_in),               // entrée cassette
        .cb2_out (via_cb2)
    );

    // 6551 ACIA ($031C-$031F) : registres côté CPU, pont série côté ESP32
    acia6551 acia (
        .clk       (clk),
        .rst       (rst),
        .cen       (cen1),
        .cs        (sel_acia),
        .we        (bus_we_q),
        .addr      (bus_addr_q[1:0]),
        .din       (bus_do_q),
        .dout      (acia_dout),
        .irq       (acia_irq),
        .dcd       (acia_dcd),
        .dsr       (acia_dsr),
        .tx_data   (acia_tx_data),
        .tx_send   (acia_tx_send),
        .tx_busy   (acia_tx_busy),
        .rx_data   (acia_rx_data),
        .rx_valid  (acia_rx_valid)
    );

    // Interface Microdisc (US-DISK) — paramètres de timing pleins ; en
    // simulation le testbench instancie microdisc directement avec des
    // timings réduits.
    microdisc #(.ROM_FILE(MD_ROM_FILE)) md (
        .clk        (clk),
        .cen        (cen1),
        .rst        (rst),
        .enable     (md_enable),
        .a          (bus_addr_q),
        .io_sel     (sel_md),
        .we         (bus_we_q),
        .din        (bus_do_q),
        .dout       (md_dout),
        .dout_valid (),
        .romdis     (md_romdis),
        .eprom_sel  (md_eprom_sel),
        .eprom_dout (md_eprom_dout),
        .rom_a      (bus_addr_q[13:0]),
        .irq        (md_irq),
        .disk_present (md_disk_present),
        .n_tracks   (md_n_tracks),
        .n_spt      (md_n_spt),
        .req_track  (md_req_track),
        .req_side   (md_req_side),
        .trk_loading(md_trk_loading),
        .sec_id     (md_sec_id),
        .sec_valid  (md_sec_valid),
        .sec_addr   (md_sec_addr),
        .sec_byte   (md_sec_byte)
    );

    assign prn_data     = via_pa_out;     // partagé avec le bus AY (fidèle)
    assign prn_strobe_n = via_pb_out[4];
    assign tape_motor   = via_pb_out[6];
    assign tape_out     = via_pb_out[7];

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
        .clk        (clk),
        .azerty     (kbd_azerty),
        .mods       (kbd_mods),
        .k1         (kbd_k1),
        .k2         (kbd_k2),
        .k3         (kbd_k3),
        .k4         (kbd_k4),
        .inj_active (inj_active),
        .inj_col    (inj_col),
        .inj_row    (inj_row),
        .inj_shift  (inj_shift),
        .col_sel    (via_pb_out[2:0]),
        .ay_ioa     (ay_ioa),
        .sense      (kbd_sense)
    );

    // ------------------------------------------------------------------
    // ULA vidéo
    // ------------------------------------------------------------------
    oric_ula #(.DIV(DIV)) ula (
        .clk        (clk),
        .rst        (rst),
        .tphase     (tphase_v),
        .vram_addr  (vram_addr),
        .vram_din   (vram_dout),
        .fb_we      (fb_we),
        .fb_addr    (fb_addr),
        .fb_data    (fb_data),
        .scan_y     (scan_y),
        .scan_x     (scan_x),
        .frame_tick (frame_tick)
    );

    assign cpu_irq_dbg = via_irq;

endmodule
