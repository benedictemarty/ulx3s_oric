// Top-level ULX3S (ECP5-85F) — Oric Atmos.
// Domaines : clk_sys 25 MHz (Oric, CPU = 25/25 = 1 MHz exact),
// clk_usb 12 MHz (clavier), clk_pixel 25 MHz + clk_shift 125 MHz (DVI).

module top_ulx3s (
    input        clk_25mhz,
    input  [6:0] btn,
    input  [3:0] sw,      // SW1 = interface Microdisc « branchée »
    input        ftdi_txd,      // UART du PC (US1) : clavier série / .tap
    output       ftdi_rxd,      // UART vers le PC (US1) : crédits cassette
    output       wifi_en,       // active l'ESP32 (modem WiFi)
    output       wifi_rxd,      // FPGA -> ESP32 : 6551 TX (modem)
    input        wifi_txd,      // ESP32 -> FPGA : 6551 RX (modem)
    output [7:0] led,
    output [3:0] gpdi_dp,
    inout        usb_fpga_bd_dp,
    inout        usb_fpga_bd_dn,
    output [3:0] audio_l,
    output [3:0] audio_r,
    inout [27:0] gp,            // port d'extension Oric (cf. docs/PORT_EXTENSION.md)
    inout [27:0] gn,
    output       wifi_gpio0,
    // Carte micro-SD (mode SPI)
    output       sd_clk,
    output       sd_cmd,
    inout  [3:0] sd_d
);

    // Maintien de l'alimentation de la carte
    assign wifi_gpio0 = 1'b1;

    // ------------------------------------------------------------------
    // Horloges
    // ------------------------------------------------------------------
    wire clk_shift, clk_pixel, clk_sys, clk_usb;
    wire lock_video, lock_sys;

    pll_video pllv (
        .clkin   (clk_25mhz),
        .clkout0 (clk_shift),    // 125 MHz
        .clkout1 (clk_pixel),    // 25 MHz
        .locked  (lock_video)
    );

    pll_sys plls (
        .clkin   (clk_25mhz),
        .clkout0 (clk_sys),      // 25 MHz (VCO 600, division exacte)
        .clkout1 (clk_usb),      // 12 MHz
        .locked  (lock_sys)
    );

    // ------------------------------------------------------------------
    // Reset : power-on + BTN1 (FIRE1)
    // ------------------------------------------------------------------
    reg [15:0] por = 16'hFFFF;
    always @(posedge clk_sys)
        if (!lock_sys || !lock_video)
            por <= 16'hFFFF;
        else if (por != 0)
            por <= por - 16'd1;

    wire ext_rst_req;
    wire rst_por = (por != 0);      // power-on seul (survit aux resets machine)
    wire rst_sys = rst_por || btn[1] || ext_rst_req || (bank_rst != 0)
                 || (dsk_rst != 0) || (sw0_rst != 0);

    // ------------------------------------------------------------------
    // Banque ROM sur BTN5 (UP) : chaque appui bascule BASIC 1.1b <-> 1.0
    // et déclenche un reset à froid (~5 ms) — le vecteur $FFFC change de
    // banque. Indicateur = la bannière au boot (V1.1 / V1.0).
    // ------------------------------------------------------------------
    reg [1:0]  b5_sync = 2'b00;
    reg [19:0] b5_deb  = 20'd0;
    reg        b5_stable = 1'b0, b5_prev = 1'b0;
    reg        rom_bank = 1'b0;
    reg [16:0] bank_rst = 17'd0;
    always @(posedge clk_sys) begin
        b5_sync <= {b5_sync[0], btn[5]};
        if (b5_sync[1] == b5_stable)
            b5_deb <= 20'd0;
        else if (b5_deb == 20'd250_000) begin   // ~10 ms stable
            b5_stable <= b5_sync[1];
            b5_deb    <= 20'd0;
        end else
            b5_deb <= b5_deb + 20'd1;
        b5_prev <= b5_stable;
        if (b5_stable && !b5_prev) begin
            rom_bank <= ~rom_bank;
            bank_rst <= 17'd125_000;            // ~5 ms de reset
        end else if (bank_rst != 0)
            bank_rst <= bank_rst - 17'd1;
    end

    reg [3:0] rst_usb_sync = 4'hF;
    always @(posedge clk_usb) rst_usb_sync <= {rst_usb_sync[2:0], rst_sys};
    wire rst_usb = rst_usb_sync[3];

    reg [3:0] rst_pix_sync = 4'hF;
    always @(posedge clk_pixel) rst_pix_sync <= {rst_pix_sync[2:0], rst_sys};
    wire rst_pixel = rst_pix_sync[3];

    // ------------------------------------------------------------------
    // Bascule disposition clavier QWERTY <-> AZERTY sur BTN6 (RIGHT).
    // Synchro + anti-rebond (~10 ms) + détection de front montant :
    // chaque appui inverse layout_azerty. led[4] indique le mode AZERTY.
    // ------------------------------------------------------------------
    reg [1:0]  b6_sync = 2'b00;
    reg [19:0] b6_deb  = 20'd0;   // ~42  ms max a 25 MHz
    reg        b6_stable = 1'b0, b6_prev = 1'b0;
    reg        layout_azerty = 1'b0;
    always @(posedge clk_sys) begin
        b6_sync <= {b6_sync[0], btn[6]};
        if (b6_sync[1] == b6_stable)
            b6_deb <= 20'd0;
        else if (b6_deb == 20'd250_000) begin   // ~10 ms stable
            b6_stable <= b6_sync[1];
            b6_deb    <= 20'd0;
        end else
            b6_deb <= b6_deb + 20'd1;
        b6_prev <= b6_stable;
        if (b6_stable && !b6_prev)               // front montant confirme
            layout_azerty <= ~layout_azerty;
    end

    // ------------------------------------------------------------------
    // Clavier USB (US2)
    // ------------------------------------------------------------------
    wire [1:0] usb_typ;
    wire       usb_report, usb_conerr;
    wire [7:0] hid_mods, hid_k1, hid_k2, hid_k3, hid_k4;
    wire       hid_gu, hid_gd, hid_gl, hid_gr, hid_ga, hid_gb;

    usb_hid_host usb (
        .usbclk        (clk_usb),
        .usbrst_n      (~rst_usb),
        .usb_dm        (usb_fpga_bd_dn),
        .usb_dp        (usb_fpga_bd_dp),
        .typ           (usb_typ),
        .report        (usb_report),
        .conerr        (usb_conerr),
        .key_modifiers (hid_mods),
        .key1          (hid_k1),
        .key2          (hid_k2),
        .key3          (hid_k3),
        .key4          (hid_k4),
        .mouse_btn     (),
        .mouse_dx      (),
        .mouse_dy      (),
        .game_l        (hid_gl), .game_r (hid_gr), .game_u (hid_gu), .game_d (hid_gd),
        .game_a        (hid_ga), .game_b (hid_gb), .game_x (), .game_y (),
        .game_sel      (), .game_sta (),
        .dbg_hid_report()
    );

    // Passage 12 MHz -> 24 MHz : signaux quasi statiques, double bascule
    reg [7:0] mods_s1, k1_s1, k2_s1, k3_s1, k4_s1;
    reg [7:0] mods_s2, k1_s2, k2_s2, k3_s2, k4_s2;
    always @(posedge clk_sys) begin
        mods_s1 <= hid_mods; k1_s1 <= hid_k1; k2_s1 <= hid_k2;
        k3_s1 <= hid_k3;     k4_s1 <= hid_k4;
        mods_s2 <= mods_s1;  k1_s2 <= k1_s1;  k2_s2 <= k2_s1;
        k3_s2 <= k3_s1;      k4_s2 <= k4_s1;
    end

    // Joystick USB (gamepad HID) -> interface IJK (US3.3). Synchro 12->24 MHz.
    // fire = bouton A ou B ; présence = un gamepad est reconnu (typ==3).
    wire       joy_present = (usb_typ == 2'd3);
    reg [5:0]  joy_s1, joy_s2;   // {present,fire,right,left,down,up}
    always @(posedge clk_sys) begin
        joy_s1 <= {joy_present, hid_ga | hid_gb, hid_gr, hid_gl, hid_gd, hid_gu};
        joy_s2 <= joy_s1;
    end

    // ------------------------------------------------------------------
    // Clavier série : UART US1 -> injection dans la matrice
    // ------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       inj_active, inj_shift, inj_ctrl;
    wire [2:0] inj_col, inj_row;

    // Console déportée : clavier PC + écran (framebuffer) sur le MÊME port
    // FTDI. Baud relevé à 1 Mbaud (25 MHz/25 exact) — un plein framebuffer
    // (26880 o) part en ~270 ms (~3-4 img/s), le texte est fluide. Les
    // outils PC (screen_view.py, send_tap.py, dump_sd.py) utilisent ce baud.
    localparam FTDI_BAUD = 1_000_000;

    uart_rx #(.CLK_HZ(25_000_000), .BAUD(FTDI_BAUD)) uart (
        .clk   (clk_sys),
        .rst   (rst_sys),
        .rx    (ftdi_txd),
        .data  (rx_data),
        .valid (rx_valid)
    );

    // Aiguillage UART : en mode cassette (tape_active), les octets vont à
    // l'injecteur .tap et NON au clavier série.
    wire       tape_active;
    wire       kbd_rx_valid = rx_valid & ~tape_active;

    key_injector inj (
        .clk        (clk_sys),
        .rst        (rst_sys),
        .rx_data    (rx_data),
        .rx_valid   (kbd_rx_valid),
        .inj_active (inj_active),
        .inj_col    (inj_col),
        .inj_row    (inj_row),
        .inj_shift  (inj_shift),
        .inj_ctrl   (inj_ctrl)
    );

    // ------------------------------------------------------------------
    // Cassette : injecteur .tap (contrôle de flux par crédits sur ftdi_rxd)
    // ------------------------------------------------------------------
    wire       tape_line;      // -> tape_in (VIA CB1)
    wire       tape_motor_w;   // <- VIA PB6
    wire [7:0] tap_tx_data;
    wire       tap_tx_send, tap_tx_busy;

    // Chargeur cassette depuis la carte SD (pilote le tape_injector à la place
    // du PC quand un chargement est en cours ; signaux définis plus bas).
    wire       ld_active;
    wire [7:0] ld_rx_data;
    wire       ld_rx_valid;

    // Mode TURBO automatique pendant un chargement cassette : tout le domaine
    // cen1 (CPU+VIA+AY) passe de 1 MHz à ~4,17 MHz et l'injecteur réduit ses
    // demi-périodes du même ratio — cohérence CLOAD/Timer 2 préservée, le
    // chargement réel est ~4× plus court. Retour à 1 MHz dès la fin du fichier.
    // Corrigé 2026-08-12 (cf. tape_injector.v) : la fenêtre inter-octets de la
    // ROM (traitement + IRQ T1) dépassait les 4 stop bits → l'injecteur émet
    // 4 stops de plus par octet en turbo. Validé en sim bout-en-bout tb_cload.
    wire turbo = tape_active;

    tape_injector tape (
        .clk         (clk_sys),
        .rst         (rst_sys),
        .rx_data     (ld_active ? ld_rx_data  : rx_data),
        .rx_valid    (ld_active ? ld_rx_valid : rx_valid),
        .tx_data     (tap_tx_data),
        .tx_send     (tap_tx_send),
        .tx_busy     (ld_active ? 1'b0 : tap_tx_busy),  // loader = jamais occupé
        .turbo       (turbo),
        .motor       (tape_motor_w),
        .tape_line   (tape_line),
        .tape_active (tape_active)
    );

    // ------------------------------------------------------------------
    // Sauvegarde cassette (US-CSAVE.2) : démodule PB7 (tape_out, bit-bangé par
    // la ROM CSAVE) et émet les octets .tap reconstitués sur l'UART FTDI. Le
    // PC (tools/recv_tap.py) se resynchronise sur l'amorce 0x16→0x24 et écrit
    // le .tap. Débit bande (~137 o/s) << UART (115200) : aucun tampon requis,
    // le pulse byte_valid déclenche directement uart_tx (jamais occupé).
    // `sav_capturing` (haut dès le 1er front, retombe après GAP_CYCLES de
    // silence) coupe le streamer écran et donne la main à la voie SAVE.
    // CYC_THRESH = 512 µs × 25 (CPU 1 MHz, clk 25 MHz) = 12800 (défaut).
    // ------------------------------------------------------------------
    wire       tape_out_w;
    wire [7:0] sav_byte;
    wire       sav_valid, sav_capturing;
    tape_demod demod (
        .clk       (clk_sys),
        .rst       (rst_sys),
        .tape_out  (tape_out_w),
        .byte_out  (sav_byte),
        .byte_valid(sav_valid),
        .capturing (sav_capturing)
    );
    assign gp[14] = tape_out_w;    // conserve la broche d'extension tape-out

    // Streamer écran : occupe l'UART FTDI quand ni dump ni cassette ni
    // chargeur ne l'utilisent. Priorité : dump > cassette/chargeur > écran.
    // L'écran cède l'UART au dump (BTN2) et au chargement cassette DEPUIS LE
    // PC (crédits sur ftdi_rxd). Pendant un chargement DEPUIS LA SD (ld_active),
    // aucun crédit n'est émis -> l'UART est libre -> on garde l'écran VIVANT
    // (on voit « Searching… » puis le jeu se charger). tape_active seul (sans
    // ld_active) = cassette PC -> on cède.
    wire        scr_enable = ~dump_active & ~(tape_active & ~ld_active) & ~sav_capturing;
    wire [15:0] scr_raddr;
    wire [3:0]  scr_rdata;
    wire        scr_rd_valid;
    wire [7:0]  scr_tx_data;
    wire        scr_tx_send, scr_active;

    // OSD recomposité dans le flux console (coordonnées framebuffer, 8x8) :
    // même liste de fichiers que l'OSD HDMI, via le 3e port de noms de fat32.
    wire [9:0]  scr_ov_x, scr_ov_y;
    wire        scr_osd_on;
    wire [7:0]  scr_osd_r, scr_osd_g, scr_osd_b;
    wire [5:0]  scr_osd_nidx;
    wire [87:0] scr_osd_name;
    osd #(.OSD_X(8), .OSD_Y(8), .COLS(11), .ROWS(13), .ZL(0)) osd_scr (
        .hc(scr_ov_x), .vc(scr_ov_y),
        .enable(fat_done && !tape_active && osd_open),
        .file_count(file_count), .sel_idx(sel_idx),
        .name_idx(scr_osd_nidx), .name(scr_osd_name),
        .osd_on(scr_osd_on), .osd_r(scr_osd_r), .osd_g(scr_osd_g), .osd_b(scr_osd_b)
    );
    wire [2:0]  scr_ov_col = {scr_osd_b[7], scr_osd_g[7], scr_osd_r[7]};

    screen_stream scr (
        .clk(clk_sys), .rst(rst_sys), .enable(scr_enable),
        .raddr(scr_raddr), .rdata(scr_rdata), .rd_valid(scr_rd_valid),
        .ov_x(scr_ov_x), .ov_y(scr_ov_y),
        .ov_on(scr_osd_on), .ov_col(scr_ov_col),
        .tx_data(scr_tx_data), .tx_send(scr_tx_send),
        .tx_busy(tap_tx_busy), .active(scr_active)
    );

    uart_tx #(.CLK_HZ(25_000_000), .BAUD(FTDI_BAUD)) uart_credits (
        .clk  (clk_sys),
        .rst  (rst_sys),
        .data (dump_active   ? dump_tx_data
               : sav_capturing ? sav_byte
               : scr_enable    ? scr_tx_data : tap_tx_data),
        .send (dump_active   ? dump_tx_send
               : sav_capturing ? sav_valid
               : scr_enable    ? scr_tx_send
               : (ld_active ? 1'b0 : tap_tx_send)),
        .tx   (ftdi_rxd),
        .busy (tap_tx_busy)
    );

    // ------------------------------------------------------------------
    // Modem WiFi : pont UART entre le 6551 ACIA et l'ESP32 embarqué
    // (US-MODEM phase 1 ; le firmware Hayes/WiFi arrive en phase 2)
    // ------------------------------------------------------------------
    assign wifi_en = 1'b1;                 // maintient l'ESP32 actif
    wire [7:0] acia_tx_data, acia_rx_data;
    wire       acia_tx_send, acia_tx_busy, acia_rx_valid;

    uart_tx #(.CLK_HZ(25_000_000), .BAUD(115_200)) uart_acia_tx (
        .clk  (clk_sys),
        .rst  (rst_sys),
        .data (acia_tx_data),
        .send (acia_tx_send),
        .tx   (wifi_rxd),                  // FPGA -> ESP32
        .busy (acia_tx_busy)
    );

    uart_rx #(.CLK_HZ(25_000_000), .BAUD(115_200)) uart_acia_rx (
        .clk   (clk_sys),
        .rst   (rst_sys),
        .rx    (wifi_txd),                 // ESP32 -> FPGA
        .data  (acia_rx_data),
        .valid (acia_rx_valid)
    );

    // ------------------------------------------------------------------
    // Système Oric
    // ------------------------------------------------------------------
    wire        fb_we;
    wire [15:0] fb_waddr;
    wire [3:0]  fb_wdata;
    wire        frame_tick;
    wire [9:0]  audio_mix;
    wire        irq_dbg;

    // Microdisc : SW1 = branché ; fournisseur de secteurs = bouchon (pas de
    // disquette tant que US-DISK.3 n'apporte pas les pistes depuis la SD) —
    // l'EPROM boote et voit un lecteur vide.
    // (SW1-reset auto RETIRÉ 2026-08-16 : suspecté de tenir le CPU en reset
    //  — écran noir + bandes = RAM non effacée. Rebasculer SW1 nécessite à
    //  nouveau un BTN1 manuel ; à réintroduire proprement (debounce) plus tard.)
    // SW1 (Microdisc branché) : reset auto au basculement, AVEC anti-rebond
    // (~10 ms stable, exactement comme BTN5) et détection des DEUX sens. Un
    // simple synchroniseur ne suffit PAS : les rebonds mécaniques font des
    // fronts multiples sur le signal brut -> resets en boucle -> CPU tenu en
    // reset (écran noir, bug du 2026-08-16). `sw0_stable` ne change qu'après
    // 10 ms stables -> au plus UN reset par basculement réel. Au power-on :
    // SW1 OFF = aucun reset ; SW1 ON = un seul reset propre (-> mode Microdisc).
    reg [1:0]  sw0_sync = 2'b00;
    reg [19:0] sw0_deb  = 20'd0;
    reg        sw0_stable = 1'b0, sw0_prev = 1'b0;
    reg [16:0] sw0_rst  = 17'd0;
    always @(posedge clk_sys) begin
        sw0_sync <= {sw0_sync[0], sw[0]};
        if (sw0_sync[1] == sw0_stable)
            sw0_deb <= 20'd0;
        else if (sw0_deb == 20'd250_000) begin   // ~10 ms stable -> valide
            sw0_stable <= sw0_sync[1];
            sw0_deb    <= 20'd0;
        end else
            sw0_deb <= sw0_deb + 20'd1;
        sw0_prev <= sw0_stable;
        if (sw0_stable != sw0_prev)               // basculement confirmé (2 sens)
            sw0_rst <= 17'd125_000;               // ~5 ms de reset
        else if (sw0_rst != 17'd0)
            sw0_rst <= sw0_rst - 17'd1;
    end

    oric_atmos #(.DIV(25), .ROM_FILE("basic11b.hex")) oric (
        .clk         (clk_sys),
        .rst         (rst_sys),
        .rom_bank    (rom_bank),
        .telestrat_mode (1'b0),   // Atmos par défaut ; ORIX/TELEMON = US-MBANK.3b
        .turbo       (turbo),
        .md_enable   (sw0_stable),
        .md_disk_present (mdp_present),
        .md_n_tracks (mdp_ntracks),
        .md_n_spt    (mdp_nspt),
        .md_req_track(mdp_reqtrk),
        .md_req_side (mdp_side),
        .md_trk_loading (mdp_trk_loading),
        .md_sec_id   (mdp_secid),
        .md_sec_valid (mdp_secvalid),
        .md_sec_addr (mdp_secaddr),
        .md_sec_byte (mdp_secbyte),
        .md_sec_we      (mdp_sec_we),
        .md_sec_wr_data (mdp_sec_wr_data),
        .md_wr_commit   (mdp_wr_commit),
        .md_wr_busy     (mdp_wr_busy),
        .md_wr_ok       (mdp_wr_ok),
        .md_wr_err      (mdp_wr_err),
        .kbd_azerty  (layout_azerty),
        .kbd_mods    (mods_s2),
        .kbd_k1      (k1_s2),
        .kbd_k2      (k2_s2),
        .kbd_k3      (k3_s2),
        .kbd_k4      (k4_s2),
        // Joystick IJK (US3.3) : {present,fire,right,left,down,up}
        .joy_up      (joy_s2[0]),
        .joy_down    (joy_s2[1]),
        .joy_left    (joy_s2[2]),
        .joy_right   (joy_s2[3]),
        .joy_fire    (joy_s2[4]),
        .joy_present (joy_s2[5]),
        .inj_active  (inj_active),
        .inj_col     (inj_col),
        .inj_row     (inj_row),
        .inj_shift   (inj_shift),
        .inj_ctrl    (inj_ctrl),
        .exp_addr    (exp_addr),
        .exp_we      (exp_we),
        .exp_do      (exp_do),
        .exp_io_page (exp_io_page),
        .exp_tphase  (exp_tphase),
        .ext_din     (ext_din),
        .ext_irq     (ext_irq),
        .ext_romdis  (ext_romdis),
        .ext_map     (ext_map),
        .ext_ioctl   (ext_ioctl),
        .prn_data    ({gn[25], gn[24], gn[23], gp[27], gp[26], gp[25], gp[24], gp[23]}),
        .prn_strobe_n(gn[26]),
        .prn_ack     (gn[27]),
        .tape_out    (tape_out_w),
        .tape_motor  (tape_motor_w),
        .tape_in     (tape_line),      // alimenté par l'injecteur .tap
        .acia_tx_data (acia_tx_data),
        .acia_tx_send (acia_tx_send),
        .acia_tx_busy (acia_tx_busy),
        .acia_rx_data (acia_rx_data),
        .acia_rx_valid(acia_rx_valid),
        .acia_dcd     (1'b1),          // modem interne toujours présent (réf.
        .acia_dsr     (1'b1),          // acia6551.c : dcd=dsr=true à l'init)
        .fb_we       (fb_we),
        .fb_addr     (fb_waddr),
        .fb_data     (fb_wdata),
        .frame_tick  (frame_tick),
        .audio       (audio_mix),
        .cpu_irq_dbg (irq_dbg)
    );

    // ------------------------------------------------------------------
    // Port d'extension Oric (GPIO, cf. docs/PORT_EXTENSION.md)
    // ------------------------------------------------------------------
    wire [15:0] exp_addr;
    wire        exp_we, exp_io_page;
    wire [7:0]  exp_do;
    wire [4:0]  exp_tphase;
    wire [7:0]  ext_din;
    wire        ext_irq, ext_romdis, ext_map, ext_ioctl;

    expansion_port exp (
        .clk          (clk_sys),
        .rst          ((por != 0) || btn[1]),   // pas ext_rst_req : évite le verrou
        .tphase       (exp_tphase),
        .bus_addr     (exp_addr),
        .bus_we       (exp_we),
        .bus_do       (exp_do),
        .sel_io_page  (exp_io_page),
        .ext_din      (ext_din),
        .ext_irq      (ext_irq),
        .ext_romdis   (ext_romdis),
        .ext_map      (ext_map),
        .ext_ioctl    (ext_ioctl),
        .ext_rst_req  (ext_rst_req),
        // gp/gn[11..17] évitées : partagées avec l'ESP32 et l'ADC
        .pin_a        ({gp[22:18], gp[10:0]}),   // A15..A11, A10..A0
        .pin_d        (gn[7:0]),
        .pin_rw       (gn[8]),
        .pin_phi2     (gn[9]),
        .pin_io_n     (gn[10]),
        .pin_rst_n    (gn[18]),
        .pin_irq_n    (gn[19]),
        .pin_romdis_n (gn[20]),
        .pin_map_n    (gn[21]),
        .pin_ioctl_n  (gn[22]),
        // Pilotage du transceiver de données 74LVCC3245A (gp/gn[16] :
        // partagées avec des entrées ADC inutilisées, haute impédance)
        .pin_xcvr_dir (gp[16]),
        .pin_xcvr_oe_n(gn[16])
    );

    // ------------------------------------------------------------------
    // Vidéo
    // ------------------------------------------------------------------
    wire [15:0] fb_raddr;
    wire [3:0]  fb_rdata;

    framebuffer fb (
        .wclk  (clk_sys),
        .we    (fb_we),
        .waddr (fb_waddr),
        .wdata (fb_wdata),
        .rclk  (clk_pixel),
        .raddr (fb_raddr),
        .rdata (fb_rdata),
        .raddr2   (scr_raddr),
        .rdata2   (scr_rdata),
        .rd2_valid(scr_rd_valid)
    );

    // Audio pour le HDMI : PSG 10 bits non signé -> PCM 16 bits signé.
    // Décalage à gauche (cadrage MSB) + inversion du bit de signe
    // (offset-binary -> complément à deux). Traversée du domaine clk_sys ->
    // clk_pixel par double bascule (signal audio lent : skew négligeable).
    wire [15:0] aud_signed = {audio_mix, 6'b0} ^ 16'h8000;
    reg  [15:0] aud_p1, aud_p2;
    always @(posedge clk_pixel) begin
        aud_p1 <= aud_signed;
        aud_p2 <= aud_p1;
    end

    wire [5:0]  osd_name_idx;
    wire [87:0] osd_q2_name;

    hdmi_out #(.SW(16)) hdmi (
        .clk_pixel (clk_pixel),
        .clk_shift (clk_shift),
        .rst       (rst_pixel),
        .fb_raddr  (fb_raddr),
        .fb_rdata  (fb_rdata),
        .aud_l     (aud_p2),
        .aud_r     (aud_p2),
        .osd_enable     (fat_done && !tape_active && osd_open),
        .osd_file_count (file_count),
        .osd_sel_idx    (sel_idx),
        .osd_name_idx   (osd_name_idx),
        .osd_name       (osd_q2_name),
        .gpdi_dp   (gpdi_dp)
    );

    // ------------------------------------------------------------------
    // Audio : DAC résistif 4 bits de l'ULX3S (jack 3.5 mm). Noise-shaper
    // sigma-delta (suréchantillonné à 25 MHz) pour restituer les 10 bits du
    // mix AY sur les 4 bits du DAC — bien mieux que la troncature `[9:6]`.
    // ------------------------------------------------------------------
    wire [3:0] audio_sd;
    audio_dac_sd audio_dac (
        .clk(clk_sys), .rst(rst_sys), .in(audio_mix), .out(audio_sd)
    );
    assign audio_l = audio_sd;
    assign audio_r = audio_sd;

    // ------------------------------------------------------------------
    // Carte micro-SD (SPI) + parseur FAT32 — liste les .tap/.dsk de la carte
    // ------------------------------------------------------------------
    wire        sd_ready, sd_busy, sd_error, sd_dvalid;
    wire [7:0]  sd_data, sd_status;
    wire        fat_rd_start;
    wire [31:0] fat_rd_sector;

    // SD + FAT = périphériques : reset au power-on SEUL (rst_por), pas à
    // chaque reset CPU. Sinon un BTN1/BTN5 ré-initialise la SD (qui n'aime
    // pas ça sans coupure d'alim) -> fat_done retombe à 0 -> OSD désactivé.
    // Écriture SD : fat32 pilote start_write/wr_data (US-DISK.5). wr_idx est
    // exposé pour que la source (dsk_track, phase 3) présente le bon octet.
    wire        fat_wr_start;
    wire [7:0]  fat_wr_data;
    wire [8:0]  sd_wr_idx;
    // Source d'écriture = dsk_track (US-DISK.5 ph.3/4) : write-back RMW.
    wire        dsk_wblk_start;
    wire [5:0]  dsk_wblk_idx;
    wire [31:0] dsk_wblk_offset;
    wire [7:0]  dsk_wblk_data;
    wire [8:0]  dsk_wblk_pos;
    wire        dsk_wblk_done, dsk_wblk_error;

    // 2e client d'écriture = tape_saver (US-CSAVE.3 ph.B) : sauvegarde cassette
    // vers SAVE.TAP. Disque et cassette-save sont mutuellement exclusifs → un
    // simple mux arbitre fat32.wblk (le saver prend la main quand il est busy ;
    // les sorties wblk_pos/done/error de fat32 sont partagées aux deux clients).
    wire        sav_wblk_start;
    wire [5:0]  sav_wblk_idx;
    wire [31:0] sav_wblk_offset;
    wire [7:0]  sav_wblk_data;
    wire        sav_busy, sav_done, sav_error;
    wire [31:0] sav_nbytes;
    // US-CSAVE.4 : vraie création FAT32 orchestrée par tape_creator (extraction
    // du nom -> alloc -> mkent -> écriture avec extension -> dsize). Remplace la
    // localisation d'un placeholder SAVE.TAP.
    wire        cr_alloc_start, cr_mkent_start, cr_dsize_start;
    wire [31:0] cr_alloc_prev, cr_mkent_clus, cr_mkent_size, cr_dsize_val;
    wire [87:0] cr_mkent_name;
    wire [5:0]  cr_mkent_idx, cr_dsize_idx;
    wire [31:0] cr_alloc_clus;
    wire        cr_alloc_done, cr_alloc_error, cr_mkent_done, cr_mkent_error, cr_dsize_done;
    wire [5:0]  cr_file_idx;
    wire        cr_file_ready, cr_busy;

    // Sélection de source vers fat32.wblk (saver prioritaire pendant une save).
    wire        wblk_start_s  = sav_busy ? sav_wblk_start  : dsk_wblk_start;
    wire [5:0]  wblk_idx_s    = sav_busy ? sav_wblk_idx    : dsk_wblk_idx;
    wire [31:0] wblk_offset_s = sav_busy ? sav_wblk_offset : dsk_wblk_offset;
    wire [7:0]  wblk_data_s   = sav_busy ? sav_wblk_data   : dsk_wblk_data;

    // Chemin WD1793 -> dsk_track (écriture de secteur, ph.4)
    wire        mdp_sec_we, mdp_wr_commit, mdp_wr_busy, mdp_wr_ok, mdp_wr_err;
    wire [7:0]  mdp_sec_wr_data;

    sd_spi #(.CLK_HZ(25_000_000), .HALF(32)) sdc (
        .clk(clk_sys), .rst(rst_por),
        .start_read(fat_rd_start),
        .start_write(fat_wr_start), .wr_data(fat_wr_data), .wr_idx(sd_wr_idx),
        .sector(fat_rd_sector),
        .ready(sd_ready), .busy(sd_busy), .error(sd_error),
        .data(sd_data), .data_valid(sd_dvalid), .status(sd_status),
        .sck(sd_clk), .mosi(sd_cmd), .miso(sd_d[0]), .cs_n(sd_d[3])
    );
    assign sd_d[1] = 1'b1;             // non utilisées en SPI : maintenues hautes
    assign sd_d[2] = 1'b1;

    reg         fat_start, fat_trig;
    wire        fat_done, fat_error;
    wire [7:0]  file_count, fat_status;

    // Sélection (BTN3 = suivant), chargement (BTN4), dump debug UART (BTN2)
    reg [1:0]   b2s, b3s, b4s;
    reg [19:0]  b2d, b3d, b4d;
    reg         b2stab, b3stab, b4stab, b2prev, b3prev, b4prev;
    reg [5:0]   sel_idx;
    reg         load_trigger, dump_trigger;
    // OSD ouvert/fermé : BTN4 charge ET ferme ; OSD fermé, BTN3/BTN4 ne font
    // que le rouvrir. Évite les chargements accidentels (une cassette lancée
    // pendant un boot disquette vole le bus SD et enclenche le turbo).
    reg         osd_open = 1'b1;

    always @(posedge clk_sys) begin
        b2s <= {b2s[0], btn[2]};
        b3s <= {b3s[0], btn[3]};
        b4s <= {b4s[0], btn[4]};
        if (b2s[1] == b2stab) b2d <= 0;
        else if (b2d == 20'd250_000) begin b2stab <= b2s[1]; b2d <= 0; end
        else b2d <= b2d + 20'd1;
        if (b3s[1] == b3stab) b3d <= 0;
        else if (b3d == 20'd250_000) begin b3stab <= b3s[1]; b3d <= 0; end
        else b3d <= b3d + 20'd1;
        if (b4s[1] == b4stab) b4d <= 0;
        else if (b4d == 20'd250_000) begin b4stab <= b4s[1]; b4d <= 0; end
        else b4d <= b4d + 20'd1;
        b2prev <= b2stab; b3prev <= b3stab; b4prev <= b4stab;
        load_trigger <= 1'b0;
        dump_trigger <= 1'b0;
        if (rst_sys) sel_idx <= 6'd0;   // osd_open survit : pas de réouverture
                                        // par-dessus un boot disquette
        else begin
            if (b3stab && !b3prev) begin    // front BTN3 : ouvrir / fichier suivant
                if (!osd_open) osd_open <= 1'b1;
                else sel_idx <= (sel_idx + 6'd1 >= file_count) ? 6'd0
                                                               : sel_idx + 6'd1;
            end
            if (b4stab && !b4prev) begin    // front BTN4 : ouvrir / charger
                if (!osd_open) osd_open <= 1'b1;
                else begin
                    load_trigger <= 1'b1;
                    osd_open <= 1'b0;       // fermer : plus d'appui avalé
                end
            end
            if (b2stab && !b2prev)          // front BTN2 : dump debug vers UART
                dump_trigger <= 1'b1;
        end
    end

    // Parseur FAT + lecture de fichier (q_idx = fichier sélectionné)
    wire [31:0] sel_size;
    wire        sel_isdsk;
    wire        ld_open_start, ld_fdata_ready, fat_fdata_valid, fat_feof, fat_floading;
    wire [5:0]  ld_open_idx;
    wire [7:0]  fat_fdata;
    // Dump debug UART (BTN2)
    wire        dump_open_start, dump_fdata_ready, dump_active, dump_tx_send;
    wire [7:0]  dump_tx_data;
    // Disquette (dsk_track) : 3e client du bus fat32
    wire        d_open_start, d_open_abort, d_fdata_ready;
    wire [5:0]  d_open_idx;
    wire [31:0] d_open_offset;
    wire        d_grant = ~dump_active & ~ld_active;   // priorité dump > tape > dsk

    fat32 fat (
        .clk(clk_sys), .rst(rst_por), .start(fat_start),
        .rd_start(fat_rd_start), .rd_sector(fat_rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy),
        .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error),
        .file_count(file_count), .status(fat_status),
        .q_idx(sel_idx), .q_name(), .q_size(sel_size), .q_clus(), .q_isdsk(sel_isdsk),
        .q2_idx(osd_name_idx), .q2_name(osd_q2_name),
        .q3_idx(scr_osd_nidx), .q3_name(scr_osd_name),
        .q4_idx(6'd0), .q4_name(),
        .open_start(dump_active ? dump_open_start :
                    ld_active   ? ld_open_start   : d_open_start),
        .open_offset(d_grant ? d_open_offset : 32'd0),
        .open_abort(d_grant ? d_open_abort : 1'b0),
        .open_idx((dump_active | ld_active) ? sel_idx : d_open_idx),
        .fdata_ready(dump_active ? dump_fdata_ready :
                     ld_active   ? ld_fdata_ready  : d_fdata_ready),
        .floading(fat_floading), .feof(fat_feof), .fdata(fat_fdata), .fdata_valid(fat_fdata_valid),
        // Écriture (US-DISK.5 disque / US-CSAVE.3 cassette) : source muxée
        // (dsk_track write-back OU tape_saver selon sav_busy). Les retours
        // wblk_pos/done/error sont partagés aux deux clients.
        .wblk_start(wblk_start_s), .wblk_idx(wblk_idx_s),
        .wblk_offset(wblk_offset_s), .wblk_data(wblk_data_s),
        .wblk_extend(sav_busy),   // extension à la demande pendant une save cassette
        .wblk_pos(dsk_wblk_pos), .wblk_done(dsk_wblk_done), .wblk_error(dsk_wblk_error),
        // Maj taille (US-CSAVE.4) — inscrite par tape_creator à la fin de save
        .dsize_start(cr_dsize_start), .dsize_idx(cr_dsize_idx), .dsize_val(cr_dsize_val),
        .dsize_done(cr_dsize_done), .dsize_error(),
        // Allocateur de cluster + création d'entrée (US-CSAVE.4) : pilotés par
        // tape_creator (vraie création FAT32)
        .alloc_start(cr_alloc_start), .alloc_prev(cr_alloc_prev),
        .alloc_clus(cr_alloc_clus), .alloc_done(cr_alloc_done), .alloc_error(cr_alloc_error),
        .mkent_start(cr_mkent_start), .mkent_name(cr_mkent_name),
        .mkent_clus(cr_mkent_clus), .mkent_size(cr_mkent_size),
        .mkent_idx(cr_mkent_idx), .mkent_done(cr_mkent_done), .mkent_error(cr_mkent_error),
        .wr_start(fat_wr_start), .wr_data(fat_wr_data), .wr_idx(sd_wr_idx)
    );

    fat_dump dbg (
        .clk(clk_sys), .rst(rst_sys), .trigger(dump_trigger),
        .sel_idx(sel_idx), .fat_ready(fat_done),
        .open_start(dump_open_start), .open_idx(), .fdata_ready(dump_fdata_ready),
        .fdata_valid(fat_fdata_valid), .fdata(fat_fdata), .feof(fat_feof),
        .tx_data(dump_tx_data), .tx_send(dump_tx_send), .tx_busy(tap_tx_busy),
        .active(dump_active)
    );

    // Chargeur : n'injecte que les .tap (les .dsk demandent le Microdisc)
    tape_loader ld_inst (
        .clk(clk_sys), .rst(rst_sys),
        .load_trigger(load_trigger && !sel_isdsk),
        .sel_idx(sel_idx), .file_size(sel_size), .fat_ready(fat_done),
        .open_start(ld_open_start), .open_idx(ld_open_idx), .fdata_ready(ld_fdata_ready),
        .fdata_valid(fat_fdata_valid), .fdata(fat_fdata), .feof(fat_feof),
        .tape_rx_data(ld_rx_data), .tape_rx_valid(ld_rx_valid),
        .tape_credit(tap_tx_send), .active(ld_active)
    );

    // Disquette : BTN4 sur un fichier .dsk = « insérer » (le tape_loader ne
    // prend que les .tap, cf. gate ci-dessus). L'EPROM Microdisc en attente
    // (« insert system disc ») réessaie son boot — sinon reset BTN1. SW1 doit
    // être ON pour que l'interface soit branchée.
    wire dsk_insert = load_trigger && sel_isdsk;

    // Insertion .dsk = reset automatique (US-DISK.4) : on attend que
    // l'insertion soit enregistrée (front montant de dsk_inserted — la
    // disquette survit au soft reset) puis on pulse ~5 ms de reset ; la
    // machine reboote sur l'EPROM Microdisc qui trouve la disquette.
    reg [16:0] dsk_rst = 17'd0;
    reg        dsk_rst_wait = 1'b0, dsk_ins_prev = 1'b0;
    always @(posedge clk_sys) begin
        dsk_ins_prev <= dsk_inserted;
        if (dsk_insert) dsk_rst_wait <= 1'b1;
        else if (dsk_rst_wait && dsk_inserted && !dsk_ins_prev) begin
            dsk_rst_wait <= 1'b0;
            dsk_rst <= 17'd125_000;
        end else if (dsk_rst != 0)
            dsk_rst <= dsk_rst - 17'd1;
    end
    wire dsk_inserted, dsk_bad, mdp_trk_loading, mdp_present, mdp_side, mdp_secvalid;
    wire [6:0] mdp_ntracks, mdp_reqtrk;
    wire [4:0] mdp_nspt, mdp_secid;
    wire [8:0] mdp_secaddr;
    wire [7:0] mdp_secbyte;

    dsk_track dsk (
        .clk(clk_sys), .rst(rst_por), .soft_rst(rst_sys),
        .insert(dsk_insert), .file_idx(sel_idx), .eject(1'b0),
        .inserted(dsk_inserted), .bad_format(dsk_bad),
        .bus_grant(d_grant), .fat_done(fat_done),
        .open_start(d_open_start), .open_idx(d_open_idx),
        .open_offset(d_open_offset), .open_abort(d_open_abort),
        .fdata_ready(d_fdata_ready), .fdata_valid(fat_fdata_valid),
        .fdata(fat_fdata), .feof(fat_feof),
        .req_track(mdp_reqtrk), .req_side(mdp_side),
        .trk_loading(mdp_trk_loading), .disk_present(mdp_present),
        .n_tracks(mdp_ntracks), .n_spt(mdp_nspt),
        .sec_id(mdp_secid), .sec_valid(mdp_secvalid),
        .sec_addr(mdp_secaddr), .sec_byte(mdp_secbyte),
        // écriture de secteur (WD1793 -> dsk_track) + write-back (-> fat32.wblk)
        .sec_we(mdp_sec_we), .sec_wr_data(mdp_sec_wr_data), .wr_commit(mdp_wr_commit),
        .wr_busy(mdp_wr_busy), .wr_ok(mdp_wr_ok), .wr_err(mdp_wr_err),
        .wblk_start(dsk_wblk_start), .wblk_idx(dsk_wblk_idx),
        .wblk_offset(dsk_wblk_offset), .wblk_data(dsk_wblk_data),
        .wblk_pos(dsk_wblk_pos), .wblk_done(dsk_wblk_done), .wblk_error(dsk_wblk_error)
    );

    // ------------------------------------------------------------------
    // Sauvegarde cassette -> vraie création FAT32 (US-CSAVE.4)
    // ------------------------------------------------------------------
    // tape_creator orchestre la création du fichier .tap au NOM RÉEL du
    // CSAVE"NOM" : il extrait le nom du flux (pendant l'amorce), alloue un
    // cluster, crée l'entrée de répertoire, publie file_idx/file_ready au saver,
    // puis inscrit la taille réelle à la fin. Plus de placeholder SAVE.TAP.
    // enable = fat_done : la save SD n'est armée qu'une fois la carte listée
    // (la voie UART US-CSAVE.2 reste opérationnelle indépendamment).
    tape_creator creator (
        .clk(clk_sys), .rst(rst_sys),
        .byte_in(sav_byte), .byte_valid(sav_valid), .capturing(sav_capturing),
        .alloc_start(cr_alloc_start), .alloc_prev(cr_alloc_prev),
        .alloc_clus(cr_alloc_clus), .alloc_done(cr_alloc_done), .alloc_error(cr_alloc_error),
        .mkent_start(cr_mkent_start), .mkent_name(cr_mkent_name),
        .mkent_clus(cr_mkent_clus), .mkent_size(cr_mkent_size),
        .mkent_idx(cr_mkent_idx), .mkent_done(cr_mkent_done), .mkent_error(cr_mkent_error),
        .dsize_start(cr_dsize_start), .dsize_idx(cr_dsize_idx), .dsize_val(cr_dsize_val),
        .dsize_done(cr_dsize_done),
        .sav_done(sav_done), .sav_busy(sav_busy), .sav_nbytes(sav_nbytes),
        .file_idx(cr_file_idx), .file_ready(cr_file_ready), .busy(cr_busy)
    );

    tape_saver saver (
        .clk(clk_sys), .rst(rst_sys),
        .byte_in(sav_byte), .byte_valid(sav_valid), .capturing(sav_capturing),
        .file_idx(cr_file_idx), .enable(fat_done), .file_ready(cr_file_ready),
        .wblk_start(sav_wblk_start), .wblk_idx(sav_wblk_idx),
        .wblk_offset(sav_wblk_offset), .wblk_data(sav_wblk_data),
        .wblk_pos(dsk_wblk_pos), .wblk_done(dsk_wblk_done), .wblk_error(dsk_wblk_error),
        .busy(sav_busy), .done(sav_done), .error(sav_error), .nbytes(sav_nbytes)
    );

    // Lancer le parsing une fois la carte initialisée. Sur power-on seul :
    // le listing survit aux resets CPU (l'OSD reste dispo après BTN1/BTN5).
    always @(posedge clk_sys) begin
        fat_start <= 1'b0;
        if (rst_por) fat_trig <= 1'b0;
        else if (sd_ready && !fat_trig) begin fat_start <= 1'b1; fat_trig <= 1'b1; end
    end

    // Diagnostic : compteur de secteurs lus DEPUIS le début du chargement
    // (remis à zéro à chaque déclenchement) ; figé = bloqué.
    reg [7:0] sec_cnt;
    always @(posedge clk_sys)
        if (rst_sys || load_trigger) sec_cnt <= 8'd0;
        else if (fat_rd_start) sec_cnt <= sec_cnt + 8'd1;

    // ------------------------------------------------------------------
    // US2.3 — LEDs d'activité (IRQ, VSYNC, USB HID).
    // Monostables re-déclenchables : allumés dès qu'un événement se produit,
    // éteints ~168 ms (2^22 @ 25 MHz) après le dernier. IRQ (~100 Hz) et VSYNC
    // (50 Hz) restent donc allumés en continu tant que le cœur tourne (= heart-
    // beat « il vit »), l'USB flashe à chaque rapport HID (frappe/joystick).
    // usb_report est en domaine clk_usb (12 MHz < 25 MHz) : sa largeur ≥ 2 clk_sys
    // -> resynchro par double bascule sans perte.
    // ------------------------------------------------------------------
    reg [2:0] usbrep_s;
    always @(posedge clk_sys) usbrep_s <= {usbrep_s[1:0], usb_report};

    wire act_irq, act_vsync, act_usb;
    led_activity #(.WIDTH(22)) act_i (.clk(clk_sys), .rst(rst_sys), .trig(irq_dbg),    .active(act_irq));
    led_activity #(.WIDTH(22)) act_v (.clk(clk_sys), .rst(rst_sys), .trig(frame_tick), .active(act_vsync));
    led_activity #(.WIDTH(22)) act_u (.clk(clk_sys), .rst(rst_sys), .trig(usbrep_s[2]),.active(act_usb));

    // Overlay d'activité opt-in : SW4 (sw[3]) haut -> vue activité sur les LEDs
    // hautes ; sinon la vue diagnostic SD/FAT/sélection reste inchangée.
    reg [1:0] sw3_s;
    always @(posedge clk_sys) sw3_s <= {sw3_s[0], sw[3]};

    // ------------------------------------------------------------------
    // LEDs (vue diagnostic) : erreur SD = 0xE0, erreur FAT = 0xEE ; pendant le
    // parsing = étape ; après = {chargement, .dsk?, nb_fichiers[2:0], index[2:0]}.
    // BTN3 change l'index (led[2:0]), led[6] s'allume si le fichier est un .dsk
    // (non chargeable), led[7] = chargement en cours.
    // ------------------------------------------------------------------
    wire [7:0] led_diag = sd_error   ? 8'hE0 :
                          fat_error  ? 8'hEE :
                          tape_active ? fat_status :  // etat fat32 : 91/92 lecture, 93 debit, 94/95 FAT
                          !fat_done  ? fat_status :
                          {dsk_inserted, sel_isdsk, file_count[2:0], sel_idx[2:0]};
                          // bit7 = disquette insérée (feedback BTN4 sur un .dsk)

    // Vue activité : led[7]=IRQ, led[6]=VSYNC, led[5]=USB.
    assign led = sw3_s[1] ? {act_irq, act_vsync, act_usb, 5'b00000} : led_diag;

endmodule
