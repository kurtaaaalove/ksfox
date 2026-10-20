# patches/ks -- our own browser patches (kurtaaaalove/camoufox, branch `ks/main` only)

Upstream Camoufox patches live one level up and are never edited here. Everything we change in the browser is a
patch file in this directory, applied **after** all upstream patches.

## Naming and order

`zz-ks-NNN-<slug>.patch`

- `NNN`: three digits, in the order they must apply; a number is never reused for a different change.
- `<slug>`: lowercase-kebab, what it does (`build-marker`, `zh-tw-font-fallback`, ...).
- `scripts/patch.py` (upstream) applies every `patches/**/*.patch` sorted by **basename**. Upstream basenames are
  all lowercase words (`a...` to `w...`), so the `zz-` prefix puts ours last, and among ours `NNN` decides.
- Only `*.patch` files are applied; this README and anything else here is ignored by the build.

## Header (required)

Free text before the first `diff --git` line is ignored by `patch(1)`, so every patch starts with a header.
`ks/new-patch.sh` writes the template; fill in every `TODO` before committing.

| Key | Meaning | Read by |
|---|---|---|
| `KS-Patch:` | file name without `.patch` | humans |
| `KS-Purpose:` | what and why (continuation lines start with two spaces) | humans |
| `KS-Fingerprint:` | `none`, or the fp.html fields (`fp.navigator.platform` ...) this patch is MEANT to change | `ks/verify/fp-check.py` (declared fields may differ from official, nothing else may) |
| `KS-Web-Visible:` | `no`, or how a web page could observe the change | humans (review) |
| `KS-Verify:` | how it is verified | humans |
| `KS-Touches:` | Firefox-tree paths in the diff | humans / upgrade triage |
| `KS-Bundle-Diff:` | `omni.ja!<entry>` (or `browser/omni.ja!...`) this patch is allowed to change; it must then differ | `ks/verify/bundle-check.py` |
| `KS-Bundle-Marker:` | `<omni>!<entry> <text>` that must be present in the packaged bundle | `bundle-check.py` |
| `KS-Runtime-Check:` | `<url> <text>`: the deployed browser, driven by Playwright, must show `<text>` on `<url>` (about: pages work) | `ks/pipeline.sh` step `vmcheck` |

## How the patches get into a build

- **Full prepare** (`ks/container/cfrun prepare`, a fresh Firefox tree): upstream `make dir` -> `scripts/patch.py`
  applies upstream + ks patches in one pass. Nothing in the upstream `Makefile` or `scripts/` is changed.
- **Incremental** (`ks/container/cfrun build`, also the first step of `ks/pipeline.sh`): `ks-build.sh kspatch`
  keeps a quilt-like stack. It remembers which ks patches are in the tree (`/work/camoufox/.ks-state/<srcdir>/`,
  outside the Firefox tree), un-applies a patch whose diff changed or that was removed (newest first), then applies
  the new/changed ones in order. Same `patch -p1 -l --binary` flags as `scripts/patch.py`. A header-only edit does
  not touch the tree. A patch that does not apply stops the build with the `patch` output.

## Workflow: a new patch

```bash
ks/new-patch.sh begin                              # kspatch + snapshot the tree (shadow git outside the tree, tag ks-base)
ks/new-patch.sh edit toolkit/content/foo.html      # copy a tree file to .ks-edit/<path> (gitignored) and edit it on the host
#   or edit inside the container: CFCMD='cd /work/camoufox/camoufox-<ver>-<rel> && ...' ks/container/cfrun shell
ks/new-patch.sh <slug>                             # git diff vs ks-base -> zz-ks-<next NNN>-<slug>.patch,
                                                   # checked: applies onto ks-base with fuzz 0, reverses on the tree
$EDITOR patches/ks/zz-ks-NNN-<slug>.patch          # fill in the KS-* header
git add patches/ks && git commit                   # on ks/main
ks/pipeline.sh                                     # build, package, all gates, deploy to VM :9376, VM checks
```

Rework of an existing patch: edit the `.patch` directly (kspatch swaps it in), or `KS_NUM=NNN ks/new-patch.sh <slug>`
after `begin` to regenerate it under the same number.

## Rules

1. One concern per patch. No patch without a concrete, measured reason (a leak case, a site that breaks).
2. Do not touch fingerprint surfaces "just in case": self-made noise is itself a new fingerprint
   (`EVAL-selfbuild-engine.md` (3)); turning features off (e.g. GMP) is a tell too.
3. Prefer prefs / `settings/` / launcher config over C++ when they can do the job (no rebuild, no merge pain).
4. Every patch passes `ks/pipeline.sh`: bundle-check (only declared entries differ), fp-check (only declared fields
   differ), build-tester failure set unchanged, outbound destinations unchanged, VM checks.
5. On an upstream update (`docs/ks/UPSTREAM-SYNC.md`) every ks patch must still apply with `make dir`; a rejected
   one is rebased with `ks/new-patch.sh` (begin on the new tree, redo the edit, `KS_NUM=NNN`).
