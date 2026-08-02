// Bitstream utilitaire : force l'ESP32 embarqué de l'ULX3S en mode DOWNLOAD,
// tout en pontant l'UART FTDI <-> ESP32, pour le flasher avec esptool
// « --before no_reset » (la puce est déjà en attente de téléchargement).
//
// Le passthru officiel pulse EN mais ne tient pas GPIO0 bas sur cette carte :
// l'ESP32 reboote en mode normal au lieu du mode download. Ici on TIENT
// wifi_gpio0 bas et on applique une impulsion de reset sur wifi_en
// (bas ~0,34 s puis haut) : au front montant d'EN, GPIO0 étant bas, la ROM
// entre en mode download série.
//
// ⚠️ À charger en SRAM (temporaire). Restaurer l'Oric ensuite (make oric-flash).

module download_esp32 (
    input        clk_25mhz,
    input        ftdi_txd,     // PC -> FPGA
    output       ftdi_rxd,     // FPGA -> PC
    output       wifi_en,      // ESP32 EN
    output       wifi_rxd,     // FPGA -> ESP32 RX
    input        wifi_txd,     // ESP32 TX -> FPGA
    output       wifi_gpio0,   // ESP32 GPIO0 (bas = mode download au reset)
    output [7:0] led
);
    // Pont série transparent
    assign wifi_rxd = ftdi_txd;    // PC -> ESP32
    assign ftdi_rxd = wifi_txd;    // ESP32 -> PC

    // GPIO0 tenu bas + impulsion de reset sur EN
    assign wifi_gpio0 = 1'b0;
    reg [23:0] cnt = 24'd0;
    always @(posedge clk_25mhz)
        if (!cnt[23]) cnt <= cnt + 24'd1;
    assign wifi_en = cnt[23];      // ~0,34 s bas (reset) puis haut -> download

    // LED0 allumée quand EN est relâché (ESP32 censé être en download)
    assign led = {7'b0, cnt[23]};
endmodule
