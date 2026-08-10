// Top-level ULX3S (ECP5-85F) — Oric Atmos.
// Domaines : clk_sys 25 MHz (Oric, CPU = 25/25 = 1 MHz exact),
// clk_usb 12 MHz (clavier), clk_pixel 25 MHz + clk_shift 125 MHz (DVI).

module top_ulx3s (
    input        clk_25mhz,
    input  [6:0] btn,
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
    wire rst_sys = (por != 0) || btn[1] || ext_rst_req;

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
        .game_l        (), .game_r (), .game_u (), .game_d (),
        .game_a        (), .game_b (), .game_x (), .game_y (),
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

    // ------------------------------------------------------------------
    // Clavier série : UART US1 -> injection dans la matrice
    // ------------------------------------------------------------------
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       inj_active, inj_shift;
    wire [2:0] inj_col, inj_row;

    uart_rx #(.CLK_HZ(25_000_000), .BAUD(115_200)) uart (
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
        .inj_shift  (inj_shift)
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

    uart_tx #(.CLK_HZ(25_000_000), .BAUD(115_200)) uart_credits (
        .clk  (clk_sys),
        .rst  (rst_sys),
        .data (dump_active ? dump_tx_data : tap_tx_data),
        .send (dump_active ? dump_tx_send : (ld_active ? 1'b0 : tap_tx_send)),
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

    oric_atmos #(.DIV(25), .ROM_FILE("basic11b.hex")) oric (
        .clk         (clk_sys),
        .rst         (rst_sys),
        .turbo       (turbo),
        .kbd_azerty  (layout_azerty),
        .kbd_mods    (mods_s2),
        .kbd_k1      (k1_s2),
        .kbd_k2      (k2_s2),
        .kbd_k3      (k3_s2),
        .kbd_k4      (k4_s2),
        .inj_active  (inj_active),
        .inj_col     (inj_col),
        .inj_row     (inj_row),
        .inj_shift   (inj_shift),
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
        .tape_out    (gp[14]),
        .tape_motor  (tape_motor_w),
        .tape_in     (tape_line),      // alimenté par l'injecteur .tap
        .acia_tx_data (acia_tx_data),
        .acia_tx_send (acia_tx_send),
        .acia_tx_busy (acia_tx_busy),
        .acia_rx_data (acia_rx_data),
        .acia_rx_valid(acia_rx_valid),
        .acia_dcd     (1'b0),          // v1 : porteuse/DSR pilotés par l'ESP32 en phase 2
        .acia_dsr     (1'b0),
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
        .pin_ioctl_n  (gn[22])
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
        .rdata (fb_rdata)
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
        .osd_enable     (fat_done && !tape_active),
        .osd_file_count (file_count),
        .osd_sel_idx    (sel_idx),
        .osd_name_idx   (osd_name_idx),
        .osd_name       (osd_q2_name),
        .gpdi_dp   (gpdi_dp)
    );

    // ------------------------------------------------------------------
    // Audio : DAC résistif 4 bits de l'ULX3S (jack 3.5 mm, conservé)
    // ------------------------------------------------------------------
    assign audio_l = audio_mix[9:6];
    assign audio_r = audio_mix[9:6];

    // ------------------------------------------------------------------
    // Carte micro-SD (SPI) + parseur FAT32 — liste les .tap/.dsk de la carte
    // ------------------------------------------------------------------
    wire        sd_ready, sd_busy, sd_error, sd_dvalid;
    wire [7:0]  sd_data, sd_status;
    wire        fat_rd_start;
    wire [31:0] fat_rd_sector;

    sd_spi #(.CLK_HZ(25_000_000), .HALF(32)) sdc (
        .clk(clk_sys), .rst(rst_sys),
        .start_read(fat_rd_start), .sector(fat_rd_sector),
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
        if (rst_sys) sel_idx <= 6'd0;
        else begin
            if (b3stab && !b3prev)          // front BTN3 : fichier suivant
                sel_idx <= (sel_idx + 6'd1 >= file_count) ? 6'd0 : sel_idx + 6'd1;
            if (b4stab && !b4prev)          // front BTN4 : charger (cassette)
                load_trigger <= 1'b1;
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

    fat32 fat (
        .clk(clk_sys), .rst(rst_sys), .start(fat_start),
        .rd_start(fat_rd_start), .rd_sector(fat_rd_sector),
        .sd_ready(sd_ready), .sd_busy(sd_busy),
        .sd_dvalid(sd_dvalid), .sd_data(sd_data),
        .done(fat_done), .error(fat_error),
        .file_count(file_count), .status(fat_status),
        .q_idx(sel_idx), .q_name(), .q_size(sel_size), .q_clus(), .q_isdsk(sel_isdsk),
        .q2_idx(osd_name_idx), .q2_name(osd_q2_name),
        .open_start(dump_active ? dump_open_start : ld_open_start),
        .open_idx(sel_idx),
        .fdata_ready(dump_active ? dump_fdata_ready : ld_fdata_ready),
        .floading(fat_floading), .feof(fat_feof), .fdata(fat_fdata), .fdata_valid(fat_fdata_valid)
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

    // Lancer le parsing une fois la carte initialisée
    always @(posedge clk_sys) begin
        fat_start <= 1'b0;
        if (rst_sys) fat_trig <= 1'b0;
        else if (sd_ready && !fat_trig) begin fat_start <= 1'b1; fat_trig <= 1'b1; end
    end

    // Diagnostic : compteur de secteurs lus DEPUIS le début du chargement
    // (remis à zéro à chaque déclenchement) ; figé = bloqué.
    reg [7:0] sec_cnt;
    always @(posedge clk_sys)
        if (rst_sys || load_trigger) sec_cnt <= 8'd0;
        else if (fat_rd_start) sec_cnt <= sec_cnt + 8'd1;

    // ------------------------------------------------------------------
    // LEDs : erreur SD = 0xE0, erreur FAT = 0xEE ; pendant le parsing = étape ;
    // après = {chargement, .dsk?, nb_fichiers[2:0], index sélectionné[2:0]}.
    // BTN3 change l'index (led[2:0]), led[6] s'allume si le fichier est un .dsk
    // (non chargeable), led[7] = chargement en cours.
    // ------------------------------------------------------------------
    assign led = sd_error   ? 8'hE0 :
                 fat_error  ? 8'hEE :
                 tape_active ? fat_status :    // etat fat32 : 91/92 lecture, 93 debit, 94/95 FAT
                 !fat_done  ? fat_status :
                 {tape_active, sel_isdsk, file_count[2:0], sel_idx[2:0]};

endmodule
