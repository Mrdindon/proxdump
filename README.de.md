# proxdump — verschlüsselte Proxmox-VE-Sicherungen in Cloud-Speicher

[English](README.md) | [Français](README.fr.md) | [Español](README.es.md) | **Deutsch** | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

`proxdump` sichert die virtuellen Maschinen und Container eines
**Proxmox-VE**-Knotens mit `vzdump`, **verschlüsselt** die Archive auf dem
Server und lädt sie zu **Microsoft OneDrive**, **Google Drive**,
**Dropbox**, einem beliebigen **S3-kompatiblen Speicher** (Backblaze B2,
Cloudflare R2, Wasabi, Amazon S3, MinIO…) oder einem **SFTP-Server** hoch.
Alles wird über Menüs im Terminal gesteuert; `rclone` muss man dafür nicht
kennen.

```
 PROXDUMP 1.0.0                                                          pve

   ╭─ Sicherung ──────────────────────────────────────────────────────────╮
   │                                                                      │
   │ Sicherung 1 von 2: qemu 100 (web)                                    │
   │                                                                      │
   │ ⠹ Verschlüsselter Upload von vzdump-qemu-100-….vma.zst nach OneDrive…│
   │   1.5GB / 2.5GB  40MB/s  verbleibend: 24s                            │
   │                                                                      │
   │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  61%  │
   ╰──────────────────────────────────────────────────────── 1m12s ───────╯

 Ctrl-C Abbrechen
```

## Merkmale

- **Verschlüsselt, bevor es den Server verlässt**: Das Ziel erhält nur
  unlesbare Daten (XSalsa20-Poly1305, über `rclone crypt`). Die Dateinamen
  bleiben lesbar und tragen die Endung `.encrypted`.
- **Fünf Arten von Zielen**, auch mehrere zugleich: Das Archiv wird einmal
  erstellt und dann zu jedem gewählten Ziel hochgeladen.
- **Überprüft**: Nach jedem Upload wird die entfernte Kopie per Prüfsumme
  mit dem lokalen Archiv verglichen.
- **Aufbewahrung**: Anzahl der aufbewahrten Versionen, global oder je Gast,
  nach jeder Sicherung angewendet.
- **Wiederherstellung** unter der ursprünglichen ID, unter einer neuen ID,
  oder einfacher Download des entschlüsselten Archivs. Die Archive sind
  gewöhnliche `vzdump`-Archive: Sie lassen sich auch ohne dieses Werkzeug
  wiederherstellen.
- **Zeitplanung**: mehrere Zeitpläne (täglich oder wöchentlich, alle Gäste
  oder eine Auswahl, ein oder mehrere Ziele), die sich auch sofort ausführen
  lassen.
- **Geführte Verbindungen**: schrittweise Autorisierung für OneDrive, Google
  Drive und Dropbox auf einem Server ohne Webbrowser; einfache Formulare für
  S3 und SFTP.
- **Zwei Oberflächen**: eine native mit Farbschemata, Maus und animiertem
  Fortschrittsfenster, oder die klassischen `whiptail`-Dialoge.
- **Sechs Sprachen**: Englisch, Französisch, Spanisch, Deutsch, Chinesisch
  (vereinfacht) und Russisch, für Oberfläche und Protokoll.
- **Schlank**: ein Bash-Skript, `rclone`, `jq` und das, was ein
  Proxmox-VE-Knoten ohnehin mitbringt.

## Funktionsweise

```
 Gast (VM/CT)                  lokaler Zwischenordner               Ziel(e)
┌─────────────┐   vzdump     ┌─────────────────────────┐  rclone  ┌──────────────────────┐
│ 100 web     │ ───────────▶ │ vzdump-qemu-100-….vma.zst│ ──────▶ │ pve-backups/<Knoten>/│
└─────────────┘              │ (Klartext, danach gelöscht)│ crypt │  ….vma.zst.encrypted │
                             └─────────────────────────┘          └──────────────────────┘
```

Für jeden Gast: `vzdump` erstellt das Archiv in einem temporären Ordner,
`rclone` verschlüsselt es und lädt es hoch, die Kopie wird überprüft, die
Aufbewahrung wird angewendet, und der temporäre Ordner wird gelöscht.
`vzdump` entscheidet, was ins Archiv kommt; die Einstellung „Backup“ jedes
Datenträgers in Proxmox VE wird also beachtet.

## Ziele

| Ziel | Verbindung | Gut zu wissen |
|---|---|---|
| Microsoft OneDrive | Autorisierung im Browser, Token auf dem Server eingefügt | 250 GB je Datei |
| Google Drive | Ebenso, mit einem eigenen OAuth-Client (kostenlos) | 750 GB Upload pro Tag |
| Dropbox | Autorisierung im Browser, Token auf dem Server eingefügt | 350 GB je Datei |
| S3-kompatibler Speicher | Zugriffsschlüssel, Geheimnis und Bucket | Backblaze B2, Cloudflare R2, Wasabi, Amazon S3, Hetzner, OVHcloud, Scaleway, MinIO… |
| SFTP-Server | Vom Werkzeug erzeugter SSH-Schlüssel oder Passwort | NAS, anderer Server, gemieteter Speicher |

## Voraussetzungen

- ein Proxmox-VE-Knoten (entwickelt und getestet auf PVE 9 / Debian 13),
  Root-Zugriff;
- mindestens ein Ziel mit genügend Platz;
- ein lokaler Ordner, der das größte Archiv vorübergehend aufnehmen kann;
- für OneDrive, Google Drive und Dropbox: ein Rechner mit Webbrowser und
  [rclone](https://rclone.org/downloads/), einmalig, für die Autorisierung.

## Installation

```bash
git clone https://github.com/Mrdindon/proxdump.git
cd proxdump
./install.sh
```

`install.sh` installiert, was fehlt (`rclone` aus dem offiziellen Paket,
`jq`, `whiptail`, `curl`), und kopiert das Werkzeug nach
`/usr/local/bin/proxdump`. Aktualisieren: `git pull && ./install.sh`.
Entfernen: `./install.sh --uninstall` (die Konfiguration bleibt erhalten).

## Erste Schritte

`proxdump` als root starten, dann unter **Konfiguration**:

1. mindestens ein Ziel verbinden;
2. die Verschlüsselungs-Passphrase festlegen und **außerhalb des Servers
   notieren**: Ohne sie lassen sich die Sicherungen nicht wiederherstellen;
3. den lokalen Zwischenordner und die Sicherungsoptionen prüfen.

Danach **Virtuelle Maschinen und Container sichern** für eine erste
Sicherung und **Automatische Zeitplanung** für die folgenden.

## Kommandozeile

```bash
proxdump                                  # die Menüs
proxdump backup --all                     # alle Gäste, alle Ziele
proxdump backup --to s3,onedrive 100 101  # angegebene Gäste und Ziele
proxdump list                             # gespeicherte Sicherungen
proxdump prune                            # Aufbewahrung anwenden
```

## Dokumentation

Die ausführliche Dokumentation ist auf Englisch:

- [Connecting the destinations](docs/CONNECTIONS.md) — OneDrive, Google
  Drive, Dropbox, S3, SFTP, Lebensdauer der Zugriffstoken;
- [Using proxdump](docs/USAGE.md) — Sprache und Erscheinungsbild,
  Verschlüsselung, Sicherung, Verwaltung, Wiederherstellung, Zeitplanung und
  Kommandozeile;
- [Disaster recovery](docs/RECOVERY.md) — Wiederherstellung auf einem neuen
  Server, mit oder ohne dieses Werkzeug;
- [Reference](docs/REFERENCE.md) — Dateien und Sicherheit, Fehlerbehebung,
  bekannte Einschränkungen;
- [Development](docs/DEVELOPMENT.md) — Testen ohne echtes Konto,
  Übersetzungen.

## Einschränkungen

- Ein Knoten zur Zeit: Das Werkzeug sichert die Gäste des Knotens, auf dem
  es läuft.
- Nur Vollsicherungen (weder inkrementell noch Deduplizierung).
- Für das komprimierte Archiv wird lokaler Platz benötigt, beim Sichern wie
  beim Wiederherstellen.
- Die Übersetzungen wurden nicht von Muttersprachlern geprüft: Korrekturen
  sind willkommen.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
