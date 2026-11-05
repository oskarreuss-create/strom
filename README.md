# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**A light, beautiful BitTorrent client for macOS — with the option to turn off seeding.**

> I had been looking for a light, good-looking torrent client that lets you switch off uploading to other peers. I couldn't find one, so I made it myself. Now I'm happy to share it with you. Please enjoy.

## Features
- Free, with no time limit: torrent files and magnet links, pause, sorting, compact mode, notifications, and the option to disable sharing.
- Interface in 6 languages: English (default), Deutsch, Français, Italiano, Русский, Español.
- **Watch while downloading:** the play button on a torrent opens the video in [BÜHNE](https://github.com/oskarreuss-create/buehne), our free native player (separate download; STRÖM links to it). You cannot jump past the part that has already been downloaded.
- **Plus** — a one-time payment of $7 for one device; works offline after activation. Extra conveniences, such as keeping the Mac awake during downloads and removing the .torrent file after completion.
- **Discount codes:** if you have one, enter it in the same field as the license key — you will be taken to a checkout page with the discount applied.

## Requirements
macOS 26 or later, Apple Silicon.

## Install
1. Download `STROM-<version>.dmg` (or the `.zip`) from [Releases](../../releases).
2. Drag STRÖM to Applications.
3. The app is not signed with an Apple Developer ID and is not notarized, so macOS shows a warning on first launch. This is normal for independent apps. Open *System Settings → Privacy & Security*, find STRÖM and click **Open Anyway**. Or run in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/STRÖM.app
```

Verify the download with `SHA256SUMS.txt` from the release: `shasum -a 256 STROM-<version>.dmg`.

## Build from source
You need Xcode (Swift 6), [libtorrent-rasterbar 2.0.15](https://github.com/arvidn/libtorrent) and OpenSSL 3 (e.g. `brew install openssl@3`).

```bash
export LIBTORRENT_INCLUDE=/path/to/libtorrent/include
export LIBTORRENT_LIB=/path/to/libtorrent/build   # folder with libtorrent-rasterbar.2.0.15.dylib
scripts/build.sh "$PWD/_out/STRÖM.app"
```

The script never overwrites an existing `.app` and signs the build ad hoc (for local use only).

## Privacy
No tracking, no ads, no cookies. The app contacts `strom.oskarreus.ch` to buy, activate and verify a Plus license and to record that you accepted the terms. Optional anonymous usage statistics are sent only if you allow them (off by default); they cannot be linked to you. See the full text below.

## License
Source code is available under the [PolyForm Noncommercial License 1.0.0](LICENSE): you may read, modify and use it for personal and non-commercial purposes. Selling it, publishing paid forks or commercial use without permission is not allowed. See [NOTICE](NOTICE). Bundled third-party components (libtorrent-rasterbar, OpenSSL) keep their own licenses: [resources/Licenses](resources/Licenses). Other terms: info@oskarreus.ch.

## Support
Questions and bugs: [Issues](../../issues) or info@oskarreus.ch. Never post license keys in Issues.

<!-- legal:start -->
## Philosophy
STRÖM is a light, beautiful BitTorrent client for macOS. We believe a tool should be fast, quiet and simple, should leave you in control (you can switch off sharing with other peers), and should respect your privacy: no hidden tracking, no ads, nothing sold.

## Privacy and statistics at a glance
- **Cookies.** The STRÖM app uses no cookies and no tracking technologies.
- **What never leaves your Mac.** Your torrent list, file names, magnet links, downloaded files, settings and the peers you connect to stay on your Mac.
- **Purchase and license data.** When you buy Plus, Stripe processes the payment; we never see your card data.
- **Update check.** Once a day (and when you press “Check now”) STRÖM asks our server whether a new version exists.
- **Anonymous usage statistics (optional).** Only if you allow it, STRÖM sends once a day: number of launches, active time, number of completed downloads, total gigabytes downloaded and uploaded, app version, macOS version and interface language.
- **How statistics are protected.** Statistics use a random installation number created by the app.

## Full text
- [Terms of use / Privacy, cookies and statistics](AGREEMENT.en.md)

Legal texts:
- [GDPR / DSGVO — Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
- [Swiss Federal Act on Data Protection (FADP / nDSG), SR 235.1](https://www.fedlex.admin.ch/eli/cc/2022/491/en)
- [Swiss Copyright Act (URG / CopA), SR 231.1](https://www.fedlex.admin.ch/eli/cc/1993/1798_1798_1798/en)
- [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)
- [Stripe Privacy Policy (payment page)](https://stripe.com/privacy)
<!-- legal:end -->
