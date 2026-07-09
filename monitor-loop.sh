#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/nokyc}"
STATE_FILE="${STATE_FILE:-$BASE_DIR/last_offers.txt}"
LAST_OFFERS=""
if [ -f "$STATE_FILE" ]; then
  LAST_OFFERS=$(cat "$STATE_FILE")
fi
NOTIFY_SCRIPT="${NOTIFY_SCRIPT:-$BASE_DIR/notify.sh}"
FIAT="${FIAT:-huf}"
ORDER_TYPE="${ORDER_TYPE:-sell}"
DEVIATION="${DEVIATION:-50}"
EXCHANGE="${EXCHANGE:-robosats}"
SLEEP_SECONDS="${SLEEP_SECONDS:-600}"

while true; do
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M')
  echo "=== $TIMESTAMP ==="
  
  cd "$BASE_DIR" && source venv/bin/activate
  OUTPUT=$(timeout 300 python ./nokyc.py -e "$EXCHANGE" -f "$FIAT" -t "$ORDER_TYPE" -d "$DEVIATION" 2>&1)
  
  # Extract offer lines (skip spinner/error lines)
  OFFERS=$(echo "$OUTPUT" | grep -E "^Robosats")
  # Fingerprint: premium, HUF amounts, method only (ignore BTC amounts which fluctuate with price)
  OFFERS_FP=$(echo "$OFFERS" | awk '{s=$3" "$6" "$7; for(i=8;i<=NF;i++) s=s" "$i; print s}' | sort)
  
  if [ -n "$OFFERS" ]; then
    echo "$OFFERS"
    
    # Only notify if offer fingerprint changed (ignore price changes)
    if [ "$OFFERS_FP" != "$LAST_OFFERS" ]; then
      # Build message
      MSG="🟠 Aktív RoboSats HUF offer(ek) - $TIMESTAMP"$'\n\n'
      while IFS= read -r line; do
        # Parse: Exchange Price Dif BTCmin BTCmax Min Max Method...
        PRICE=$(echo "$line" | sed 's/^Robosats//' | awk '{print $1}')
        DIF=$(echo "$line" | awk '{print $3}')
        BTCMIN=$(echo "$line" | awk '{print $4}')
        BTCMAX=$(echo "$line" | awk '{print $5}')
        HUFMIN=$(echo "$line" | awk '{print $6}')
        HUFMAX=$(echo "$line" | awk '{print $7}')
        METHOD=$(echo "$line" | awk '{for(i=8;i<=NF;i++) printf $i" "; print ""}')
        MSG+="Ár: ${PRICE} HUF/BTC"$'\n'
        MSG+="BTC: ${BTCMIN}-${BTCMAX} (~${HUFMIN}-${HUFMAX} HUF)"$'\n'
        MSG+="Fizetés: ${METHOD}"$'\n'
        MSG+="Prémium: ${DIF}"$'\n\n'
      done <<< "$OFFERS"
      
      bash "$NOTIFY_SCRIPT" "$MSG" "new"
      echo "[NOTIFIED]"
      LAST_OFFERS="$OFFERS_FP"
      echo "$OFFERS_FP" > "$STATE_FILE"
    else
      echo "[no change]"
      # Re-pin if offer exists but got unpinned due to earlier tor error
      PINNED_MSG_FILE="$BASE_DIR/pinned_msg_id.txt"
      if [ ! -f "$PINNED_MSG_FILE" ]; then
        # Re-send and pin the current offers
        MSG="🟠 Aktív RoboSats HUF offer(ek) - $TIMESTAMP"$'\n\n'
        while IFS= read -r line; do
          PRICE=$(echo "$line" | sed 's/^Robosats//' | awk '{print $1}')
          DIF=$(echo "$line" | awk '{print $3}')
          BTCMIN=$(echo "$line" | awk '{print $4}')
          BTCMAX=$(echo "$line" | awk '{print $5}')
          HUFMIN=$(echo "$line" | awk '{print $6}')
          HUFMAX=$(echo "$line" | awk '{print $7}')
          METHOD=$(echo "$line" | awk '{for(i=8;i<=NF;i++) printf $i" "; print ""}')
          MSG+="Ár: ${PRICE} HUF/BTC"$'\n'
          MSG+="BTC: ${BTCMIN}-${BTCMAX} (~${HUFMIN}-${HUFMAX} HUF)"$'\n'
          MSG+="Fizetés: ${METHOD}"$'\n'
          MSG+="Prémium: ${DIF}"$'\n\n'
        done <<< "$OFFERS"
        bash "$NOTIFY_SCRIPT" "$MSG" "new"
        echo "[re-pinned after tor recovery]"
      fi
    fi
  else
    # Distinguish Tor/script failure from genuine "no offers"
    # Key: if the output contains the results table header, the query succeeded
    # even if some individual .onion nodes timed out along the way
    if echo "$OUTPUT" | grep -qE "(BTC sell offers|BTC buy offers|Price:)"; then
      echo "[no offers - query succeeded]"
      if [ -n "$LAST_OFFERS" ]; then
        bash "$NOTIFY_SCRIPT" "⚪ A RoboSats HUF offer(ek) eltűntek ($TIMESTAMP)" "gone"
        LAST_OFFERS=""
        rm -f "$STATE_FILE"
        echo "[NOTIFIED: offers gone]"
      fi
    elif echo "$OUTPUT" | grep -qiE "Failed to connect|make sure you are running TOR|Traceback|timed out|ConnectionError"; then
      echo "[tor/script error - skipping]"
    else
      echo "[no offers - query succeeded]"
      if [ -n "$LAST_OFFERS" ]; then
        bash "$NOTIFY_SCRIPT" "⚪ A RoboSats HUF offer(ek) eltűntek ($TIMESTAMP)" "gone"
        LAST_OFFERS=""
        rm -f "$STATE_FILE"
        echo "[NOTIFIED: offers gone]"
      fi
    fi
  fi
  
  echo ""
  sleep "$SLEEP_SECONDS"
done
