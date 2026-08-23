// Extraction du nom de fichier depuis le flux .tap capturé (US-CSAVE.4 phase D).
// Observe (sans le consommer) le flux d'octets produit par `tape_demod` pendant
// un CSAVE et reconstruit un nom 8.3 FAT à partir du nom ASCII de l'en-tête
// cassette Oric.
//
// Format du flux (cf. tools/recv_tap.py, réf. ~/Oric1/src/io/cassette.c) :
//   amorce 0x16…  puis marqueur 0x24  puis 9 octets d'en-tête  puis le nom
//   ASCII terminé par 0x00  puis les données.
//
// Le nom Oric est tronqué à 8 caractères, mis en majuscules, les caractères
// non [A-Z0-9] remplacés par '_', complété par des espaces ; l'extension est
// forcée à "TAP". Un nom vide donne "NONAME  ". `name_ready` monte dès le 0x00
// terminateur ; `name83` (11 octets, comme q_name) est alors stable.
//
// `capturing` bas (fin/hors capture) réarme l'extracteur pour le CSAVE suivant.

module tape_name (
    input             clk,
    input             rst,
    input      [7:0]  byte_in,
    input             byte_valid,
    input             capturing,
    output reg [87:0] name83,      // nom 8.3 (11 octets, MSB = 1er caractère)
    output reg        name_ready
);
    localparam TN_SYNC = 2'd0, TN_HDR = 2'd1, TN_NAME = 2'd2, TN_DONE = 2'd3;
    reg [1:0]  st;
    reg [3:0]  hdrcnt;             // 0..9 octets d'en-tête consommés
    reg [3:0]  npos;               // 0..8 caractères de nom capturés
    reg [7:0]  nm [0:7];           // 8 caractères 8.3

    // Normalisation d'un caractère pour un nom 8.3
    function [7:0] to83(input [7:0] ch);
        if (ch >= 8'd97 && ch <= 8'd122)                 to83 = ch - 8'd32;   // a-z -> A-Z
        else if ((ch >= 8'd65 && ch <= 8'd90) ||
                 (ch >= 8'd48 && ch <= 8'd57))           to83 = ch;          // A-Z 0-9
        else                                             to83 = "_";
    endfunction

    always @(posedge clk) begin
        if (rst || !capturing) begin
            st <= TN_SYNC; hdrcnt <= 0; npos <= 0; name_ready <= 1'b0;
        end else begin
            case (st)
                TN_SYNC: if (byte_valid && byte_in == 8'h24) begin
                             hdrcnt <= 0; st <= TN_HDR;
                         end
                TN_HDR:  if (byte_valid) begin
                             if (hdrcnt == 4'd8) begin npos <= 0; st <= TN_NAME; end
                             else hdrcnt <= hdrcnt + 4'd1;
                         end
                TN_NAME: if (byte_valid) begin
                             if (byte_in == 8'h00) begin
                                 // fige le nom : chaque position au-delà de npos
                                 // est un espace ; nom vide -> défaut. Extension
                                 // "TAP" (0x54 0x41 0x50).
                                 if (npos == 0) begin
                                     name83 <= "NONAME  TAP";
                                 end else begin
                                     name83 <= {(4'd0 < npos ? nm[0] : 8'h20),
                                                (4'd1 < npos ? nm[1] : 8'h20),
                                                (4'd2 < npos ? nm[2] : 8'h20),
                                                (4'd3 < npos ? nm[3] : 8'h20),
                                                (4'd4 < npos ? nm[4] : 8'h20),
                                                (4'd5 < npos ? nm[5] : 8'h20),
                                                (4'd6 < npos ? nm[6] : 8'h20),
                                                (4'd7 < npos ? nm[7] : 8'h20),
                                                8'h54, 8'h41, 8'h50};
                                 end
                                 name_ready <= 1'b1;
                                 st <= TN_DONE;
                             end else if (npos < 4'd8) begin
                                 nm[npos] <= to83(byte_in);
                                 npos <= npos + 4'd1;
                             end
                             // caractères au-delà de 8 : ignorés (troncature 8.3)
                         end
                default: ;   // TN_DONE : nom figé jusqu'à la fin de capture
            endcase
        end
    end
endmodule
