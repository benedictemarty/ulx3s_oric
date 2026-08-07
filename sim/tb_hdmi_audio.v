// Testbench du générateur de contenu des packets audio HDMI
// (rtl/hdmi_audio_packets.v). Vérifie les trois types de packets contre les
// valeurs attendues de la spec (headers, slices N/CTS, checksum InfoFrame,
// layout IEC60958 + parité recalculée, multi-échantillons).
`timescale 1ns/1ps

module tb_hdmi_audio;

    localparam SW = 16;

    reg  [1:0]     ptype;
    reg  [3:0]     present, frame0;
    reg  [SW-1:0]  l0, l1, l2, l3, r0, r1, r2, r3;
    wire [23:0]    header;
    wire [55:0]    sub0, sub1, sub2, sub3;

    hdmi_audio_packets #(.N(20'd4096), .CTS(20'd25000), .SAMPLE_WIDTH(SW)) dut (
        .ptype(ptype), .present(present), .frame0(frame0),
        .l0(l0), .l1(l1), .l2(l2), .l3(l3),
        .r0(r0), .r1(r1), .r2(r2), .r3(r3),
        .header(header), .sub0(sub0), .sub1(sub1), .sub2(sub2), .sub3(sub3)
    );

    integer errors = 0;
    task check(input cond, input [255:0] msg);
        if (!cond) begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    wire [23:0] l24_0 = {l0, 8'h00};
    wire [23:0] r24_0 = {r0, 8'h00};
    wire [23:0] l24_1 = {l1, 8'h00};
    wire [23:0] r24_1 = {r1, 8'h00};

    initial begin
        present = 0; frame0 = 0;
        l0=0; l1=0; l2=0; l3=0; r0=0; r1=0; r2=0; r3=0;

        // ---------- ACR (ptype 0) ----------
        ptype = 2'd0; #1;
        check(header === 24'h000001, "ACR header (HB0=0x01)");
        check(sub0 === 56'h001000A8610000, "ACR subpacket N/CTS");
        check(sub1 === sub0 && sub2 === sub0 && sub3 === sub0, "ACR 4 subpackets identiques");

        // ---------- Audio InfoFrame (ptype 1) ----------
        ptype = 2'd1; #1;
        check(header === 24'h0A0184, "InfoFrame header (0x84/0x01/0x0A)");
        check(sub0[15:8] === 8'h01, "InfoFrame PB1 = 0x01 (LPCM 2ch)");
        check(((header[7:0] + header[15:8] + header[23:16]
              + sub0[7:0] + sub0[15:8] + sub0[23:16] + sub0[31:24]
              + sub0[39:32] + sub0[47:40] + sub0[55:48]) & 8'hFF) === 8'h00,
              "InfoFrame checksum (somme nulle)");

        // ---------- Audio Sample : 1 échantillon (créneau 0) ----------
        ptype = 2'd2; present = 4'b0001; frame0 = 4'b0001;
        l0 = 16'hABCD; r0 = 16'h1234; #1;
        check(header[7:0]   === 8'h02,    "ASP HB0 = 0x02");
        check(header[11:8]  === 4'b0001,  "ASP sample_present = 0001");
        check(header[15:12] === 4'b0000,  "ASP layout = 0 (2ch)");
        check(header[19:16] === 4'b0000,  "ASP sample_flat = 0");
        check(header[23:20] === 4'b0001,  "ASP B field (frame0 & present)");
        check(sub0[23:0]  === l24_0,      "ASP0 gauche cadre MSB");
        check(sub0[47:24] === r24_0,      "ASP0 droit cadre MSB");
        check(sub0[50:48] === 3'b000,     "ASP0 C_L/U_L/V_L = 0");
        check(sub0[51] === (^l24_0),      "ASP0 P_L parite gauche");
        check(sub0[55] === (^r24_0),      "ASP0 P_R parite droite");
        check(sub1 === 56'd0 && sub2 === 56'd0 && sub3 === 56'd0,
              "ASP creneaux 1-3 vides");

        // ---------- Audio Sample : 2 échantillons (créneaux 0,1) ----------
        present = 4'b0011; frame0 = 4'b0000;
        l1 = 16'h5678; r1 = 16'h9ABC; #1;
        check(header[11:8]  === 4'b0011,  "ASP sample_present = 0011");
        check(header[23:20] === 4'b0000,  "ASP B field = 0 (hors debut bloc)");
        check(sub0[23:0]  === l24_0,      "ASP0 gauche");
        check(sub1[23:0]  === l24_1,      "ASP1 gauche");
        check(sub1[47:24] === r24_1,      "ASP1 droit");
        check(sub1[51] === (^l24_1),      "ASP1 P_L");
        check(sub2 === 56'd0 && sub3 === 56'd0, "ASP creneaux 2-3 vides");

        if (errors == 0)
            $display("ALL TESTS PASSED (tb_hdmi_audio)");
        else
            $display("%0d ERREUR(S)", errors);
        $finish;
    end

endmodule
