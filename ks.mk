# ks.mk -- kurtaaaalove fork additions. The upstream Makefile is deliberately left untouched so that
# `source_digest` of a ks/base-* branch still equals the official release's manifest.json digest.
#
#   make -f ks.mk ks-help
#
include Makefile

KS_TAG ?= v$(version)-$(release)
KS_UPSTREAM ?= daijro/camoufox
KS_TREE := /tmp/ks-digest-tree

.PHONY: ks-help ks-set-build ks-digest ks-verify-manifest ks-prepare ks-build ks-package ks-all ks-tree

ks-help:
	@echo "ks targets (build stages run inside the build container, see docs/ks/UPSTREAM-SYNC.md):"
	@echo "  ks-set-build KS_TAG=vX-beta.N  - write the release number of TAG into upstream.sh (working tree only)"
	@echo "  ks-digest                      - source_digest of the committed tree (git archive HEAD)"
	@echo "  ks-verify-manifest KS_TAG=...  - download TAG's manifest.json and compare commit + digest"
	@echo "  ks-prepare / ks-build / ks-package / ks-all - linux x86_64 build stages (ks/container/ks-build.sh)"

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

ks-prepare ks-build ks-package ks-all:
	bash ks/container/ks-build.sh $(subst ks-,,$@)
