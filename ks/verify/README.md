# Verification tools (official release vs self-built)

| Tool | Checks |
|---|---|
| `manifest-check.py` (via `make -f ks.mk ks-verify-manifest`) | HEAD contains the release commit; committed tree's `source_digest` equals the release `manifest.json` |
| `bundle-diff.sh <official.zip> <self.zip> [workdir]` | required files, file list, config files, fonts/fontconfig sha256, every omni.ja entry, ELF sizes |
| `fp.html` | fixture page: navigator, screen, window, Intl/timezone, WebGL 1/2, canvas (text + shapes-only), OfflineAudioContext, font probe (100 families), voices, media devices, math. Result is JSON in `#out` (Camoufox runs automation JS in an isolated world, so `window.*` set by the page is not visible to Playwright) |
| `fp-compare.mjs <outdir> <officialDir> <selfDir> <fixtureUrl> [display]` | generates ONE camoufox-js launch config, then launches official, self, official, self with exactly that config (only the binary and its fontconfig path change). `FP_EXTRA_PREFS='{"privacy.fingerprintingProtection":false,"privacy.baselineFingerprintingProtection":false}'` turns off Gecko's per-session canvas randomisation so canvas pixels can be compared |
| `fp-diff.py a.json b.json ...` | flattens and lists every field that differs; a field that also differs between two runs of the same binary is noise, not a build difference |
| `ab-launch.mjs` / `ab-outbound.sh` / `ab-attrib.py` | A/B cold-start outbound capture (tcpdump + ss sampler, connections attributed to the probe binary via /proc/<pid>/exe) and the per-run destination sets. Note the Widevine CDM download host is chosen per request by Google (edgedl.me.gvt1.com / dl.google.com / www.google.com) for official and self-built alike |
| `bundle-check.py <offDir> <candDir> <patches/ks> [--prev dir] [--buildid id]` | gate used by `ks/pipeline.sh`: same file list, configs, fonts; omni.ja entries differ only by build path/BuildID or as declared (`KS-Bundle-Diff`/`KS-Bundle-Marker`); application.ini BuildID aligned; ELF report incl. strings residual and diff vs the previous candidate |
| `fp-check.py <fp-compare outdir> [patches/ks]` | gate: every fp.* field identical official vs candidate in all 4 runs (or declared with `KS-Fingerprint`) |
| `bt-compare.py <official.json> <candidate.json>` | gate: build-tester grade, score and the set of failed checks identical |
| `outbound-probe.sh` + `outbound-check.py` + `outbound-baseline-156.txt` | gate: 180 s cold-start capture of the candidate; every destination attributed to it is in the official baseline (DNS names lower-cased: 0x20 case randomisation) |
| `runtime-checks.py` + `runtime-check.mjs` | `KS-Runtime-Check` headers -> validated JSON -> Playwright on the VM opens e.g. about:buildconfig and looks for the marker |
| `safe-unzip.py <zip> <dest>` | the only way a container-built zip is unpacked on the host (refuses symlink / absolute / `..` members, clamps modes) |
| `pcap-dests.py <pcap>` | outbound destinations (IP, ports, DNS/SNI names) from a `tcpdump -i any` capture, pure Python |

Toolchain pin: the official build's compiler versions are in its `about:buildconfig`
(`omni.ja` -> `chrome/toolkit/content/global/buildconfig.html`). v156.0.1-beta.36 was built with rustc 1.98.1
and the clang that `mach bootstrap` fetches (same Taskcluster artifact for everyone), so pin rustup to the same
rustc (`rustup default 1.98.1`) for the closest rebuild. BuildID (a timestamp) and build paths always differ.
