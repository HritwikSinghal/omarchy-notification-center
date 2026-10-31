#!/usr/bin/env bash
# Unit tests: History.js, Shortcuts.js and Images.js under node's test runner,
# the capture helper under python's unittest. No desktop, bus or network needed.
# The end-to-end run on a hidden desktop is tests/e2e/run.sh (docs/TESTING.md).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== JS (node --test)"
node --test tests/js/

echo "== Python (unittest)"
python3 -I -m unittest discover -s tests/py -v
