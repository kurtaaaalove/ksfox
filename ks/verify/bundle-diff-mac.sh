#!/bin/bash
# Compare an official Camoufox macOS zip with a self-built one (Camoufox.app layout).
# usage: bundle-diff-mac.sh <official-mac.zip> <self-mac.zip> [workdir]
set -uo pipefail
OFF=$1; SELF=$2; W=${3:-$(mktemp -d)}
mkdir -p "$W"
SAFE=$(dirname "$0")/safe-unzip.py      # never `unzip` a container-built zip on the host
A=Camoufox.app/Contents
[ -f "$W/off/$A/MacOS/camoufox" ]  || { rm -rf "$W/off";  python3 -I "$SAFE" "$OFF"  "$W/off"  || exit 1; }
[ -f "$W/self/$A/MacOS/camoufox" ] || { rm -rf "$W/self"; python3 -I "$SAFE" "$SELF" "$W/self" || exit 1; }
echo "## (a) required files in self-built bundle"
for f in MacOS/camoufox MacOS/XUL Resources/properties.json Resources/omni.ja Resources/browser/omni.ja Info.plist; do
  [ -e "$W/self/$A/$f" ] && echo "OK   $f" || echo "MISS $f"
done
echo "## file list (path) diff"
(cd "$W/off" && find . | sort) > "$W/off.list"; (cd "$W/self" && find . | sort) > "$W/self.list"
echo "official=$(wc -l < $W/off.list) self=$(wc -l < $W/self.list)"
diff "$W/off.list" "$W/self.list" && echo "file list IDENTICAL"
echo "## text/config files (must be identical, BuildID lines excepted)"
for f in Resources/properties.json Resources/camoufox.cfg Resources/distribution/policies.json Resources/chrome.css \
         Resources/application.ini Resources/platform.ini Resources/dependentlibs.list Info.plist PkgInfo; do
  if cmp -s "$W/off/$A/$f" "$W/self/$A/$f"; then echo "SAME $f"; else echo "DIFF $f"; diff <(cat "$W/off/$A/$f" 2>/dev/null) <(cat "$W/self/$A/$f" 2>/dev/null) | head -8; fi
done
echo "## every non-Mach-O file outside omni.ja and fonts (sha256)"
for d in off self; do (cd "$W/$d" && find . -type f ! -path '*/Contents/MacOS/*' ! -path '*/Frameworks/*' ! -name omni.ja \
   ! -path '*/Resources/fonts/*' -exec sha256sum {} + | sort -k2) > "$W/$d.misc"; done
diff "$W/off.misc" "$W/self.misc" | grep '^[<>]' | awk '{print $3}' | sort | uniq -c | awk '{print "  differs:", $2}'
echo "  ($(wc -l < $W/off.misc) files compared)"
echo "## fonts/ tree"
(cd "$W/off/$A/Resources/fonts" && find . -type f -exec sha256sum {} + | sort -k2) > "$W/off.fonts"
(cd "$W/self/$A/Resources/fonts" && find . -type f -exec sha256sum {} + | sort -k2) > "$W/self.fonts"
cmp -s "$W/off.fonts" "$W/self.fonts" && echo "fonts IDENTICAL ($(wc -l < $W/off.fonts) files)" || { echo "fonts DIFFER"; diff "$W/off.fonts" "$W/self.fonts" | head; }
echo "## omni.ja / browser/omni.ja entries"
for o in omni.ja browser/omni.ja; do
  python3 -I - "$W/off/$A/Resources/$o" "$W/self/$A/Resources/$o" "$o" <<'PY'
import sys, zipfile, hashlib
a, b, name = sys.argv[1:4]
def entries(p):
    z = zipfile.ZipFile(p); return {i.filename: hashlib.sha256(z.read(i)).hexdigest() for i in z.infolist()}
ea, eb = entries(a), entries(b)
only_a = sorted(set(ea) - set(eb)); only_b = sorted(set(eb) - set(ea))
changed = sorted(k for k in set(ea) & set(eb) if ea[k] != eb[k])
print(f"{name}: official={len(ea)} self={len(eb)} only_official={len(only_a)} only_self={len(only_b)} content_differs={len(changed)}")
for k in (only_a[:5] + only_b[:5] + changed[:15]): print("   ", k)
PY
done
echo "## Mach-O binaries (byte-identical count; sizes of the big ones)"
n=0; same=0
while IFS= read -r f; do
  if file -b "$W/off/$f" | grep -q Mach-O; then n=$((n+1)); cmp -s "$W/off/$f" "$W/self/$f" && same=$((same+1)) || echo "  differs: $f ($(stat -c %s "$W/off/$f") vs $(stat -c %s "$W/self/$f" 2>/dev/null))"; fi
done < <(cd "$W/off" && find . -type f \( -path '*/Contents/MacOS/*' -o -path '*/Frameworks/*' -o -name '*.dylib' \) | sort -u)
echo "  Mach-O files: $n, byte-identical: $same"
echo "workdir: $W"
