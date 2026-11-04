#!/bin/bash
# Usage: scripts/build.sh /absolute/new/path/STRÖM.app
# Needs: LIBTORRENT_INCLUDE, LIBTORRENT_LIB (dir with libtorrent-rasterbar.2.0.15.dylib), OPENSSL_LIB.
# Never overwrites an existing target. Signs ad-hoc (local testing only).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:?absolute .app path}"
case "$target" in /*.app) ;; *) echo 'Expected an absolute .app path' >&2; exit 2;; esac
[ -e "$target" ] && { echo 'Target exists; refusing to overwrite.' >&2; exit 3; }
: "${LIBTORRENT_INCLUDE:?}" "${LIBTORRENT_LIB:?}"
OPENSSL_LIB="${OPENSSL_LIB:-/opt/homebrew/opt/openssl@3/lib}"
b="$(mktemp -d "${TMPDIR:-/tmp}/strom-build.XXXXXX")"; app="$b/STRÖM.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses" "$app/Contents/Frameworks"
swift_files=("$root"/src/*.swift)
main_files=(); for f in "${swift_files[@]}"; do [ "$(basename "$f")" = StromSleepWatchdog.swift ] || main_files+=("$f"); done
c++ -std=c++17 -c -I"$LIBTORRENT_INCLUDE" -I/opt/homebrew/include "$root/src/strom-engine.cpp" -o "$b/engine.o"
# STROM_SWIFT_FLAGS is for the sandbox QA build only (e.g. -DSTROM_LICENSE_TESTING).
swiftc ${STROM_SWIFT_FLAGS:-} -parse-as-library "${main_files[@]}" "$b/engine.o" -L"$LIBTORRENT_LIB" -ltorrent-rasterbar -lc++ \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$app/Contents/MacOS/Strom"
swiftc "$root/src/StromSleepWatchdog.swift" -o "$app/Contents/MacOS/StromSleepWatchdog"
cp "$root/resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$root/resources/StromLogo.png" "$app/Contents/Resources/StromLogo.png"
[ -d "$root/resources/Licenses" ] && cp "$root"/resources/Licenses/* "$app/Contents/Resources/Licenses/"
cp "$LIBTORRENT_LIB/libtorrent-rasterbar.2.0.15.dylib" "$app/Contents/Frameworks/libtorrent-rasterbar.2.0.dylib"
cp -L "$OPENSSL_LIB/libssl.3.dylib" "$OPENSSL_LIB/libcrypto.3.dylib" "$app/Contents/Frameworks/"
chmod u+w "$app/Contents/Frameworks/"*.dylib
t="$app/Contents/Frameworks/libtorrent-rasterbar.2.0.dylib"
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib @loader_path/libssl.3.dylib "$t"
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib @loader_path/libcrypto.3.dylib "$t"
install_name_tool -change /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib @loader_path/libcrypto.3.dylib "$app/Contents/Frameworks/libssl.3.dylib"
xattr -cr "$app"; codesign --force --deep --sign - "$app"; codesign --verify --deep --strict "$app"
ditto --noextattr "$app" "$target"; echo "Built: $target"
