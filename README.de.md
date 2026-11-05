# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Ein leichter, schöner BitTorrent-Client für macOS — mit der Möglichkeit, das Hochladen (Seeding) abzuschalten.**

> Ich habe lange nach einem leichten, schönen Torrent-Client gesucht, bei dem man das Teilen von Dateien abschalten kann. Gefunden habe ich keinen, also habe ich ihn selbst gebaut. Jetzt freue ich mich, ihn mit euch zu teilen. Viel Freude damit.

## Funktionen
- Kostenlos und ohne zeitliche Begrenzung: Torrent-Dateien und Magnet-Links, Pause, Sortierung, kompakter Modus, Benachrichtigungen und die Möglichkeit, das Teilen zu deaktivieren.
- Oberfläche in 6 Sprachen: English (Standard), Deutsch, Français, Italiano, Русский, Español.
- **Schauen beim Herunterladen:** Die Play-Taste an einem Torrent öffnet das Video in [BÜHNE](https://github.com/oskarreuss-create/buehne), unserem kostenlosen nativen Player (separater Download; STRÖM verlinkt ihn). Über den bereits geladenen Teil hinaus kann man nicht springen.
- **Plus** — einmalige Zahlung von 7 $ für ein Gerät; funktioniert nach der Aktivierung offline. Zusätzliche Komfortfunktionen, etwa den Mac während Downloads wach halten und die .torrent-Datei nach Abschluss entfernen.
- **Rabattcodes:** Wenn Sie einen haben, geben Sie ihn im selben Feld wie den Lizenzschlüssel ein – Sie gelangen zu einer Bestellseite mit angewendetem Rabatt.

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
Kein Tracking, keine Werbung, keine Cookies. Die App kontaktiert `strom.oskarreus.ch`, um eine Plus-Lizenz zu kaufen, zu aktivieren und zu prüfen und um Ihre Zustimmung zu den Bedingungen festzuhalten. Optionale anonyme Nutzungsstatistik wird nur gesendet, wenn Sie zustimmen (standardmässig aus); sie lässt sich nicht mit Ihnen verknüpfen. Vollständiger Text weiter unten.

## Lizenz
Der Quellcode steht unter der [PolyForm Noncommercial License 1.0.0](LICENSE): Du darfst ihn lesen, ändern und für private und nichtkommerzielle Zwecke nutzen. Verkauf, kostenpflichtige Forks oder kommerzielle Nutzung ohne Erlaubnis sind nicht gestattet. Siehe [NOTICE](NOTICE). Enthaltene Drittkomponenten (libtorrent-rasterbar, OpenSSL) behalten ihre eigenen Lizenzen: [resources/Licenses](resources/Licenses). Andere Bedingungen: info@oskarreus.ch.

## Support
Fragen und Fehler: [Issues](../../issues) oder info@oskarreus.ch. Poste niemals Lizenzschlüssel in Issues.

<!-- legal:start -->
## Philosophie
STRÖM ist ein leichter, schöner BitTorrent-Client für macOS. Wir glauben, ein Werkzeug sollte schnell, ruhig und einfach sein, Ihnen die Kontrolle lassen (Sie können das Teilen mit anderen abschalten) und Ihre Privatsphäre achten: kein verstecktes Tracking, keine Werbung, nichts wird verkauft.

## Datenschutz und Statistik im Überblick
- **Cookies.** Die STRÖM-App verwendet keine Cookies und keine Tracking-Technologien.
- **Was Ihren Mac nie verlässt.** Ihre Torrent-Liste, Dateinamen, Magnet-Links, heruntergeladene Dateien, Einstellungen und die Peers, mit denen Sie sich verbinden, bleiben auf Ihrem Mac.
- **Kauf- und Lizenzdaten.** Beim Kauf von Plus wickelt Stripe die Zahlung ab; Ihre Kartendaten sehen wir nie.
- **Update-Prüfung.** Einmal täglich (und beim Klick auf „Jetzt prüfen“) fragt STRÖM unseren Server, ob eine neue Version existiert.
- **Anonyme Nutzungsstatistik (optional).** Nur wenn Sie zustimmen, sendet STRÖM einmal täglich: Anzahl der Starts, aktive Nutzungszeit, Anzahl abgeschlossener Downloads, insgesamt heruntergeladene und hochgeladene Gigabyte, App-Version, macOS-Version und Oberflächensprache.
- **Wie die Statistik geschützt ist.** Die Statistik nutzt eine zufällige Installationsnummer, die die App erzeugt.

## Vollständiger Text
- [Nutzungsbedingungen / Datenschutz, Cookies und Statistik](AGREEMENT.de.md)

Rechtstexte:
- [GDPR / DSGVO — Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
- [Swiss Federal Act on Data Protection (FADP / nDSG), SR 235.1](https://www.fedlex.admin.ch/eli/cc/2022/491/en)
- [Swiss Copyright Act (URG / CopA), SR 231.1](https://www.fedlex.admin.ch/eli/cc/1993/1798_1798_1798/en)
- [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)
- [Stripe Privacy Policy (payment page)](https://stripe.com/privacy)
<!-- legal:end -->
