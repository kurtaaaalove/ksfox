# ks fork: upstream sync procedure

This fork (`kurtaaaalove/camoufox`) tracks `daijro/camoufox` and builds **Linux x86_64 only**.
Nothing here is published as a binary; the fork exists so we can rebuild, audit and (later) patch the
browser ourselves.

## Branches

| Branch | What it is |
|---|---|
| `main` | Mirror of `upstream/main`. Fast-forward only, never commit here. |
| `ks/base-<tag>` | Exactly the upstream commit of a browser release (from that release's `manifest.json`), plus ks tooling only (`docs/ks/`, `ks/`, `ks.mk`). Nothing is added under the hashed directories (`patches/ additions/ settings/ assets/ scripts/`, `Makefile`, `upstream.sh`), so its `source_digest` equals the release manifest and building it must reproduce the official release. |
| `ks/main` (from step 2) | `ks/base-<tag>` + our own patches in `patches/ks/` (directory created there). This is what we deploy. |

Rules:
- The upstream `Makefile` and existing upstream files are not edited; ks targets live in `ks.mk`
  (`make -f ks.mk ks-help`), so `source_digest` of a `ks/base-*` branch stays equal to the release manifest.
- Our patches go in `patches/ks/` and are named `zz-ks-NNN-<topic>.patch`. `scripts/patch.py` applies
  every `patches/**/*.patch` sorted by **basename**, so the `zz-` prefix makes ours apply last.

## Remotes

```bash
git remote -v
# origin    https://github.com/kurtaaaalove/camoufox.git
# upstream  https://github.com/daijro/camoufox.git
```

## 1. See what upstream released

```bash
git fetch upstream --tags
gh release list -R daijro/camoufox --limit 10
TAG=v158.0-beta.40                       # example
curl -fsSL https://github.com/daijro/camoufox/releases/download/$TAG/manifest.json | tee /tmp/manifest.json
# -> {"tag": ..., "source_digest": ..., "commit": "<sha>"}
```

Read `upstream.sh` (Firefox version) and `git log --oneline <old-commit>..<new-commit> -- patches additions settings`
to see which patches changed. A Firefox major-version bump means a long rebuild (ccache mostly misses).

## 2. New base branch for the release

```bash
COMMIT=$(python3 -c 'import json;print(json.load(open("/tmp/manifest.json"))["commit"])')
git switch -c ks/base-${TAG#v} $COMMIT
git checkout ks/base-156.0.1-beta.36 -- docs/ks ks ks.mk     # carry the ks tooling over
git commit -m "ks: tooling on ${TAG}"
make -f ks.mk ks-verify-manifest KS_TAG=$TAG    # must print digest MATCH
```

## 3. Merge into ks/main (once ks patches exist)

```bash
git switch ks/main
git merge --no-ff ks/base-${TAG#v}       # conflicts here are only in ks files or patches/ks
```

Then re-check every ks patch against the new Firefox tree (inside the build container):

```bash
make -f ks.mk ks-set-build KS_TAG=$TAG
make setup-minimal && make dir           # fails with a list of .rej files if any patch no longer applies
```

A rejected upstream patch means upstream itself is broken for that tag (should not happen). A rejected
`zz-ks-*` patch has to be rebased: follow `docs/patch-upgrading-guide.md` (`make workspace`, fix, `make diff`).

## 4. Rebuild

Inside the container (see `ks/container/`):

```bash
ks/container/ks-build.sh prepare   # fonts, Firefox tarball, patches, mach bootstrap
ks/container/ks-build.sh build     # ./mach build -j12 (incremental if obj-* exists)
ks/container/ks-build.sh package   # make package-linux arch=x86_64 -> dist/*.zip
```

For a new Firefox version run `prepare` again (it re-extracts the tarball). Within the same Firefox
version, after adding or editing a ks patch, apply it to the existing tree and run `build` only:

```bash
cd camoufox-<version>-<release> && patch -p1 --forward -i ../patches/ks/zz-ks-NNN-x.patch && cd ..
ks/container/ks-build.sh build && ks/container/ks-build.sh package
```

(`make dir` on a tree without its own git repo re-applies every patch and fails on the already-applied ones;
`make setup` creates that repo, but then `make dir` clobbers obj-* first. Choose per situation.)

## 5. Verify before deploying

1. Bundle contents: `ks/verify/bundle-diff.sh <official.zip> <self.zip>` -- file list, `properties.json`,
   `camoufox.cfg`, `policies.json`, `version.json`, `fontconfig/` must be identical (binaries differ).
2. Fingerprint, same launch config: `ks/verify/fp-compare.mjs` launches the official and the self-built bundle with
   one identical camoufox-js config (2 runs each); `ks/verify/fp-diff.py` must show no field that differs between
   official and self-built unless it also differs between two runs of the same binary.
3. Smoke test through the launcher that production uses (open / screenshot / snapshot / click / evaluate / close).
4. Outbound connections during startup must not include any destination the official build does not contact.

Only after 1-4 pass does a bundle replace the official one.
