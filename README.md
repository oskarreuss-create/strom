# STRÖM

**A light, beautiful BitTorrent client for macOS — with the option to turn off seeding.**
**Лёгкий и красивый торрент-клиент для macOS с возможностью отключить раздачу файлов.**

> I had been looking for a light, good-looking torrent client that lets you switch off uploading to other peers. I couldn't find one, so I made it myself. Now I'm happy to share it with you. Please enjoy.
>
> Я давно искал лёгкий и красивый торрент-клиент, в котором можно отключить раздачу файлов. В итоге я ничего не нашёл и решил создать его сам. Теперь я рад поделиться им с вами. Пользуйтесь на здоровье.

---

## English

### Features
- Free, with no time limit: torrent files and magnet links, pause, sorting, compact mode, notifications, and the option to disable sharing.
- Interface in 6 languages: English (default), Русский, Deutsch, Français, Italiano, Español.
- **Plus** — a one-time payment of $7 for one device; works offline after activation. Extra conveniences, such as keeping the Mac awake during downloads and removing the .torrent file after completion.

### Requirements
macOS 26 or later, Apple Silicon.

### Install
1. Download `STROM-<version>.dmg` (or the `.zip`) from [Releases](../../releases).
2. Drag STRÖM to Applications.
3. The app is not signed with an Apple Developer ID and is not notarized, so macOS shows a warning on first launch. This is normal for independent apps. Open *System Settings → Privacy & Security*, find STRÖM and click **Open Anyway**. Or run in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/STRÖM.app
```

You can verify the download with `SHA256SUMS.txt` from the release: `shasum -a 256 STROM-<version>.dmg`.

### Build from source
You need Xcode (Swift 6), [libtorrent-rasterbar 2.0.15](https://github.com/arvidn/libtorrent) and OpenSSL 3 (e.g. `brew install openssl@3`).

```bash
export LIBTORRENT_INCLUDE=/path/to/libtorrent/include
export LIBTORRENT_LIB=/path/to/libtorrent/build   # folder with libtorrent-rasterbar.2.0.15.dylib
scripts/build.sh "$PWD/_out/STRÖM.app"
```

The script never overwrites an existing `.app` and signs the build ad hoc (for local use only).

### Privacy
No analytics. The app contacts `strom.oskarreus.ch` only to purchase, activate and verify a Plus license.

### License
Source code is available under the [PolyForm Noncommercial License 1.0.0](LICENSE): you may read, modify and use it for personal and non-commercial purposes. Selling it, publishing paid forks or commercial use without permission is not allowed. See [NOTICE](NOTICE). Bundled third-party components (libtorrent-rasterbar, OpenSSL) keep their own licenses: [resources/Licenses](resources/Licenses). Other terms: info@oskarreus.ch.

### Support
Questions and bugs: [Issues](../../issues) or info@oskarreus.ch. Never post license keys in Issues.

---

## Русский

### Возможности
- Бесплатно и без ограничений по времени: торрент-файлы и magnet-ссылки, пауза, сортировка, компактный режим, уведомления, отключение раздачи.
- Интерфейс на 6 языках; по умолчанию английский, язык меняется в настройках.
- **Plus** — один платёж 7 $, одно устройство, после активации работает без интернета. Дополнительные удобства: не давать Mac засыпать во время загрузок, убирать .torrent после завершения.

### Требования
macOS 26 или новее, Apple Silicon.

### Установка
1. Скачайте `STROM-<версия>.dmg` (или `.zip`) в разделе [Releases](../../releases).
2. Перетащите STRÖM в «Программы».
3. Приложение не подписано сертификатом Apple Developer ID и не нотаризовано, поэтому при первом запуске macOS покажет предупреждение. Это нормально для независимых программ. Откройте «Системные настройки → Конфиденциальность и безопасность», найдите STRÖM и нажмите «Всё равно открыть». Либо выполните в Терминале команду `xattr -dr com.apple.quarantine /Applications/STRÖM.app`.

Проверить файл можно по `SHA256SUMS.txt` из релиза.

### Сборка, конфиденциальность, лицензия
См. английский раздел выше. Кратко: сборка через `scripts/build.sh`; аналитики нет, сервер лицензий используется только для Plus; исходный код под PolyForm Noncommercial 1.0.0 (личное и некоммерческое использование), уведомление — в [NOTICE](NOTICE).
