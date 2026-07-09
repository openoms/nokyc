#!/usr/bin/env bash
set -euo pipefail

cd ~/nokyc
source venv/bin/activate
FIAT="${FIAT:-huf}"
ORDER_TYPE="${ORDER_TYPE:-sell}"
DEVIATION="${DEVIATION:-15}"
timeout 120 python ./nokyc.py -e robosats -f "$FIAT" -t "$ORDER_TYPE" -d "$DEVIATION" 2>&1 | grep -v "^Gathering"
