#!/bin/bash
# Run the repo's build-tester (8 fingerprint profiles, graded per check) against an unpacked bundle.
# Runs INSIDE the container as builder:  CFCMD='/opt/ks/build-tester.sh <label> <bundle-dir>' cfrun shell
# Result: /work/dist/bt-<label>/build-tester-result.json (+ results/)
set -eo pipefail
LABEL=${1:?label}; BUNDLE=${2:?bundle dir}
cd /work/camoufox
# v156 layout: build-tester/ + scripts/pin-fpgen-model.py at the root; v158: browser/tests/build-tester + python/scripts/
BT=build-tester; [ -d browser/tests/build-tester ] && BT=browser/tests/build-tester
PIN=scripts/pin-fpgen-model.py; [ -f python/scripts/pin-fpgen-model.py ] && PIN=python/scripts/pin-fpgen-model.py
V=/work/camoufox/.ks-venv
[ -x $V/bin/python ] || python3 -m venv $V
. $V/bin/activate
pip install -q -r ci/requirements.txt
( cd "$BT" && npm install --no-audit --no-fund --loglevel=error && pip install -q -r requirements.txt )
python3 "$PIN"
export CI_WORK_DIR=/work/dist/bt-$LABEL
mkdir -p "$CI_WORK_DIR"
set +e
xvfb-run -a python3 -m ci.run_build_tester --binary "$BUNDLE/camoufox-bin"
echo "build-tester exit=$?"
