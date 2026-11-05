# STRÖM

[English](README.md) · [Deutsch](README.de.md) · [Français](README.fr.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Un client BitTorrent léger et élégant pour macOS — avec la possibilité de désactiver le partage (seeding).**

> Je cherchais depuis longtemps un client torrent léger et beau, qui permette de désactiver le partage des fichiers. Je n'en ai trouvé aucun, alors je l'ai créé moi-même. Je suis heureux de le partager avec vous. Profitez-en bien.

## Fonctionnalités
- Gratuit et sans limite de durée : fichiers torrent et liens magnet, pause, tri, mode compact, notifications, et possibilité de désactiver le partage.
- Interface en 6 langues : English (par défaut), Deutsch, Français, Italiano, Русский, Español.
- **Regarder pendant le téléchargement :** le bouton lecture d’un torrent ouvre la vidéo dans [BÜHNE](https://github.com/oskarreuss-create/buehne), notre lecteur natif gratuit (téléchargement séparé ; STRÖM donne le lien). On ne peut pas avancer au-delà de la partie déjà téléchargée.
- **Plus** — paiement unique de 7 $ pour un appareil ; fonctionne hors ligne après activation. Quelques fonctions de confort en plus, comme empêcher le Mac de se mettre en veille pendant les téléchargements et supprimer le fichier .torrent une fois terminé.
- **Codes de réduction :** si vous en avez un, saisissez-le dans le même champ que la clé de licence ; vous serez redirigé vers une page de paiement avec la réduction appliquée.

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
Pas de suivi, pas de publicité, pas de cookies. L'app contacte `strom.oskarreus.ch` pour acheter, activer et vérifier une licence Plus et pour enregistrer votre acceptation des conditions. Des statistiques d'utilisation anonymes facultatives ne sont envoyées que si vous les autorisez (désactivées par défaut) ; elles ne peuvent pas être liées à vous. Texte complet ci-dessous.

## Licence
Le code source est disponible sous la [PolyForm Noncommercial License 1.0.0](LICENSE) : vous pouvez le lire, le modifier et l'utiliser à des fins personnelles et non commerciales. La vente, les forks payants ou l'usage commercial sans autorisation sont interdits. Voir [NOTICE](NOTICE). Les composants tiers inclus (libtorrent-rasterbar, OpenSSL) conservent leurs propres licences : [resources/Licenses](resources/Licenses). Autres conditions : info@oskarreus.ch.

## Assistance
Questions et bogues : [Issues](../../issues) ou info@oskarreus.ch. Ne publiez jamais de clés de licence dans les Issues.

<!-- legal:start -->
## Philosophie
STRÖM est un client BitTorrent léger et élégant pour macOS. Nous pensons qu'un outil doit être rapide, discret et simple, vous laisser le contrôle (vous pouvez désactiver le partage avec les autres) et respecter votre vie privée : pas de suivi caché, pas de publicité, rien n'est vendu.

## Confidentialité et statistiques en bref
- **Cookies.** L'app STRÖM n'utilise ni cookies ni technologies de suivi.
- **Ce qui ne quitte jamais votre Mac.** Votre liste de torrents, les noms de fichiers, les liens magnet, les fichiers téléchargés, les réglages et les pairs auxquels vous vous connectez restent sur votre Mac.
- **Données d'achat et de licence.** Lors de l'achat de Plus, Stripe traite le paiement ; nous ne voyons jamais vos données de carte.
- **Vérification des mises à jour.** Une fois par jour (et lorsque vous cliquez sur « Vérifier maintenant »), STRÖM demande à notre serveur si une nouvelle version existe.
- **Statistiques d'utilisation anonymes (facultatif).** Uniquement si vous l'autorisez, STRÖM envoie une fois par jour : nombre de lancements, temps d'utilisation actif, nombre de téléchargements terminés, total de gigaoctets téléchargés et envoyés, version de l'app, version de macOS et langue de l'interface.
- **Comment les statistiques sont protégées.** Les statistiques utilisent un numéro d'installation aléatoire créé par l'app.

## Texte complet
- [Conditions d'utilisation / Confidentialité, cookies et statistiques](AGREEMENT.fr.md)

Textes juridiques:
- [GDPR / DSGVO — Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj)
- [Swiss Federal Act on Data Protection (FADP / nDSG), SR 235.1](https://www.fedlex.admin.ch/eli/cc/2022/491/en)
- [Swiss Copyright Act (URG / CopA), SR 231.1](https://www.fedlex.admin.ch/eli/cc/1993/1798_1798_1798/en)
- [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0)
- [Stripe Privacy Policy (payment page)](https://stripe.com/privacy)
<!-- legal:end -->
