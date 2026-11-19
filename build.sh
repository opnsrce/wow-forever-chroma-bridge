#!/usr/bin/env bash
# macOS/Linux equivalent of build.ps1: builds dist/WoW-Chroma-Bridge-<version>.zip, the download
# end users get, from the wow-chroma folder plus the repository's LICENSE and CHANGELOG. The version number
# comes from the addon's .toc file, so bump "## Version" in wow-chroma/ChromaBridge/ChromaBridge.toc
# before building a release.
#
# Usage:  ./build.sh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
src="$root/wow-chroma"
version="$(sed -n 's/^## Version:[[:space:]]*//p' "$src/ChromaBridge/ChromaBridge.toc" | head -n 1 | tr -d '\r[:space:]')"
if [ -z "$version" ]; then
  echo "Couldn't read '## Version' from ChromaBridge.toc" >&2
  exit 1
fi
name="WoW-Chroma-Bridge-$version"
dist="$root/dist"
stage="$dist/$name"
zip="$dist/$name.zip"

rm -rf "$stage" "$zip"
mkdir -p "$stage"

files=(ChromaBridge chroma-bridge.ps1 install.ps1 Install.bat Uninstall.bat "Start Chroma Bridge.bat" "Stop Chroma Bridge.bat" README.md)
for f in "${files[@]}"; do cp -R "$src/$f" "$stage/"; done
cp "$root/LICENSE" "$root/CHANGELOG.md" "$stage/"

# The .bat files must keep Windows (CRLF) line endings, or cmd.exe can misread them.
for f in "$stage"/*.bat; do
  if ! grep -q $'\r$' "$f"; then
    echo "Warning: $(basename "$f") has Unix line endings; converting to CRLF." >&2
    perl -pi -e 's/\r?\n/\r\n/' "$f"
  fi
done

# Zip the folder itself, so extracting gives one tidy "WoW-Chroma-Bridge-x.y.z" folder.
# -X leaves out macOS extended attributes; .DS_Store files are excluded.
(cd "$dist" && zip -rqX "$zip" "$name" -x '*.DS_Store')
rm -rf "$stage"
ls -l "$zip"
