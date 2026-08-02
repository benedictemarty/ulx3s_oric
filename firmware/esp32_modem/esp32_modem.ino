/*
 * esp32_modem — modem WiFi « Hayes » pour l'Oric sur ULX3S (US-MODEM phase 2).
 *
 * Ponte l'UART venant du 6551 ACIA du FPGA ($031C-$031F) vers une connexion
 * TCP/telnet en WiFi. L'Oric parle au 6551 comme à un modem RS-232 ; ce
 * firmware interprète les commandes AT et ouvre les connexions.
 *
 * Liaison FPGA <-> ESP32 (cf. top_ulx3s.v / LPF ULX3S) :
 *   FPGA wifi_rxd (K3)  --->  ESP32 RX   (le FPGA émet, l'ESP32 reçoit)
 *   FPGA wifi_txd (K4)  <---  ESP32 TX   (l'ESP32 émet, le FPGA reçoit)
 *   FPGA wifi_en        --->  ESP32 EN   (maintenu haut par le FPGA)
 * ⚠️ Vérifier le mappage GPIO exact de l'UART côté ESP32 sur le schéma ULX3S
 *    (voir README). Par défaut on utilise UART0 (Serial, GPIO1/3), qui est la
 *    liaison standard ESP32<->FPGA de l'ULX3S. Si conflit console, basculer
 *    sur un UART secondaire (voir LINK ci-dessous).
 *
 * SCAFFOLD : à compiler et flasher par bmarty (voir README). Non compilé/testé
 * dans ce dépôt (pas de toolchain ESP32 ici).
 */

#include <WiFi.h>
#include <Preferences.h>

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
static const uint32_t LINK_BAUD = 115200;   // doit matcher uart_tx/uart_rx du FPGA

// UART vers le FPGA. Par défaut UART0 (Serial). Pour un UART dédié, remplacer
// par :  HardwareSerial Link(2); ... Link.begin(LINK_BAUD, SERIAL_8N1, RXPIN, TXPIN);
HardwareSerial& Link = Serial;

static const uint16_t DEF_PORT = 23;        // telnet par défaut
Preferences prefs;

// ---------------------------------------------------------------------------
// État
// ---------------------------------------------------------------------------
WiFiClient client;
bool   online   = false;      // true = mode « en ligne » (données transparentes)
bool   echoOn   = true;       // ATE1/ATE0
bool   verbose  = true;       // ATV1 : réponses texte ; ATV0 : codes numériques
bool   telnetStrip = true;    // filtre les négociations IAC (telnet)
String cmdLine;

// Détection de la séquence d'échappement +++ (garde ~1 s)
uint8_t  plusCount = 0;
uint32_t lastPlus  = 0;
uint32_t lastLinkActivity = 0;

// ---------------------------------------------------------------------------
// Réponses (style Hayes)
// ---------------------------------------------------------------------------
void resp(const char* verboseMsg, int code) {
    Link.print("\r\n");
    if (verbose) { Link.print(verboseMsg); Link.print("\r\n"); }
    else         { Link.print(code);       Link.print("\r"); }
}
void respOK()        { resp("OK", 0); }
void respERROR()     { resp("ERROR", 4); }
void respCONNECT()   { resp("CONNECT", 1); }
void respNOCARRIER() { resp("NO CARRIER", 3); }

// ---------------------------------------------------------------------------
// WiFi
// ---------------------------------------------------------------------------
bool wifiConnect(uint32_t timeoutMs = 15000) {
    String ssid = prefs.getString("ssid", "");
    String pass = prefs.getString("pass", "");
    if (ssid.isEmpty()) return false;
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid.c_str(), pass.c_str());
    uint32_t t0 = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - t0 < timeoutMs) delay(100);
    return WiFi.status() == WL_CONNECTED;
}

// ---------------------------------------------------------------------------
// Numérotation : ATDT host[:port]
// ---------------------------------------------------------------------------
void dial(String target) {
    target.trim();
    if (target.isEmpty()) { respERROR(); return; }
    if (WiFi.status() != WL_CONNECTED && !wifiConnect()) { respNOCARRIER(); return; }

    uint16_t port = DEF_PORT;
    int colon = target.lastIndexOf(':');
    String host = target;
    if (colon > 0) { host = target.substring(0, colon); port = target.substring(colon + 1).toInt(); }

    if (client.connect(host.c_str(), port)) {
        online = true;
        respCONNECT();          // porteuse en bande ; DCD matériel = TODO (voir README)
    } else {
        respNOCARRIER();
    }
}

void hangup() {
    if (client.connected()) client.stop();
    online = false;
    respNOCARRIER();
}

// ---------------------------------------------------------------------------
// Analyse d'une commande AT
// ---------------------------------------------------------------------------
void handleAT(String line) {
    line.trim();
    if (line.length() < 2 || line.substring(0, 2) != "AT") {
        if (line.isEmpty()) return;   // ligne vide : rien
        respERROR(); return;
    }
    String rest = line.substring(2);
    rest.toUpperCase();

    // Bare "AT"
    if (rest.isEmpty()) { respOK(); return; }

    // Commandes multiples simples
    if (rest.startsWith("DT") || rest.startsWith("D")) {   // ATDT / ATD
        int idx = rest.startsWith("DT") ? 2 : 1;
        // On récupère la cible depuis la ligne ORIGINALE (casse préservée)
        dial(line.substring(2 + idx));
        return;
    }
    if (rest == "H" || rest == "H0")            { hangup(); return; }
    if (rest == "O" || rest == "O0")            { if (client.connected()) { online = true; respCONNECT(); } else respNOCARRIER(); return; }
    if (rest == "E0") { echoOn = false; respOK(); return; }
    if (rest == "E1") { echoOn = true;  respOK(); return; }
    if (rest == "V0") { verbose = false; respOK(); return; }
    if (rest == "V1") { verbose = true;  respOK(); return; }
    if (rest == "Z"  || rest == "Z0")           { hangup(); respOK(); return; }  // reset léger
    if (rest.startsWith("I"))                   { Link.print("\r\nESP32 WiFi Modem (Oric ULX3S)\r\n"); respOK(); return; }

    // Config WiFi (custom) : AT$SSID=..., AT$PASS=..., AT$C (connect), AT$W (état)
    if (rest.startsWith("$SSID=")) { prefs.putString("ssid", line.substring(2 + 6)); respOK(); return; }
    if (rest.startsWith("$PASS=")) { prefs.putString("pass", line.substring(2 + 6)); respOK(); return; }
    if (rest == "$C")   { bool ok = wifiConnect(); resp(ok ? "WIFI OK" : "WIFI FAIL", ok ? 0 : 4); return; }
    if (rest == "$W")   {
        Link.print("\r\nSSID: "); Link.print(prefs.getString("ssid", "(vide)"));
        Link.print("\r\nIP:   "); Link.print(WiFi.localIP());
        Link.print("\r\n"); respOK(); return;
    }

    respERROR();
}

// ---------------------------------------------------------------------------
// Mode « en ligne » : pont transparent série <-> TCP
// ---------------------------------------------------------------------------
void pumpOnline() {
    // TCP -> FPGA (avec filtrage telnet IAC optionnel)
    while (client.available()) {
        int b = client.read();
        if (telnetStrip && b == 0xFF) {           // IAC : refuser toute négociation
            int cmd = client.read();
            if (cmd == 0xFF) { Link.write(0xFF); } // IAC IAC = 0xFF littéral
            else {                                  // WILL/WONT/DO/DONT + option
                int opt = client.read();
                (void)opt;                          // on ignore (pas de réponse -> minimal)
            }
            continue;
        }
        Link.write(b);
    }
    // FPGA -> TCP
    while (Link.available()) {
        uint8_t b = Link.read();
        lastLinkActivity = millis();
        // Détection +++ (uniquement en ligne)
        if (b == '+') {
            if (plusCount == 0 && millis() - lastLinkActivity > 900) plusCount = 1;
            else plusCount++;
            lastPlus = millis();
            if (plusCount >= 3) { /* validé après le temps de garde, cf. loop() */ }
        } else {
            plusCount = 0;
        }
        client.write(b);
    }
    if (!client.connected()) { online = false; respNOCARRIER(); }
}

// ---------------------------------------------------------------------------
// Mode commande : accumulation de la ligne AT
// ---------------------------------------------------------------------------
void pumpCommand() {
    while (Link.available()) {
        char c = Link.read();
        if (echoOn) Link.write(c);
        if (c == '\r' || c == '\n') {
            if (cmdLine.length()) { handleAT(cmdLine); cmdLine = ""; }
        } else if (c == 8 || c == 127) {           // backspace
            if (cmdLine.length()) cmdLine.remove(cmdLine.length() - 1);
        } else if (cmdLine.length() < 128) {
            cmdLine += c;
        }
    }
}

// ---------------------------------------------------------------------------
// Setup / loop
// ---------------------------------------------------------------------------
void setup() {
    Link.begin(LINK_BAUD);
    prefs.begin("modem", false);
    delay(200);
    resp("ESP32 WiFi Modem pret", 0);   // bannière au boot
}

void loop() {
    if (online) {
        pumpOnline();
        // Validation de l'échappement +++ après le temps de garde (~1 s sans data)
        if (plusCount >= 3 && millis() - lastPlus > 900) {
            plusCount = 0; online = false; respOK();   // retour en mode commande, connexion maintenue
        }
    } else {
        pumpCommand();
    }
}
