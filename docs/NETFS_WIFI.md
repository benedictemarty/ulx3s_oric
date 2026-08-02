# Navigateur de fichiers WiFi (tap/dsk) — plan

Objectif : depuis l'Oric, **parcourir une arborescence de `.tap` et `.dsk`
servie par un serveur HTTP** via le WiFi, et **charger** le fichier choisi.
Navigation par **OSD incrusté par le FPGA**.

Décisions (bmarty, 2026-08-02) :
- **`.tap` d'abord** (réutilise l'injecteur cassette) ; **`.dsk` = épopée
  séparée ultérieure** (contrôleur Microdisc WD1793, cf. plus bas).
- **OSD incrusté par le FPGA** (superposition dans le chemin vidéo `hdmi_out`).
- **Serveur HTTP standard + listing JSON** (portable, n'importe quel hôte).

Dépendance : partage le **lien ESP32↔FPGA** de l'épopée modem
(`docs/MODEM_WIFI.md`) — le firmware WiFi et le pont UART sont mutualisés.

## Architecture

```
Serveur HTTP (arbre de tap/dsk, listing JSON)
      │  WiFi
      ▼
   ESP32   (client HTTP : GET listing JSON d'un dossier ; GET d'un fichier)
      │  UART wifi_rxd/txd (K3/K4) — protocole à trames ESP32<->FPGA
      ▼
   FPGA
     ├─ OSD : incruste l'arbre dans hdmi_out (texte + curseur), navigation
     │        flèches (btn[3..6]) / joystick ; met en évidence dir/tap/dsk
     ├─ reçoit les listings (affichage) et émet CD / UP / LOAD
     └─ .tap sélectionné -> injecteur cassette (source = ESP32 au lieu du PC)
      ▼
    Oric  (charge le .tap comme une cassette : CLOAD)
```

## Phases (épopée US-NETFS)

### US-NETFS.1 — Protocole ESP32↔FPGA & client HTTP
- **Protocole série à trames** (multiplexé avec le modem sur le même UART —
  prévoir des canaux/en-têtes) :
  - FPGA→ESP32 : `CD <index>`, `UP`, `LOAD <index>`, `REFRESH`.
  - ESP32→FPGA : `DIR <chemin>`, puis N × `ENTRY {type: dir|tap|dsk, nom,
    taille}`, `END`. Puis, sur LOAD d'un `.tap`, le flux de l'injecteur
    cassette (crédits déjà en place).
- **Firmware ESP32** : `GET <base>/<chemin>` → listing **JSON** attendu, p.ex.
  ```json
  { "path": "/games",
    "entries": [ {"name":"..","type":"dir"},
                 {"name":"arcade","type":"dir"},
                 {"name":"zorgon.tap","type":"tap","size":18432} ] }
  ```
  parse → trames ENTRY vers le FPGA. Sur LOAD : `GET` du fichier, stream vers
  la cassette. WiFi + base URL configurés par AT/build.

### US-NETFS.2 — OSD incrusté (FPGA)
- **Couche vidéo** dans `rtl/hdmi_out.v` : selon (scan_x, scan_y), superposer
  une grille de caractères (police 8×8 en ROM) et un curseur au RGB issu du
  framebuffer. N lignes visibles, défilement.
- **Mémoire OSD** : tampon des entrées de la page courante (nom + type),
  écrit par le récepteur de trames, lu par le rendu.
- **Navigation** : flèches ULX3S (`btn[3..6]` déjà mappées) + FIRE (`btn[2]`)
  pour entrer/charger ; un bouton pour ouvrir/fermer l'OSD. (Joystick USB =
  US3.3, optionnel.)
- **Contrainte** : incrustation purement combinatoire en domaine `clk_pixel`,
  ne touche pas au timing vidéo verrouillé. Testbench de rendu (fenêtre,
  curseur, mapping caractère→pixel).

### US-NETFS.3 — Chargement .tap via WiFi (bout-en-bout)
- Router le flux du fichier sélectionné **ESP32 → injecteur cassette**
  (réutilise `tape_injector` + contrôle de flux crédits ; la source bascule
  de l'UART PC vers l'UART ESP32).
- Séquence : OSD LOAD → l'Oric fait `CLOAD""` (ou déclenchement auto) →
  l'ESP32 stream le `.tap` → l'Oric charge. Validation sur carte.

## Épopée séparée US-DISK — support `.dsk` (plus tard)
- Émulation du **contrôleur Microdisc (FDC WD1793)** + **ROM de boot**, fidèle
  à `~/Oric1/src/io/microdisc.c` : registres FDC, mapping I/O, /ROMDIS.
- **Secteurs** servis depuis l'ESP32/WiFi : streaming à la demande (latence à
  maîtriser) ou bufferisation d'une piste/du disque (stockage — SDRAM ULX3S
  ou BRAM). Gros morceau RTL + protocole secteur.
- Puis intégration à l'OSD (le `.dsk` sélectionné « insère » la disquette).

## Points ouverts
- **Multiplexage du lien ESP32** : modem 6551 (US-MODEM) + contrôle OSD +
  stream cassette → concevoir un protocole à canaux propre et unique.
- **Format JSON** exact et pagination des gros dossiers.
- **Ouverture/fermeture de l'OSD** et cohabitation avec l'affichage Oric.
- **Latence WiFi** pour le `.dsk` (lecture secteur temps réel).
- Réutiliser la navigation flèches déjà câblée ; éviter le conflit avec la
  bascule AZERTY sur `btn[6]`.

## Suivi
Épopée **US-NETFS** au backlog (phases 1→3) + **US-DISK** (dsk). Chaque phase :
RTL/firmware + tests + doc + CHANGELOG, non-régression maintenue.
