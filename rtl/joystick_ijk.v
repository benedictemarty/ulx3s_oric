// Interface joystick IJK (la plus courante sur Oric) — portage RTL de
// `oric_joystick_port_a_pins()` de la référence ~/Oric1/src/io/joystick.c.
//
// L'IJK vit sur le port imprimante = **VIA Port A**. L'adaptateur tire des
// lignes de Port A vers le BAS (actif bas) selon l'état du stick, quand il est
// activé et sélectionné :
//   - Activation : PB4 (strobe imprimante) piloté en SORTIE et à l'état BAS.
//     Comme `pb_out = orb | ~ddrb`, cette condition ⟺ `pb_out[4] == 0`.
//   - Sélection du stick : bits 6-7 de la valeur pilotée sur Port A
//     (`joysel = ora | ~ddra` = `pa_out` du VIA). bit6=1 → stick A ;
//     bits 6 ET 7 = 1 → aucun ; sinon (bit6=0) → présence seule (stick B non câblé).
//   - État sur bits 0-4 (actif bas) : 0=RIGHT,1=LEFT,2=FIRE,3=DOWN,4=UP.
//   - Présence sur bit 5 (0 = interface présente).
//
// Sortie `pins` = contribution de l'IJK aux pins de Port A, à **combiner par ET**
// avec l'entrée normale de Port A (les pull-downs sont à collecteur ouvert).
// Vaut 0xFF (aucun effet) quand l'interface est inactive ou aucun gamepad.

module joystick_ijk (
    input             up,       // directions actives HAUTES (appuyé = 1)
    input             down,
    input             left,
    input             right,
    input             fire,
    input             present,  // 1 = un gamepad est connecté
    input      [7:0]  pa_out,   // joysel = ora | ~ddra (sortie pilotée sur Port A)
    input             pb4_low,  // = ~pb_out[4] : PB4 piloté bas (interface activée)
    output     [7:0]  pins      // pull-downs Port A (ET dans pa_in) ; 0xFF = neutre
);
    localparam [7:0] PRESENCE = 8'h20;   // bit 5

    // Masque des boutons, actif bas (bit à 0 = appuyé) — bits 0..4.
    wire [7:0] mask = ~{3'b000, up, down, fire, left, right};

    wire [7:0] presence_only = ~PRESENCE;              // 0xDF (bit5=0)

    // Superposition selon la sélection de stick (comme la référence).
    wire [7:0] ijk_out = (pa_out[7:6] == 2'b11) ? presence_only          // aucun
                       : (pa_out[6])            ? (presence_only & mask)  // stick A
                       :                          presence_only;         // présence seule

    assign pins = (pb4_low && present) ? ijk_out : 8'hFF;

endmodule
