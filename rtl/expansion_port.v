// Port d'extension Oric sur GPIO ULX3S — reconstitution du connecteur
// d'extension 34 points (bus 6502 complet, annexe 11 du manuel Atmos) pour
// brancher une vraie cartouche (LOCI, Microdisc…) via des adaptateurs de
// niveau 3,3 V <-> 5 V. Voir docs/PORT_EXTENSION.md.
//
// Cadencé sur le découpage tphase du cycle 1 MHz (cf. oric_atmos.v) :
//   phases 0..11  : adresse/RW stables, PHI2 bas
//   phases 12..24 : PHI2 haut, données d'écriture pilotées
//   phase 22      : échantillonnage des données lues (cartouche -> CPU)
// À 1 MHz, les marges sont énormes pour un câblage Dupont + TXS0108E.

module expansion_port (
    input         clk,
    input         rst,            // reset du système (piloté vers la cartouche)
    input  [4:0]  tphase,

    // Bus interne (snapshot stable sur tout le cycle 1 MHz)
    input  [15:0] bus_addr,
    input         bus_we,
    input  [7:0]  bus_do,
    input         sel_io_page,    // page $03xx

    // Vers le cœur
    output reg [7:0] ext_din,     // donnée lue (valide dès la phase 23)
    output           ext_irq,     // actif haut, synchronisé
    output           ext_romdis,  // actif haut, synchronisé
    output           ext_map,     // actif haut, synchronisé
    output           ext_ioctl,   // actif haut : inhibe la VIA interne
    output           ext_rst_req, // la cartouche tire /RESET (bouton LOCI)

    // Broches physiques (à travers les TXS0108E)
    output [15:0] pin_a,
    inout  [7:0]  pin_d,
    output        pin_rw,
    output        pin_phi2,
    output        pin_io_n,
    inout         pin_rst_n,      // drain ouvert, pull-up
    input         pin_irq_n,
    input         pin_romdis_n,
    input         pin_map_n,
    input         pin_ioctl_n
);

    wire phi2 = (tphase >= 5'd12);

    assign pin_a    = bus_addr;
    assign pin_rw   = ~bus_we;
    assign pin_phi2 = phi2;
    assign pin_io_n = ~sel_io_page;

    // /RESET : drain ouvert — le FPGA le tire bas pendant son propre reset,
    // la cartouche peut aussi le tirer (bouton reset LOCI)
    assign pin_rst_n = rst ? 1'b0 : 1'bz;

    // Données : pilotées seulement pendant une écriture CPU, PHI2 haut
    assign pin_d = (bus_we && phi2) ? bus_do : 8'bz;

    // Échantillonnage lecture en fin de PHI2 haut
    always @(posedge clk)
        if (tphase == 5'd22)
            ext_din <= pin_d;

    // Entrées asynchrones de la cartouche : double bascule
    reg [1:0] irq_s, romdis_s, map_s, ioctl_s, rstin_s;
    always @(posedge clk) begin
        irq_s    <= {irq_s[0],    ~pin_irq_n};
        romdis_s <= {romdis_s[0], ~pin_romdis_n};
        map_s    <= {map_s[0],    ~pin_map_n};
        ioctl_s  <= {ioctl_s[0],  ~pin_ioctl_n};
        rstin_s  <= {rstin_s[0],  ~pin_rst_n & ~rst};
    end
    assign ext_irq     = irq_s[1];
    assign ext_romdis  = romdis_s[1];
    assign ext_map     = map_s[1];
    assign ext_ioctl   = ioctl_s[1];
    assign ext_rst_req = rstin_s[1];

endmodule
