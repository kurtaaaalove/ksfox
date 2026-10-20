#!/bin/bash
# Compare an official Camoufox zip with a self-built one.
# usage: bundle-diff.sh <official.zip> <self.zip> [workdir]
set -uo pipefail
OFF=$1; SELF=$2; W=${3:-$(mktemp -d)}
mkdir -p "$W/off" "$W/self"
[ -f "$W/off/camoufox-bin" ] || unzip -q -o "$OFF" -d "$W/off"
[ -f "$W/self/camoufox-bin" ] || unzip -q -o "$SELF" -d "$W/self"
echo "## (a) required files in self-built bundle"
for f in camoufox-bin properties.json fontconfig; do
  [ -e "$W/self/$f" ] && echo "OK   $f" || echo "MISS $f"
done
# version.json is not in any release zip: the launcher (camoufox-js / deploy script) writes it at install time
[ -e "$W/off/version.json" ] || [ -e "$W/self/version.json" ] || echo "n/a  version.json (absent from both zips; written at install)"
echo "## file list (path + type) diff"
(cd "$W/off" && find . | sort) > "$W/off.list"; (cd "$W/self" && find . | sort) > "$W/self.list"
echo "official=$(wc -l < $W/off.list) self=$(wc -l < $W/self.list)"
diff "$W/off.list" "$W/self.list" && echo "file list IDENTICAL"
echo "## text/config files (must be identical)"
for f in properties.json camoufox.cfg distribution/policies.json chrome.css \
         application.ini platform.ini dependentlibs.list; do
  if cmp -s "$W/off/$f" "$W/self/$f"; then echo "SAME $f"; else echo "DIFF $f"; diff <(cat "$W/off/$f" 2>/dev/null) <(cat "$W/self/$f" 2>/dev/null) | head -8; fi
done
echo "## every non-ELF file outside omni.ja (sha256)"
for d in off self; do (cd "$W/$d" && find . -type f ! -name '*.so' ! -name 'camoufox*' ! -name gfxtest ! -name omni.ja ! -path './fonts/*' -exec sha256sum {} + | sort -k2) > "$W/$d.misc"; done
diff "$W/off.misc" "$W/self.misc" | grep '^[<>]' | awk '{print $1, $3}' | sort -k2 | uniq -f1 -c | awk '{print "  differs:", $3}'
echo "  ($(wc -l < $W/off.misc) files compared)"
for f in /dev/null; do :
done
echo "## fontconfig/ and fonts/ trees"
diff -r -q "$W/off/fontconfig" "$W/self/fontconfig" && echo "fontconfig IDENTICAL"
(cd "$W/off/fonts" && find . -type f -exec sha256sum {} + | sort -k2) > "$W/off.fonts"
(cd "$W/self/fonts" && find . -type f -exec sha256sum {} + | sort -k2) > "$W/self.fonts"
diff -q "$W/off.fonts" "$W/self.fonts" >/dev/null && echo "fonts IDENTICAL ($(wc -l < $W/off.fonts) files)" || { echo "fonts DIFFER"; diff "$W/off.fonts" "$W/self.fonts" | head; }
echo "## omni.ja / browser/omni.ja entry lists (content of JS/resources)"
for o in omni.ja browser/omni.ja; do
  python3 - "$W/off/$o" "$W/self/$o" "$o" <<'PY'
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
echo "## ELF binaries (expected to differ byte-wise; size shown)"
for f in camoufox-bin libxul.so libmozgtk.so libnss3.so; do
  printf '%-14s official=%s self=%s %s\n' "$f" "$(stat -c %s $W/off/$f)" "$(stat -c %s $W/self/$f)" \
    "$(cmp -s $W/off/$f $W/self/$f && echo IDENTICAL || echo differs)"
done
echo "workdir: $W"
