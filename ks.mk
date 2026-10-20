# ks.mk -- kurtaaaalove fork additions. The upstream Makefile is deliberately left untouched so that
# `source_digest` of a ks/base-* branch still equals the official release's manifest.json digest.
#
#   make -f ks.mk ks-help
#
# v156: Makefile/upstream.sh at the root; v158+: under browser/ (only version/release are needed here)
KS_BW := $(if $(wildcard browser/upstream.sh),browser,.)
include $(KS_BW)/upstream.sh

KS_TAG ?= v$(version)-$(release)
KS_UPSTREAM ?= daijro/camoufox
KS_TREE := /tmp/ks-digest-tree

.PHONY: ks-help ks-set-build ks-digest ks-verify-manifest ks-prepare ks-apply ks-build ks-package ks-all ks-kspatch ks-tree ks-pipeline ks-new-patch

ks-help:
	@echo "ks targets (build stages run inside the build container, see docs/ks/UPSTREAM-SYNC.md):"
	@echo "  ks-set-build KS_TAG=vX-beta.N  - write the release number of TAG into upstream.sh (working tree only)"
	@echo "  ks-digest                      - source_digest of the committed tree (git archive HEAD)"
	@echo "  ks-verify-manifest KS_TAG=...  - download TAG's manifest.json and compare commit + digest"
	@echo "  ks-prepare / ks-apply / ks-build / ks-package / ks-all / ks-kspatch - build stages (ks/container/ks-build.sh, inside the container)"
	@echo "host side:"
	@echo "  ks-pipeline [ARGS='--from bundle']  - ks/pipeline.sh: kspatch+build, package, gates, deploy VM :9376, VM checks"
	@echo "  ks-new-patch SLUG=<slug>            - ks/new-patch.sh <slug> (see patches/ks/README.md for begin/edit)"

ks-set-build:
	python3 -m ci.release set-build --tag $(KS_TAG)

# The digest is computed on the COMMITTED tree: build artifacts such as scripts/__pycache__ would change it.
ks-tree:
	@rm -rf $(KS_TREE) && mkdir -p $(KS_TREE) && git archive HEAD | tar -x -C $(KS_TREE)

ks-digest: ks-tree
	@python3 -c 'from pathlib import Path; from ci.browser_inputs import source_digest; print(source_digest(Path("$(KS_TREE)")))'

ks-verify-manifest: ks-tree
	@curl -fsSL https://github.com/$(KS_UPSTREAM)/releases/download/$(KS_TAG)/manifest.json -o /tmp/ks-manifest.json
	@python3 ks/verify/manifest-check.py /tmp/ks-manifest.json $(KS_TREE)

ks-prepare ks-apply ks-build ks-package ks-all ks-kspatch:
	bash ks/container/ks-build.sh $(subst ks-,,$@)

ks-pipeline:
	bash ks/pipeline.sh $(ARGS)

ks-new-patch:
	bash ks/new-patch.sh $(SLUG)
