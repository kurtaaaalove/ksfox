# ks fork: macOS arm64 build (cross-compiled on Linux)

Same source, same patches (`ks/main`, incl. `zz-ks-*`), same container as the Linux build; only the target
changes. This is how upstream CI builds every macOS release (`.github/workflows/release.yml`, job
`build-browser`, matrix `macos/arm64`): Linux host, clang + ld64.lld from `mach bootstrap`, the macOS SDK.

## SDK

Firefox 156 refuses any SDK older than **26.5** (`build/moz.configure/toolchain.configure`,
`mac_sdk_min_version()`), and `assets/macos.mozconfig` points at `~/.mozbuild/MacOSX26.5.sdk`.

`prepare` (with `KS_TARGET=macos,arm64`) runs the upstream `make setup-macos-sdk`, which downloads Apple's own
Command Line Tools SDK package from `swcdn.apple.com` and unpacks it with Mozilla's
`taskcluster/scripts/misc/unpack-sdk.py`, refusing anything whose **sha512 differs from the value pinned in the
upstream Makefile** (the same URL + hash as Mozilla's `macosx64-sdk-26.5` toolchain). No third-party
re-packaged SDK is used.

The SDK (≈840 MB) stays in the build machine's `work/mozbuild/MacOSX26.5.sdk`. It is covered by Apple's
Xcode/SDK licence: never commit it, never upload it, never ship it inside anything. The build output links
against it but does not contain it.

A Mac's own Xcode/CLT SDK only works if it is ≥ 26.5 (`xcrun --show-sdk-version`); the Mac mini had 26.4
(Xcode) / 15.5 (CLT) on 2026-10-20, so it could not be used, natively or copied.

## Build

```bash
B=/home/kurt/camoufox-build
export KS_TARGET=macos,arm64 KS_WORK_CAMOUFOX=$B/work/camoufox-mac   # own build tree: Linux obj/state untouched
$B/bin/cfrun prepare                 # fonts, Firefox source, 49 patches, bootstrap, SDK (unit cfbuild-prepare-macos-arm64)
KS_BUILD_DATE=<official mac application.ini BuildID> $B/bin/cfrun build
$B/bin/cfrun package                 # make package-macos arch=arm64 -> /work/dist/camoufox-<ver>-mac.arm64.zip
```

- `KS_TARGET` is passed into the container (`BUILD_TARGET`), a non-default target gets its own unit/log name
  (`cfbuild-<stage>-macos-arm64`, `/var/log/cfbuild/cfbuild-<stage>-macos-arm64.log`).
- `KS_BUILD_DATE`: every platform of a release has its own BuildID. v156.0.1-beta.36 mac.arm64 =
  `20261006020952` (Linux x86_64 is `20261006020805`). Read it from the official zip:
  `Camoufox.app/Contents/Resources/application.ini`.
- `Assets.car` is committed (`additions/browser/branding/camoufox/Assets.car`); on Linux
  `make generate-assets-car` just keeps it (actool exists only in full Xcode).
- The bundle is not code-signed beyond the linker's ad-hoc signature (same as the official zip: no
  `_CodeSignature`). Files copied over ssh carry no quarantine attribute; a zip downloaded in a browser does:
  `xattr -dr com.apple.quarantine Camoufox.app`.

## Verify

- `ks/verify/bundle-diff-mac.sh <official-mac.zip> <self-mac.zip> [workdir]`: file list, config files, fonts,
  omni.ja entries, Mach-O byte-identity count.
- On the Mac: fingerprint (`fp-compare-mac.mjs`, same idea as `fp-compare.mjs`: one camoufox-js config,
  official/self alternating, only `executablePath` swapped), smoke through a ksfox test instance, outbound.
  See the runbook (`SELFBUILD-RUNBOOK.md` §12) for the commands and the results.
