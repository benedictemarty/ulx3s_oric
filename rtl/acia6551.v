// 6551 ACIA émulé, mappé $031C-$031F sur l'Oric (standard de facto).
// Fidèle à ~/Oric1/src/io/acia6551.c :
//   $031C data | $031D status | $031E command | $031F control
//   STATUS : PE 0x01, FE 0x02, OVRN 0x04, RDRF 0x08, TDRE 0x10,
//            DCD 0x20, DSR 0x40, IRQ 0x80
//   COMMAND: DTR 0x01, IRD 0x02 (1=RX IRQ off), TIC 0x0C, ECHO 0x10, PMx
//   CONTROL: BAUD 0x0F, RXCLK 0x10, WL 0x60, SBN 0x80 (cosmétiques ici)
//
// Le débit « bande » (CONTROL) est cosmétique : les octets transitent 1:1 par
// un pont UART vers l'ESP32 (Hayes/WiFi). PE/FE ne sont jamais générés (octets
// propres). Mode IRQ simple : le bit IRQ (et la ligne /IRQ) s'arme sur une
// source active et se désarme à la lecture de STATUS ; il se réarme quand la
// source repasse active (data lu -> RDRF tombe, etc.).
//
// Deux « domaines » sur la MÊME horloge clk :
//   - côté CPU (registres) : cadencé par `cen` (impulsion 1 MHz, comme la VIA) ;
//   - côté série (pont UART) : à chaque cycle clk.

module acia6551 (
    input            clk,
    input            rst,
    // Bus CPU
    input            cen,        // cen1 : impulsion 1 MHz
    input            cs,
    input            we,
    input      [1:0] addr,
    input      [7:0] din,
    output reg [7:0] dout,
    output           irq,
    // Lignes modem (bits STATUS 5/6), fournies par l'ESP32 (v1 : câblées)
    input            dcd,
    input            dsr,
    // Pont série vers l'ESP32
    output reg [7:0] tx_data,
    output reg       tx_send,
    input            tx_busy,
    input      [7:0] rx_data,
    input            rx_valid
);

    reg [7:0] rdr, tdr, command, control;
    reg       rdrf, tdre, ovrn;
    reg       tx_start;
    reg       irq_ack;

    // Sources d'interruption
    wire rx_irq = rdrf & ~command[1];                 // RDRF & !IRD
    wire tx_irq = tdre & (command[3:2] == 2'b01);     // TDRE & TIC=01
    wire irq_event = rx_irq | tx_irq;
    assign irq = irq_event & ~irq_ack;

    wire [7:0] status = {irq, dsr, dcd, tdre, rdrf, ovrn, 1'b0, 1'b0};

    // Lecture CPU (combinatoire ; effets de bord au front cen ci-dessous)
    always @* begin
        case (addr)
            2'd0:    dout = rdr;
            2'd1:    dout = status;
            2'd2:    dout = command;
            default: dout = control;
        endcase
    end

    always @(posedge clk) begin
        tx_send <= 1'b0;

        if (rst) begin
            rdrf <= 1'b0; tdre <= 1'b1; ovrn <= 1'b0;
            command <= 8'h00; control <= 8'h00;
            tx_start <= 1'b0; irq_ack <= 1'b0;
        end else begin
            // ---- Réception série (pont) ----
            if (rx_valid) begin
                if (rdrf) ovrn <= 1'b1;         // débordement : octet perdu
                else begin rdr <= rx_data; rdrf <= 1'b1; end
            end

            // ---- Émission série (pont) ----
            if (tx_start && !tx_busy) begin
                tx_data  <= tdr;
                tx_send  <= 1'b1;
                tx_start <= 1'b0;
            end else if (!tx_start && !tx_busy) begin
                tdre <= 1'b1;                   // émetteur libre
            end

            // ---- Désarmement IRQ : la source active a été acquittée ----
            if (!irq_event) irq_ack <= 1'b0;

            // ---- Accès CPU (au front cen) ----
            if (cen && cs) begin
                if (we) begin
                    case (addr)
                        2'd0: begin tdr <= din; tdre <= 1'b0; tx_start <= 1'b1; end
                        2'd1: begin                 // reset programmé
                                  rdrf <= 1'b0; tdre <= 1'b1; ovrn <= 1'b0;
                                  tx_start <= 1'b0; irq_ack <= 1'b0;
                              end
                        2'd2: command <= din;
                        2'd3: control <= din;
                    endcase
                end else begin
                    case (addr)
                        2'd0: begin rdrf <= 1'b0; ovrn <= 1'b0; end  // lecture data
                        2'd1: irq_ack <= 1'b1;                        // lecture status -> ack IRQ
                        default: ;
                    endcase
                end
            end
        end
    end

endmodule
