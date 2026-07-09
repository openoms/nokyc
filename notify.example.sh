#!/usr/bin/env bash
set -euo pipefail

: "${TELEGRAM_BOT_TOKEN:?Set TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_DM_CHAT_ID:?Set TELEGRAM_DM_CHAT_ID}"
: "${TELEGRAM_GROUP_CHAT_ID:?Set TELEGRAM_GROUP_CHAT_ID}"
: "${TELEGRAM_TOPIC_ID:=}"

API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"
PINNED_MSG_FILE="${PINNED_MSG_FILE:-$HOME/nokyc/pinned_msg_id.txt}"

send_tg() {
  local chat_id="$1"
  local text="$2"
  local topic_id="${3:-}"

  if [ -n "$topic_id" ]; then
    curl -s -X POST "$API/sendMessage" \
      -d chat_id="$chat_id" \
      -d message_thread_id="$topic_id" \
      -d text="$text" \
      -d parse_mode="HTML"
  else
    curl -s -X POST "$API/sendMessage" \
      -d chat_id="$chat_id" \
      -d text="$text" \
      -d parse_mode="HTML"
  fi
}

pin_msg() {
  local chat_id="$1"
  local msg_id="$2"
  curl -s -X POST "$API/pinChatMessage" \
    -d chat_id="$chat_id" \
    -d message_id="$msg_id" \
    -d disable_notification=true >/dev/null 2>&1
}

unpin_msg() {
  local chat_id="$1"
  local msg_id="$2"
  curl -s -X POST "$API/unpinChatMessage" \
    -d chat_id="$chat_id" \
    -d message_id="$msg_id" >/dev/null 2>&1
}

delete_msg() {
  local chat_id="$1"
  local msg_id="$2"
  curl -s -X POST "$API/deleteMessage" \
    -d chat_id="$chat_id" \
    -d message_id="$msg_id" >/dev/null 2>&1
}

MSG="$1"
ACTION="${2:-new}"

send_tg "$TELEGRAM_DM_CHAT_ID" "$MSG" >/dev/null 2>&1
RESPONSE=$(send_tg "$TELEGRAM_GROUP_CHAT_ID" "$MSG" "$TELEGRAM_TOPIC_ID")
NEW_MSG_ID=$(echo "$RESPONSE" | jq -r '.result.message_id // empty')

if [ "$ACTION" = "new" ] && [ -n "$NEW_MSG_ID" ]; then
  if [ -f "$PINNED_MSG_FILE" ]; then
    OLD_MSG_ID=$(cat "$PINNED_MSG_FILE")
    unpin_msg "$TELEGRAM_GROUP_CHAT_ID" "$OLD_MSG_ID"
    delete_msg "$TELEGRAM_GROUP_CHAT_ID" "$OLD_MSG_ID"
  fi
  pin_msg "$TELEGRAM_GROUP_CHAT_ID" "$NEW_MSG_ID"
  echo "$NEW_MSG_ID" > "$PINNED_MSG_FILE"
  echo "[pinned: $NEW_MSG_ID]"
elif [ "$ACTION" = "gone" ] && [ -f "$PINNED_MSG_FILE" ]; then
  OLD_MSG_ID=$(cat "$PINNED_MSG_FILE")
  unpin_msg "$TELEGRAM_GROUP_CHAT_ID" "$OLD_MSG_ID"
  delete_msg "$TELEGRAM_GROUP_CHAT_ID" "$OLD_MSG_ID"
  rm -f "$PINNED_MSG_FILE"
  echo "[unpinned+deleted: $OLD_MSG_ID]"
fi
