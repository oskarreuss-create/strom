# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Un client BitTorrent leggero e bello per macOS — con la possibilità di disattivare la condivisione (seeding).**

> Cercavo da tempo un client torrent leggero e bello, che permettesse di disattivare la condivisione dei file. Non ne ho trovato nessuno, così l'ho creato io. Ora sono felice di condividerlo con voi. Buon utilizzo.

## Funzionalità
- Gratuito e senza limiti di tempo: file torrent e link magnet, pausa, ordinamento, modalità compatta, notifiche e possibilità di disattivare la condivisione.
- Interfaccia in 6 lingue: English (predefinita), Deutsch, Français, Italiano, Русский, Español.
- **Plus** — pagamento unico di 7 $ per un dispositivo; funziona offline dopo l'attivazione. Comodità extra, come tenere il Mac attivo durante i download e rimuovere il file .torrent al termine.

## Requisiti
macOS 26 o successivo, Apple Silicon.

## Installazione
1. Scarica `STROM-<versione>.dmg` (o lo `.zip`) da [Releases](../../releases).
2. Trascina STRÖM in Applicazioni.
3. L'app non è firmata con un Apple Developer ID e non è notarizzata, quindi macOS mostra un avviso al primo avvio. È normale per le app indipendenti. Apri *Impostazioni di Sistema → Privacy e sicurezza*, trova STRÖM e fai clic su **Apri comunque**. Oppure esegui nel Terminale:

```bash
xattr -dr com.apple.quarantine /Applications/STRÖM.app
```

Verifica il download con `SHA256SUMS.txt` della release: `shasum -a 256 STROM-<versione>.dmg`.

## Compilare dai sorgenti
Servono Xcode (Swift 6), [libtorrent-rasterbar 2.0.15](https://github.com/arvidn/libtorrent) e OpenSSL 3 (ad es. `brew install openssl@3`).

```bash
export LIBTORRENT_INCLUDE=/path/to/libtorrent/include
export LIBTORRENT_LIB=/path/to/libtorrent/build   # cartella con libtorrent-rasterbar.2.0.15.dylib
scripts/build.sh "$PWD/_out/STRÖM.app"
```

Lo script non sovrascrive mai una `.app` esistente e firma la build in modalità ad hoc (solo per uso locale).

## Privacy
Nessuna statistica. L'app contatta `strom.oskarreus.ch` solo per acquistare, attivare e verificare una licenza Plus.

## Licenza
Il codice sorgente è disponibile con la [PolyForm Noncommercial License 1.0.0](LICENSE): puoi leggerlo, modificarlo e usarlo per scopi personali e non commerciali. Vendita, fork a pagamento o uso commerciale senza permesso non sono consentiti. Vedi [NOTICE](NOTICE). I componenti di terze parti inclusi (libtorrent-rasterbar, OpenSSL) mantengono le proprie licenze: [resources/Licenses](resources/Licenses). Altre condizioni: info@oskarreus.ch.

## Supporto
Domande e bug: [Issues](../../issues) oppure info@oskarreus.ch. Non pubblicare mai chiavi di licenza nelle Issues.
