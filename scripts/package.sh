#!/bin/bash
# Usage: scripts/package.sh /abs/path/built/STRÖM.app /abs/NEW/output/dir
# Packages an ad-hoc signed build (no Developer ID) as .dmg + .zip with SHA-256 sums.
set -euo pipefail
src="${1:?path to built .app}"; outdir="${2:?absolute NEW output dir}"
case "$src$outdir" in /*/*) ;; *) echo 'Absolute paths required' >&2; exit 2;; esac
[ -d "$src" ] || { echo "No such app: $src" >&2; exit 2; }
if [ -e "$outdir" ] && [ -n "$(ls -A "$outdir")" ]; then echo 'Output dir must be new or empty' >&2; exit 3; fi
mkdir -p "$outdir"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$src/Contents/Info.plist")"
stage="$(mktemp -d "${TMPDIR:-/tmp}/strom-pkg.XXXXXX")"
ditto --noextattr "$src" "$stage/STRÖM.app"; xattr -cr "$stage/STRÖM.app"
codesign --verify --deep --strict "$stage/STRÖM.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "STRÖM" -srcfolder "$stage" -ov -format UDZO "$outdir/STROM-$version.dmg" >/dev/null
ditto -c -k --keepParent --noextattr "$stage/STRÖM.app" "$outdir/STROM-$version.zip"
( cd "$outdir" && shasum -a 256 STROM-"$version".dmg STROM-"$version".zip | tee SHA256SUMS.txt )
echo "Release files in: $outdir"
