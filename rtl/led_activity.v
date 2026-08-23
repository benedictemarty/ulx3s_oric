// ---------------------------------------------------------------------------
// led_activity — monostable re-déclenchable (« LED d'activité »)
//
// À chaque impulsion/niveau haut sur `trig`, un compteur est rechargé à sa
// valeur max ; tant qu'il est non nul, `active` reste haut puis décrémente à
// chaque coup d'horloge. Résultat : la LED s'allume dès qu'un événement se
// produit et s'éteint ~2^WIDTH cycles après le DERNIER événement.
//
//   - Événement fréquent (IRQ ~100 Hz, VSYNC 50 Hz) => LED allumée en continu
//     = « le cœur vit » ; se fige/éteint si le signal s'arrête.
//   - Événement rare (rapport HID par frappe)        => flash visible.
//
// WIDTH règle la durée de rémanence : à 25 MHz, WIDTH=22 -> ~168 ms.
// ---------------------------------------------------------------------------
module led_activity #(
    parameter WIDTH = 22
) (
    input  wire clk,
    input  wire rst,
    input  wire trig,     // impulsion ou niveau haut = activité
    output wire active    // niveau haut visible pour la LED
);
    reg [WIDTH-1:0] cnt;

    always @(posedge clk) begin
        if (rst)            cnt <= {WIDTH{1'b0}};
        else if (trig)      cnt <= {WIDTH{1'b1}};   // recharge (retriggerable)
        else if (cnt != 0)  cnt <= cnt - 1'b1;      // décroissance
    end

    assign active = (cnt != 0);
endmodule
