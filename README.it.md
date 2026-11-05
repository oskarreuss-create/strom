# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Un client BitTorrent leggero e bello per macOS — con la possibilità di disattivare la condivisione (seeding).**

> Cercavo da tempo un client torrent leggero e bello, che permettesse di disattivare la condivisione dei file. Non ne ho trovato nessuno, così l'ho creato io. Ora sono felice di condividerlo con voi. Buon utilizzo.

## Funzionalità
- Gratuito e senza limiti di tempo: file torrent e link magnet, pausa, ordinamento, modalità compatta, notifiche e possibilità di disattivare la condivisione.
- Interfaccia in 6 lingue: English (predefinita), Deutsch, Français, Italiano, Русский, Español.
- **Guardare durante il download:** il pulsante play su un torrent apre il video in [BÜHNE](https://github.com/oskarreuss-create/buehne), il nostro lettore nativo gratuito (download separato; STRÖM ne mostra il link). Non si può saltare oltre la parte già scaricata.
- **Plus** — pagamento unico di 7 $ per un dispositivo; funziona offline dopo l'attivazione. Comodità extra, come tenere il Mac attivo durante i download e rimuovere il file .torrent al termine.
- **Codici sconto:** se ne hai uno, inseriscilo nello stesso campo della chiave di licenza; verrai portato a una pagina di pagamento con lo sconto applicato.

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
Nessun tracciamento, nessuna pubblicità, nessun cookie. L'app contatta `strom.oskarreus.ch` per acquistare, attivare e verificare una licenza Plus e per registrare la tua accettazione delle condizioni. Statistiche d'uso anonime facoltative vengono inviate solo se le consenti (disattivate per impostazione predefinita); non possono essere collegate a te. Testo completo qui sotto.

## Licenza
Il codice sorgente è disponibile con la [PolyForm Noncommercial License 1.0.0](LICENSE): puoi leggerlo, modificarlo e usarlo per scopi personali e non commerciali. Vendita, fork a pagamento o uso commerciale senza permesso non sono consentiti. Vedi [NOTICE](NOTICE). I componenti di terze parti inclusi (libtorrent-rasterbar, OpenSSL) mantengono le proprie licenze: [resources/Licenses](resources/Licenses). Altre condizioni: info@oskarreus.ch.

## Supporto
Domande e bug: [Issues](../../issues) oppure info@oskarreus.ch. Non pubblicare mai chiavi di licenza nelle Issues.

<!-- legal:start -->
## Filosofia
STRÖM è un client BitTorrent leggero e bello per macOS. Crediamo che uno strumento debba essere veloce, discreto e semplice, lasciarti il controllo (puoi disattivare la condivisione con gli altri) e rispettare la tua privacy: nessun tracciamento nascosto, nessuna pubblicità, nulla viene venduto.

## Privacy e statistiche in sintesi
- **Cookie.** L'app STRÖM non usa cookie né tecnologie di tracciamento.
- **Cosa non lascia mai il tuo Mac.** L'elenco dei torrent, i nomi dei file, i link magnet, i file scaricati, le impostazioni e i peer ai quali ti connetti restano sul tuo Mac.
- **Dati di acquisto e di licenza.** Quando acquisti Plus, Stripe elabora il pagamento; non vediamo mai i dati della tua carta.
- **Controllo degli aggiornamenti.** Una volta al giorno (e quando premi « Controlla ora ») STRÖM chiede al nostro server se esiste una nuova versione.
- **Statistiche d'uso anonime (facoltative).** Solo se lo consenti, STRÖM invia una volta al giorno: numero di avvii, tempo di utilizzo attivo, numero di download completati, gigabyte totali scaricati e inviati, versione dell'app, versione di macOS e lingua dell'interfaccia.
- **Come sono protette le statistiche.** Le statistiche usano un numero di installazione casuale creato dall'app.

## Testo completo
- [Condizioni d'uso / Privacy, cookie e statistiche](AGREEMENT.it.md)

Testi giuridici:
- [GDPR / DSGVO — Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
- [Swiss Federal Act on Data Protection (FADP / nDSG), SR 235.1](https://www.fedlex.admin.ch/eli/cc/2022/491/en)
- [Swiss Copyright Act (URG / CopA), SR 231.1](https://www.fedlex.admin.ch/eli/cc/1993/1798_1798_1798/en)
- [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)
- [Stripe Privacy Policy (payment page)](https://stripe.com/privacy)
<!-- legal:end -->
