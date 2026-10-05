#!/usr/bin/env bash
set -e
BASE="/opt/vps-monitor"
source "$BASE/config.sh"

api() {
  local method="$1"; shift
  curl -fsS --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/${method}" "$@"
}

send() {
  local text="$1"
  api sendMessage \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null
}

case "${1:-}" in
  send)
    shift
    send "$*"
    ;;
  *)
    echo "Usage: telegram.sh send 'message'"
    exit 1
    ;;
esac
