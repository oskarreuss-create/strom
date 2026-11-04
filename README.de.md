# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Ein leichter, schöner BitTorrent-Client für macOS — mit der Möglichkeit, das Hochladen (Seeding) abzuschalten.**

> Ich habe lange nach einem leichten, schönen Torrent-Client gesucht, bei dem man das Teilen von Dateien abschalten kann. Gefunden habe ich keinen, also habe ich ihn selbst gebaut. Jetzt freue ich mich, ihn mit euch zu teilen. Viel Freude damit.

## Funktionen
- Kostenlos und ohne zeitliche Begrenzung: Torrent-Dateien und Magnet-Links, Pause, Sortierung, kompakter Modus, Benachrichtigungen und die Möglichkeit, das Teilen zu deaktivieren.
- Oberfläche in 6 Sprachen: English (Standard), Deutsch, Français, Italiano, Русский, Español.
- **Plus** — einmalige Zahlung von 7 $ für ein Gerät; funktioniert nach der Aktivierung offline. Zusätzliche Komfortfunktionen, etwa den Mac während Downloads wach halten und die .torrent-Datei nach Abschluss entfernen.

## Voraussetzungen
macOS 26 oder neuer, Apple Silicon.

## Installation
1. Lade `STROM-<Version>.dmg` (oder die `.zip`) unter [Releases](../../releases) herunter.
2. Ziehe STRÖM in den Ordner „Programme“.
3. Die App ist nicht mit einer Apple Developer ID signiert und nicht notarisiert, daher zeigt macOS beim ersten Start eine Warnung. Das ist bei unabhängigen Apps normal. Öffne *Systemeinstellungen → Datenschutz & Sicherheit*, suche STRÖM und klicke auf **Trotzdem öffnen**. Oder führe im Terminal aus:

```bash
xattr -dr com.apple.quarantine /Applications/STRÖM.app
```

Den Download kannst du mit `SHA256SUMS.txt` aus dem Release prüfen: `shasum -a 256 STROM-<Version>.dmg`.

## Aus dem Quellcode bauen
Benötigt werden Xcode (Swift 6), [libtorrent-rasterbar 2.0.15](https://github.com/arvidn/libtorrent) und OpenSSL 3 (z. B. `brew install openssl@3`).

```bash
export LIBTORRENT_INCLUDE=/path/to/libtorrent/include
export LIBTORRENT_LIB=/path/to/libtorrent/build   # Ordner mit libtorrent-rasterbar.2.0.15.dylib
scripts/build.sh "$PWD/_out/STRÖM.app"
```

Das Skript überschreibt nie eine vorhandene `.app` und signiert den Build nur ad hoc (nur für die lokale Nutzung).

## Datenschutz
Keine Analyse- oder Tracking-Daten. Die App kontaktiert `strom.oskarreus.ch` nur zum Kauf, zur Aktivierung und zur Prüfung einer Plus-Lizenz.

## Lizenz
Der Quellcode steht unter der [PolyForm Noncommercial License 1.0.0](LICENSE): Du darfst ihn lesen, ändern und für private und nichtkommerzielle Zwecke nutzen. Verkauf, kostenpflichtige Forks oder kommerzielle Nutzung ohne Erlaubnis sind nicht gestattet. Siehe [NOTICE](NOTICE). Enthaltene Drittkomponenten (libtorrent-rasterbar, OpenSSL) behalten ihre eigenen Lizenzen: [resources/Licenses](resources/Licenses). Andere Bedingungen: info@oskarreus.ch.

## Support
Fragen und Fehler: [Issues](../../issues) oder info@oskarreus.ch. Poste niemals Lizenzschlüssel in Issues.
