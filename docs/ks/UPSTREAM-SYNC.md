# ks fork: upstream sync procedure

This fork (`kurtaaaalove/ksfox`) tracks `daijro/camoufox` and builds **Linux x86_64 only**.
Nothing here is published as a binary; the fork exists so we can rebuild, audit and (later) patch the
browser ourselves.

## Branches

| Branch | What it is |
|---|---|
| `main` | Mirror of `upstream/main`. Fast-forward only, never commit here. |
| `ks/base-<tag>` | Exactly the upstream commit of a browser release (from that release's `manifest.json`), plus ks tooling only (`docs/ks/`, `ks/`, `ks.mk`). Nothing is added under the hashed directories (`patches/ additions/ settings/ assets/ scripts/`, `Makefile`, `upstream.sh`), so its `source_digest` equals the release manifest and building it must reproduce the official release. |
| `ks/main` | `ks/base-<tag>` + our own patches in `patches/ks/` (`browser/patches/ks/` from v158), see `patches/ks/README.md`. This is what we build, verify (`ks/pipeline.sh`) and deploy. |

Rules:
- The upstream `Makefile` and existing upstream files are not edited; ks targets live in `ks.mk`
  (`make -f ks.mk ks-help`), so `source_digest` of a `ks/base-*` branch stays equal to the release manifest.
- Our patches go in `patches/ks/` and are named `zz-ks-NNN-<topic>.patch`. `scripts/patch.py` applies
  every `patches/**/*.patch` sorted by **basename**, so the `zz-` prefix makes ours apply last.

## Remotes

```bash
git remote -v
# origin    https://github.com/kurtaaaalove/ksfox.git
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

## 3. Merge into ks/main

```bash
git switch ks/main
git merge --no-ff ks/base-${TAG#v}       # textual conflicts can only be in ks files (we never edit upstream files)
```

Upstream moved the whole browser build under `browser/` in v158 (`browser/Makefile`, `browser/upstream.sh`,
`browser/patches/`, `browser/scripts/`, `browser/tests/build-tester`). The ks tooling detects either layout
(`ks-build.sh` `BW`, `ks.mk` `KS_BW`, `pipeline.sh`/`new-patch.sh` `PK`), so the merge needs exactly one manual step
when crossing that boundary:

```bash
git mv patches/ks browser/patches/ks     # scripts/patch.py reads <build dir>/patches/**; ours must live there
```

Before touching the main build tree, try the new base in its own worktree and build tree (same container, same
isolation; `KS_REPO` = what is bound read-only at /src, `KS_WORK_CAMOUFOX` = a separate /work/camoufox):

```bash
git worktree add -b ks/try-${TAG#v} ../wt-${TAG#v} $COMMIT && cd ../wt-${TAG#v} && git merge --no-ff ks/main
KS_REPO=$PWD KS_WORK_CAMOUFOX=/home/kurt/camoufox-build/work/camoufox-${TAG#v} KS_TAG=$TAG CFWAIT=1 \
  SUDO=/home/kurt/camoufox-build/bin/ssudo ks/container/cfrun apply   # fresh Firefox tree + every patch, fails on any .rej
```

A rejected upstream patch means upstream itself is broken for that tag (should not happen). A rejected
`zz-ks-*` patch has to be rebased: `ks/new-patch.sh begin` on the new tree, redo the edit, `KS_NUM=NNN ks/new-patch.sh <slug>`.

## 4. Rebuild

Pin rustc to the version the official release used (read it from the release's `about:buildconfig`, see
`ks/verify/README.md`): `CFCMD='. ~/.cargo/env; rustup toolchain install <ver> --profile minimal; rustup default <ver>' ks/container/cfrun shell`.

From the host (see `ks/container/README.md`; each stage runs in the userns build container):

```bash
ks/container/cfrun prepare   # fonts, Firefox tarball, patches (upstream + patches/ks), mach bootstrap
ks/container/cfrun build     # kspatch, then ./mach build -j12 (incremental if obj-* exists)
ks/container/cfrun package   # make package-linux arch=x86_64 -> work/dist/*.zip
```

For a new Firefox version run `prepare` again (it re-extracts the tarball). Within the same Firefox version a
changed / added / removed ks patch needs no manual step: `build` runs `ks-build.sh kspatch`, which swaps the
ks patch stack in the existing tree (see `patches/ks/README.md`). The whole loop including every check below and
the VM deploy is `ks/pipeline.sh`.

## 5. Verify before deploying

1. Bundle contents: `ks/verify/bundle-diff.sh <official.zip> <self.zip>` -- file list, `properties.json`,
   `camoufox.cfg`, `policies.json`, `version.json`, `fontconfig/` must be identical (binaries differ).
2. Fingerprint, same launch config: `ks/verify/fp-compare.mjs` launches the official and the self-built bundle with
   one identical camoufox-js config (2 runs each); `ks/verify/fp-diff.py` must show no field that differs between
   official and self-built unless it also differs between two runs of the same binary.
3. Smoke test through the launcher that production uses (open / screenshot / snapshot / click / evaluate / close).
4. Outbound connections during startup must not include any destination the official build does not contact.

Only after 1-4 pass does a bundle replace the official one.
