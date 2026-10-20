#!/bin/bash
# Unpack the self-built macOS bundle to ~/engines/ksfox-156.0.1-beta.36 and build a separate HOME for the
# 9378 test instance (camoufox-js resolves its engine as $HOME/Library/Caches/camoufox/Camoufox.app).
# usage: setup-engine.sh <zip> <expected-sha256>
set -euo pipefail
Z=$1; WANT=$2
E=$HOME/engines/ksfox-156.0.1-beta.36; TH=$HOME/engines/ksfox-test-home; C=$TH/Library/Caches/camoufox
GOT=$(shasum -a 256 "$Z" | cut -d' ' -f1); [ "$GOT" = "$WANT" ] || { echo "sha256 mismatch $GOT"; exit 1; }
rm -rf "$E.tmp"; mkdir -p "$E.tmp"; /usr/bin/unzip -q "$Z" -d "$E.tmp"
[ -x "$E.tmp/Camoufox.app/Contents/MacOS/camoufox" ] || { echo "no Camoufox.app in zip"; exit 1; }
rm -rf "$E"; mv "$E.tmp" "$E"
echo '{"version":"156.0.1","release":"beta.36"}' > "$E/version.json"
# uBO is not part of the build: camoufox-js installs it into <cache>/Camoufox.app/Contents/Resources/addons/UBO
mkdir -p "$E/Camoufox.app/Contents/Resources/addons"
cp -R "$HOME/Library/Caches/camoufox/Camoufox.app/Contents/Resources/addons/UBO" "$E/Camoufox.app/Contents/Resources/addons/"
mkdir -p "$C"; ln -sfn "$E/Camoufox.app" "$C/Camoufox.app"; cp "$E/version.json" "$C/version.json"
echo "engine=$E files=$(find "$E" -type f | wc -l) size=$(du -sh "$E" | cut -f1)"
xattr -l "$E/Camoufox.app/Contents/MacOS/camoufox" | head -3
for a in "$HOME/Library/Caches/camoufox/Camoufox.app" "$E/Camoufox.app"; do
  echo "== codesign $a"; codesign -dv "$a/Contents/MacOS/camoufox" 2>&1 | grep -E 'Signature|flags|TeamIdentifier|CDHash' ; done
