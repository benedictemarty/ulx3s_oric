// rPLL Gowin : 27 MHz -> 135 MHz (5x, sérialisation TMDS).
// fCLKOUT = fCLKIN x (FBDIV+1)/(IDIV+1) = 27 x 5/1 = 135 MHz
// fVCO = fCLKOUT x ODIV = 135 x 8 = 1080 MHz (plage 400-1200 OK... 8 trop ?
// ODIV_SEL=4 -> VCO 540 MHz, dans la plage recommandée).

module gowin_rpll (
    input  clkin,      // 27 MHz
    output clkout,     // 135 MHz
    output locked
);

`ifndef SIM
    rPLL #(
        .FCLKIN("27"),
        .IDIV_SEL(0),
        .FBDIV_SEL(4),
        .ODIV_SEL(4),
        .DYN_IDIV_SEL("false"),
        .DYN_FBDIV_SEL("false"),
        .DYN_ODIV_SEL("false"),
        .PSDA_SEL("0000"),
        .DYN_DA_EN("false"),
        .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1),
        .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"),
        .CLKOUT_BYPASS("false"),
        .CLKOUTP_BYPASS("false"),
        .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2),
        .CLKOUTD_SRC("CLKOUT"),
        .CLKOUTD3_SRC("CLKOUT"),
        .DEVICE("GW2AR-18C")
    ) pll (
        .CLKOUT(clkout),
        .LOCK(locked),
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(1'b0),
        .RESET_P(1'b0),
        .CLKIN(clkin),
        .CLKFB(1'b0),
        .FBDSEL(6'b0),
        .IDSEL(6'b0),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0)
    );
`else
    // Modèle de simulation grossier : x5 par multiplication d'horloge externe
    assign clkout = 1'b0;
    assign locked = 1'b1;
`endif

endmodule
