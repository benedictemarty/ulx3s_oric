# Modem Hayes WiFi pour l'ESP32 interne de l'ULX3S (MicroPython 1.14).
# Tourne sur l'UART0 (= pont FPGA wifi_rxd/txd = 6551 de l'Oric, 115200).
# Installé via le REPL (tools/esp32/install_main.py) — PAS de flash esptool.
#
# Jeu de commandes : sous-ensemble COMPATIBLE PicoWiFiModemUSB (~/picowifi,
# lignée mecparts/RetroWiFiModem) pour que l'Oric parle la même langue au
# modem interne et au Pico W de la LOCI :
#   AT            OK
#   AT?           aide
#   ATI           état (SSID, IP, RSSI)
#   ATE0/ATE1/ATE?  écho commande
#   AT$SSID=nom   / AT$SSID?     réseau WiFi
#   AT$PASS=mdp   / AT$PASS?     mot de passe (affiché masqué)
#   ATC1 / ATC0 / ATC?           connexion WiFi on/off/état
#   AT&W          sauve SSID/PASS (wifi.txt, rejoint au boot)
#   AT&F          efface la config
#   ATDT host[:port]             appel TCP (port 23 défaut) -> CONNECT
#   +++ (garde 1 s)              retour mode commande
#   ATO           retour en ligne     ATH  raccroche -> NO CARRIER
#   ATGET http://hote[/page]     GET simple, affiche la page, raccroche
#   ATZ           reset du modem (machine.reset)
# Ctrl-C au REPL : interrompt le modem et rend la main à MicroPython.

import sys
import time
import select
import socket
import network
import machine

VERSION = "ULX3S-ORIC ESP32 MODEM 0.2 (MicroPython, cmds PicoWiFiModem)"

wlan = network.WLAN(network.STA_IF)
wlan.active(True)

poller = select.poll()
poller.register(sys.stdin, select.POLLIN)
net_poll = select.poll()          # surveille la socket réseau (lisible ?)

echo = True
sock = None
online = False
ssid = ""
password = ""

# Telnet : on répond aux négociations IAC (refus de toutes les options) et on
# les retire de l'affichage -> terminal propre. ATNET0 = mode brut (IAC passés
# tels quels, ex. transfert XMODEM binaire). État persistant entre les recv.
tn_on = True
_tn_st = 0            # 0 normal, 1 IAC, 2 option, 3 SB, 4 SB+IAC
_tn_cmd = 0


def telnet_reset():
    global _tn_st, _tn_cmd
    _tn_st = 0
    _tn_cmd = 0


def telnet_filter(data):
    global _tn_st, _tn_cmd
    if not tn_on:
        return data
    out = bytearray()
    resp = bytearray()
    for b in data:
        if _tn_st == 0:
            if b == 0xFF:
                _tn_st = 1
            else:
                out.append(b)
        elif _tn_st == 1:
            if b == 0xFF:            # IAC IAC = 0xFF littéral
                out.append(0xFF); _tn_st = 0
            elif 0xFB <= b <= 0xFE:  # WILL/WONT/DO/DONT
                _tn_cmd = b; _tn_st = 2
            elif b == 0xFA:          # SB
                _tn_st = 3
            else:
                _tn_st = 0
        elif _tn_st == 2:            # octet d'option -> refuser
            if _tn_cmd == 0xFD:      # DO x   -> WONT x
                resp += bytes((0xFF, 0xFC, b))
            elif _tn_cmd == 0xFB:    # WILL x -> DONT x
                resp += bytes((0xFF, 0xFE, b))
            _tn_st = 0
        elif _tn_st == 3:            # sous-négociation
            if b == 0xFF:
                _tn_st = 4
        elif _tn_st == 4:
            _tn_st = 0 if b == 0xF0 else 3   # IAC SE = fin
    if resp and sock:
        try:
            sock.send(resp)
        except Exception:
            pass
    return bytes(out)


# Sortie octets BRUTS : MicroPython ne supporte que le codec UTF-8, donc
# data.decode("latin-1") LÈVE UnicodeError sur un octet >=0x80 (ex. telnet
# IAC 0xFF). On écrit les octets directement via sys.stdout.buffer.
_rawout = getattr(sys.stdout, "buffer", None)
def wbytes(data):
    if _rawout:
        _rawout.write(data)
    else:
        for b in data:
            sys.stdout.write(chr(b) if b < 0x80 else "?")


def crlf(s=""):
    sys.stdout.write(s + "\r\n")


def load_cfg():
    global ssid, password
    try:
        f = open("wifi.txt")
        ssid = f.readline().strip()
        password = f.readline().strip()
        f.close()
    except OSError:
        pass


def save_cfg():
    f = open("wifi.txt", "w")
    f.write(ssid + "\n" + password + "\n")
    f.close()


def wifi_connect():
    if not ssid:
        return False
    if wlan.isconnected():
        return True
    wlan.connect(ssid, password)
    for _ in range(120):            # ~12 s
        if wlan.isconnected():
            return True
        time.sleep_ms(100)
    return False


def hangup(report=True):
    global sock, online
    if sock:
        try:
            net_poll.unregister(sock)
        except Exception:
            pass
        try:
            sock.close()
        except Exception:
            pass
    sock = None
    online = False
    if report:
        crlf("NO CARRIER")


def dial(arg):
    global sock, online
    host = arg.strip()
    port = 23
    if ":" in host:
        host, p = host.rsplit(":", 1)
        try:
            port = int(p)
        except ValueError:
            crlf("ERROR")
            return
    if not wifi_connect():
        crlf("NO CARRIER")
        return
    try:
        s = socket.socket()
        s.connect(socket.getaddrinfo(host, port)[0][-1])
        s.setblocking(False)
        net_poll.register(s, select.POLLIN)
        sock = s
        online = True
        telnet_reset()
        crlf("CONNECT")
    except Exception:
        crlf("NO CARRIER")


def atget(url):
    if not wifi_connect():
        crlf("NO CARRIER")
        return
    try:
        proto, rest = url.split("://", 1)
        host = rest.split("/", 1)[0]
        path = "/" + rest.split("/", 1)[1] if "/" in rest else "/"
        port = 443 if proto == "https" else 80
        if ":" in host:
            host, p = host.rsplit(":", 1)
            port = int(p)
        s = socket.socket()
        s.connect(socket.getaddrinfo(host, port)[0][-1])
        if proto == "https":
            import ussl
            s = ussl.wrap_socket(s, server_hostname=host)
        req = ("GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n"
               % (path, host))
        s.write(req.encode()) if proto == "https" else s.send(req.encode())
        while True:
            data = s.read(256) if proto == "https" else s.recv(256)
            if not data:
                break
            wbytes(data)
        s.close()
        crlf()
        crlf("OK")
    except Exception as e:
        crlf("ERROR " + repr(e))


def atdiskrd(url):
    # Protocole loci-webdisk (cf. ~/loci-webdisk, at_basic.h httpDiskRead) :
    # renvoie UNIQUEMENT le corps HTTP, cadré "\r\n+DISK:<len>\r\n" + octets
    # bruts + "OK". Le range est dans la query (?offset=&len=), pas d'en-tête
    # Range. Piloté par firmware (FPGA/LOCI), pas tapé à la main.
    if not wifi_connect():
        crlf("ERROR")
        return
    try:
        proto, rest = url.split("://", 1)
        host = rest.split("/", 1)[0]
        path = "/" + rest.split("/", 1)[1] if "/" in rest else "/"
        port = 443 if proto == "https" else 80
        if ":" in host:
            host, p = host.rsplit(":", 1)
            port = int(p)
        s = socket.socket()
        s.connect(socket.getaddrinfo(host, port)[0][-1])
        if proto == "https":
            import ussl
            s = ussl.wrap_socket(s, server_hostname=host)
            rd = s.read
            wr = s.write
        else:
            rd = lambda n: s.recv(n)
            wr = lambda d: s.send(d)
        wr(("GET %s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n"
            % (path, host)).encode())
        # statut + en-têtes octet par octet jusqu'à la ligne vide
        line = b""
        status = 0
        clen = -1
        nl = 0
        while True:
            c = rd(1)
            if not c:
                break
            if c == b"\n":
                t = line.strip()
                if status == 0 and t[:5] == b"HTTP/":
                    status = int(t.split(b" ")[1])
                elif t.lower().startswith(b"content-length:"):
                    clen = int(t.split(b":")[1])
                if t == b"":
                    nl = 1
                line = b""
                if nl:
                    break
            else:
                line += c
        if status != 200 or clen < 0:
            s.close()
            crlf("ERROR")
            return
        # sortie BINAIRE : sys.stdout.buffer si présent (sinon latin-1 —
        # dégradé, les octets >127 partiraient en UTF-8)
        out = getattr(sys.stdout, "buffer", None)
        sys.stdout.write("\r\n+DISK:%d\r\n" % clen)
        left = clen
        while left > 0:
            data = rd(min(256, left))
            if not data:
                break
            if out:
                out.write(data)
            else:
                sys.stdout.write(data.decode("latin-1"))
            left -= len(data)
        s.close()
        crlf("OK" if left == 0 else "ERROR")
    except Exception:
        crlf("ERROR")


HELP = (
    "AT ATI AT? ATE0/1 AT$SSID= AT$PASS= ATC0/1/? AT&W AT&F",
    "ATDT host[:port]  +++  ATO  ATH  ATGET http://...  ATZ",
    "AT$SCAN  ATDISKRD http(s)://... (+DISK:<len> framing)",
)


def do_cmd(line):
    global echo, online, ssid, password, tn_on
    u = line.upper()
    if u == "AT":
        crlf("OK")
    elif u == "AT?":
        for h in HELP:
            crlf(h)
        crlf("OK")
    elif u == "ATI":
        crlf(VERSION)
        if wlan.isconnected():
            # wlan.config("ssid") lève ValueError sur MicroPython 1.14 en STA :
            # on affiche le SSID mémorisé et on garde le RSSI optionnel.
            crlf("WIFI CONNECTED " + ssid)
            try:
                rssi = str(wlan.status("rssi"))
            except Exception:
                rssi = "?"
            crlf("IP " + wlan.ifconfig()[0] + " RSSI " + rssi)
        else:
            crlf("WIFI NOT CONNECTED"
                 + (" (SSID " + ssid + ")" if ssid else ""))
        crlf("OK")
    elif u in ("ATE0", "ATE1", "ATE?"):
        if u == "ATE?":
            crlf("1" if echo else "0")
        else:
            echo = (u == "ATE1")
        crlf("OK")
    elif u.startswith("AT$SSID="):
        ssid = line[8:]
        crlf("OK")
    elif u == "AT$SSID?":
        crlf(ssid)
        crlf("OK")
    elif u.startswith("AT$PASS="):
        password = line[8:]
        crlf("OK")
    elif u == "AT$PASS?":
        crlf("*" * len(password))
        crlf("OK")
    elif u == "AT$SCAN":
        # format wificonf.bas : "<n> <ssid><TAB><O|S>" par ligne puis OK
        try:
            nets = wlan.scan()
            for i, n in enumerate(nets):
                nom = n[0].decode("utf-8", "replace")
                sec = "O" if n[4] == 0 else "S"
                crlf("%d %s\t%s" % (i, nom, sec))
            crlf("OK")
        except Exception:
            crlf("ERROR")
    elif u == "ATC?":
        crlf("1" if wlan.isconnected() else "0")
        crlf("OK")
    elif u == "ATC1":
        crlf("OK" if wifi_connect() else "ERROR")
    elif u == "ATC0":
        wlan.disconnect()
        crlf("OK")
    elif u == "AT&W":
        save_cfg()
        crlf("OK")
    elif u == "AT&F":
        try:
            import os
            os.remove("wifi.txt")
        except OSError:
            pass
        ssid = ""
        password = ""
        crlf("OK")
    elif u.startswith("ATDISKRD"):
        atdiskrd(line[8:].strip())
    elif u.startswith("ATDT") or u.startswith("ATDP"):
        dial(line[4:])
    elif u.startswith("ATD"):
        dial(line[3:])
    elif u == "ATO":
        if sock:
            online = True
        else:
            crlf("NO CARRIER")
    elif u == "ATH":
        hangup()
    elif u.startswith("ATNET"):
        if u == "ATNET?":
            crlf("1" if tn_on else "0")
        elif u == "ATNET0":
            tn_on = False
        else:                         # ATNET1/ATNET2 -> traitement telnet ON
            tn_on = True
        crlf("OK")
    elif u.startswith("ATGET"):
        atget(line[5:].strip())
    elif u == "ATZ":
        crlf("OK")
        time.sleep_ms(100)
        machine.reset()
    elif u == "":
        pass
    else:
        crlf("ERROR")


def run():
    global online
    load_cfg()
    if ssid:
        wifi_connect()
    crlf()
    crlf(VERSION + " READY")
    buf = ""
    plus = 0
    last_rx = time.ticks_ms()
    while True:
        if poller.poll(0):
            ch = sys.stdin.read(1)
            if online:
                if ch == "+" and (plus > 0 or
                        time.ticks_diff(time.ticks_ms(), last_rx) > 1000):
                    plus += 1
                    if plus == 3:
                        online = False
                        plus = 0
                        crlf()
                        crlf("OK")
                else:
                    try:
                        if plus:
                            sock.send(b"+" * plus)
                        plus = 0
                        sock.send(ch.encode("latin-1"))
                    except Exception:
                        hangup()
                last_rx = time.ticks_ms()
            else:
                if echo:
                    sys.stdout.write(ch)
                if ch in ("\r", "\n"):
                    if echo and ch == "\r":
                        sys.stdout.write("\n")
                    do_cmd(buf.strip())
                    buf = ""
                elif ch in ("\x08", "\x7f"):
                    buf = buf[:-1]
                else:
                    buf += ch
        # Ne lire QUE si la socket est réellement lisible (POLLIN) : sinon un
        # recv() non-bloquant renvoie b"" « pas de données » sur MicroPython,
        # à tort pris pour une fermeture -> NO CARRIER juste après CONNECT.
        if sock and online and net_poll.poll(0):
            try:
                data = sock.recv(256)
                if not data:                 # POLLIN + vide = vraie fermeture
                    hangup()
                else:
                    wbytes(telnet_filter(data))
            except OSError:
                pass                # EAGAIN transitoire
            except Exception:
                hangup()
        time.sleep_ms(2)


while True:
    try:
        run()
    except KeyboardInterrupt:
        raise                    # Ctrl-C : rendre la main au REPL
    except Exception as e:
        crlf("ERROR " + repr(e))
        time.sleep_ms(200)
