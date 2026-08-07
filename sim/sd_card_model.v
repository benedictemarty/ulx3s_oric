// Modèle comportemental minimal d'une carte SD en mode SPI (pour testbench).
// Esclave SPI mode 0 : échantillonne MOSI au front montant, présente MISO au
// front descendant. Reconnaît les commandes (octet [7:6]=01 + 5 octets) et
// répond : CMD0/55 -> 0x01, CMD8 -> 0x01+voltage echo, CMD41 -> 0x00,
// CMD58 -> 0x00+OCR(CCS=1), CMD17 -> 0x00 + token 0xFE + 512 octets + CRC.
// Le secteur simulé : octet i = i[7:0], sauf 510=0x55 et 511=0xAA (signature).
`timescale 1ns/1ps

module sd_card_model (
    input        cs_n,
    input        sck,
    input        mosi,
    output reg   miso
);
    reg [7:0]  rx;
    reg [3:0]  nbit;
    reg [7:0]  tx;
    reg        cmd_active;
    reg [2:0]  ci;
    reg [7:0]  c0;
    reg [7:0]  resp [0:519];
    integer    rn, rp, i;
    reg [7:0]  b;

    initial begin nbit = 0; tx = 8'hFF; cmd_active = 0; rn = 0; rp = 0; miso = 1; end

    always @(negedge cs_n) begin
        nbit <= 0; tx <= 8'hFF; cmd_active <= 0; rn <= 0; rp <= 0;
    end

    // Réception (front montant)
    always @(posedge sck) if (!cs_n) begin
        b = {rx[6:0], mosi};
        rx <= {rx[6:0], mosi};
        if (nbit == 7) begin
            nbit <= 0;
            if (!cmd_active) begin
                if (b[7:6] == 2'b01) begin cmd_active <= 1; c0 <= b; ci <= 1; end
            end else if (ci == 5) begin
                cmd_active <= 0; rp <= 0;
                case (c0)
                    8'h40: begin resp[0]=8'h01; rn<=1; end                 // CMD0
                    8'h48: begin resp[0]=8'h01; resp[1]=0; resp[2]=0;
                                 resp[3]=8'h01; resp[4]=8'hAA; rn<=5; end   // CMD8
                    8'h77: begin resp[0]=8'h01; rn<=1; end                 // CMD55
                    8'h69: begin resp[0]=8'h00; rn<=1; end                 // ACMD41
                    8'h7A: begin resp[0]=8'h00; resp[1]=8'h40; resp[2]=0;
                                 resp[3]=0; resp[4]=0; rn<=5; end           // CMD58 OCR CCS=1
                    8'h51: begin                                           // CMD17
                        resp[0]=8'h00; resp[1]=8'hFE;
                        for (i=0;i<512;i=i+1)
                            resp[2+i] = (i==510)?8'h55:(i==511)?8'hAA:i[7:0];
                        resp[514]=0; resp[515]=0; rn<=516;
                    end
                    default: begin resp[0]=8'h00; rn<=1; end
                endcase
            end else ci <= ci + 3'd1;
        end else nbit <= nbit + 4'd1;
    end

    // Émission (front descendant) : décalé d'un octet (réponse à l'octet suivant)
    always @(negedge sck) if (!cs_n) begin
        if (nbit == 0) begin
            if (rp < rn) begin miso <= resp[rp][7]; tx <= {resp[rp][6:0],1'b1}; rp <= rp + 1; end
            else begin miso <= 1'b1; tx <= 8'hFF; end
        end else begin
            miso <= tx[7]; tx <= {tx[6:0], 1'b1};
        end
    end

endmodule
