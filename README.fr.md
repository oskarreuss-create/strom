# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Un client BitTorrent léger et élégant pour macOS — avec la possibilité de désactiver le partage (seeding).**

> Je cherchais depuis longtemps un client torrent léger et beau, qui permette de désactiver le partage des fichiers. Je n'en ai trouvé aucun, alors je l'ai créé moi-même. Je suis heureux de le partager avec vous. Profitez-en bien.

## Fonctionnalités
- Gratuit et sans limite de durée : fichiers torrent et liens magnet, pause, tri, mode compact, notifications, et possibilité de désactiver le partage.
- Interface en 6 langues : English (par défaut), Deutsch, Français, Italiano, Русский, Español.
- **Plus** — paiement unique de 7 $ pour un appareil ; fonctionne hors ligne après activation. Quelques fonctions de confort en plus, comme empêcher le Mac de se mettre en veille pendant les téléchargements et supprimer le fichier .torrent une fois terminé.

## Configuration requise
macOS 26 ou plus récent, Apple Silicon.

## Installation
1. Téléchargez `STROM-<version>.dmg` (ou le `.zip`) depuis [Releases](../../releases).
2. Faites glisser STRÖM dans Applications.
3. L'app n'est pas signée avec un Apple Developer ID et n'est pas notarisée ; macOS affiche donc un avertissement au premier lancement. C'est normal pour une app indépendante. Ouvrez *Réglages Système → Confidentialité et sécurité*, repérez STRÖM et cliquez sur **Ouvrir quand même**. Ou exécutez dans le Terminal :

```bash
xattr -dr com.apple.quarantine /Applications/STRÖM.app
```

Vérifiez le téléchargement avec `SHA256SUMS.txt` de la release : `shasum -a 256 STROM-<version>.dmg`.

## Compiler depuis les sources
Il faut Xcode (Swift 6), [libtorrent-rasterbar 2.0.15](https://github.com/arvidn/libtorrent) et OpenSSL 3 (par ex. `brew install openssl@3`).

```bash
export LIBTORRENT_INCLUDE=/path/to/libtorrent/include
export LIBTORRENT_LIB=/path/to/libtorrent/build   # dossier contenant libtorrent-rasterbar.2.0.15.dylib
scripts/build.sh "$PWD/_out/STRÖM.app"
```

Le script n'écrase jamais une `.app` existante et signe la compilation en ad hoc (usage local uniquement).

## Confidentialité
Aucune statistique. L'app contacte `strom.oskarreus.ch` uniquement pour acheter, activer et vérifier une licence Plus.

## Licence
Le code source est disponible sous la [PolyForm Noncommercial License 1.0.0](LICENSE) : vous pouvez le lire, le modifier et l'utiliser à des fins personnelles et non commerciales. La vente, les forks payants ou l'usage commercial sans autorisation sont interdits. Voir [NOTICE](NOTICE). Les composants tiers inclus (libtorrent-rasterbar, OpenSSL) conservent leurs propres licences : [resources/Licenses](resources/Licenses). Autres conditions : info@oskarreus.ch.

## Assistance
Questions et bogues : [Issues](../../issues) ou info@oskarreus.ch. Ne publiez jamais de clés de licence dans les Issues.
