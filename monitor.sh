#!/usr/bin/env bash
set -u

BASE="/opt/vps-monitor"
source "$BASE/config.sh"

declare -A STATE

send() {
  local text="$1"
  curl -fsS --max-time 15 \
    "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${text}" >/dev/null 2>&1 || true
}

check_ping() {
  ping -c 1 -W 3 "$1" >/dev/null 2>&1
}

check_tcp() {
  timeout 5 bash -c "</dev/tcp/$1/$2" >/dev/null 2>&1
}

check_server() {
  local host="$1" port="$2" method="$3"
  if [[ "$method" == "ping" ]]; then
    check_ping "$host"
  else
    check_tcp "$host" "$port"
  fi
}

echo "VPS Telegram Monitor started."

while true; do
  while IFS='|' read -r name host port method; do
    [[ -z "${name// }" || "$name" == \#* ]] && continue

    if check_server "$host" "$port" "$method"; then
      current="up"
    else
      current="down"
    fi

    key="$name|$host|$port|$method"
    previous="${STATE[$key]:-unknown}"
    STATE[$key]="$current"

    if [[ "$previous" == "up" && "$current" == "down" ]]; then
      send "🚨 VPS DOWN

🖥 Server: $name
🌐 Host: $host
📡 Method: ${method^^}${port:+${port:+:$port}}
❌ Connection failed"
    elif [[ "$previous" == "down" && "$current" == "up" ]]; then
      send "🟢 VPS RECOVERED

🖥 Server: $name
🌐 Host: $host
📡 Method: ${method^^}${port:+${port:+:$port}}
✅ Server is online again"
    fi
  done < "$BASE/servers.conf"

  sleep "${CHECK_INTERVAL:-30}"
done
