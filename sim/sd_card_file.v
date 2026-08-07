// Modèle de carte SD (SPI) servant les secteurs depuis un fichier image
// (paramètre IMG). Comme sim/sd_card_model.v pour l'init, mais CMD17 lit le
// secteur demandé dans l'image (carte SDHC : adresse CMD17 = numéro de bloc).
`timescale 1ns/1ps

module sd_card_file #(
    parameter IMG = "fat.img"
) (
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
    reg [31:0] carg;
    reg [7:0]  resp [0:519];
    reg [7:0]  secbuf  [0:511];
    integer    rn, rp, i, fd, dummy;
    reg [7:0]  b;

    initial begin nbit=0; tx=8'hFF; cmd_active=0; rn=0; rp=0; miso=1; end

    always @(negedge cs_n) begin
        nbit <= 0; tx <= 8'hFF; cmd_active <= 0; rn <= 0; rp <= 0;
    end

    always @(posedge sck) if (!cs_n) begin
        b = {rx[6:0], mosi};
        rx <= {rx[6:0], mosi};
        if (nbit == 7) begin
            nbit <= 0;
            if (!cmd_active) begin
                if (b[7:6] == 2'b01) begin cmd_active <= 1; c0 <= b; ci <= 1; carg <= 0; end
            end else if (ci == 5) begin
                cmd_active <= 0; rp <= 0;
                case (c0)
                    8'h40: begin resp[0]=8'h01; rn<=1; end
                    8'h48: begin resp[0]=8'h01; resp[1]=0; resp[2]=0; resp[3]=8'h01; resp[4]=8'hAA; rn<=5; end
                    8'h77: begin resp[0]=8'h01; rn<=1; end
                    8'h69: begin resp[0]=8'h00; rn<=1; end
                    8'h7A: begin resp[0]=8'h00; resp[1]=8'h40; resp[2]=0; resp[3]=0; resp[4]=0; rn<=5; end
                    8'h51: begin                                   // CMD17 : lire dans l'image
                        resp[0]=8'h00; resp[1]=8'hFE;
                        fd = $fopen(IMG, "rb");
                        dummy = $fseek(fd, carg*512, 0);
                        dummy = $fread(secbuf, fd);
                        $fclose(fd);
                        for (i=0;i<512;i=i+1) resp[2+i] = secbuf[i];
                        resp[514]=0; resp[515]=0; rn<=516;
                    end
                    default: begin resp[0]=8'h00; rn<=1; end
                endcase
            end else begin
                // accumuler l'argument (octets 1..4 de la commande)
                carg <= {carg[23:0], b};
                ci <= ci + 3'd1;
            end
        end else nbit <= nbit + 4'd1;
    end

    always @(negedge sck) if (!cs_n) begin
        if (nbit == 0) begin
            if (rp < rn) begin miso <= resp[rp][7]; tx <= {resp[rp][6:0],1'b1}; rp <= rp + 1; end
            else begin miso <= 1'b1; tx <= 8'hFF; end
        end else begin
            miso <= tx[7]; tx <= {tx[6:0], 1'b1};
        end
    end
endmodule
