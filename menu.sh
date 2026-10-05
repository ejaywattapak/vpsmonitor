#!/usr/bin/env bash
set -u

BASE="/opt/vps-monitor"
source "$BASE/config.sh"

CYAN='\033[1;36m'; CYAN2='\033[0;36m'; GREEN='\033[1;32m'
RED='\033[1;31m'; YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'
WHITE='\033[1;37m'; BLUE='\033[1;34m'; RESET='\033[0m'
DIM='\033[2m'

pause() { echo; read -rp "  Press ENTER to continue..." _; }

check() {
  local host="$1" port="$2" method="$3"
  if [[ "$method" == "ping" ]]; then
    ping -c 1 -W 3 "$host" >/dev/null 2>&1
  else
    timeout 5 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1
  fi
}

show_status() {
  local online=0 down=0 n=0
  echo
  echo -e "${CYAN}╭──────────────────────────────────────────────────────────╮${RESET}"
  echo -e "${CYAN}│${WHITE}                  REGISTERED VPS                       ${CYAN}│${RESET}"
  echo -e "${CYAN}╰──────────────────────────────────────────────────────────╯${RESET}"
  echo
  printf "  ${CYAN}%-3s %-22s %-18s %-12s${RESET}\n" "#" "NAME" "IP ADDRESS" "STATUS"
  echo -e "  ${CYAN}────────────────────────────────────────────────────────${RESET}"

  while IFS='|' read -r name host port method; do
    [[ -z "${name// }" || "$name" == \#* ]] && continue
    n=$((n+1))
    if check "$host" "$port" "$method"; then
      status="${GREEN}🟢 ONLINE${RESET}"
      online=$((online+1))
    else
      status="${RED}🔴 DOWN${RESET}"
      down=$((down+1))
    fi
    printf "  ${CYAN}%-3s${RESET} %-22s %-18s %b\n" "$n" "$name" "$host" "$status"
  done < "$BASE/servers.conf"

  echo -e "  ${CYAN}────────────────────────────────────────────────────────${RESET}"
  echo -e "  ${GREEN}🟢 ONLINE: $online${RESET}    ${RED}🔴 DOWN: $down${RESET}    ${CYAN}TOTAL: $n${RESET}"
  echo
}

telegram_status() {
  "$BASE/telegram.sh" send "$(status_text)"
}

status_text() {
  local online=0 down=0 n=0 text="📊 VPS STATUS

🖥 Monitor: $(hostname)

"
  while IFS='|' read -r name host port method; do
    [[ -z "${name// }" || "$name" == \#* ]] && continue
    n=$((n+1))
    if check "$host" "$port" "$method"; then
      online=$((online+1))
      text+="🟢 $n. $name
   🌐 $host

"
    else
      down=$((down+1))
      text+="🔴 $n. $name
   🌐 $host
   ❌ DOWN

"
    fi
  done < "$BASE/servers.conf"
  text+="━━━━━━━━━━━━━━━━━━━━
🟢 ONLINE: $online
🔴 DOWN: $down"
  printf '%s' "$text"
}

add_vps() {
  echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════╗"
  echo -e "║                    ADD VPS                             ║"
  echo -e "╚══════════════════════════════════════════════════════════╝${RESET}\n"

  read -rp "  VPS Name   : " name
  read -rp "  IP Address : " host
  echo -e "\n  ${CYAN}[1] PING${RESET}\n  ${CYAN}[2] TCP PORT${RESET}"
  read -rp "  Monitor    : " type

  if [[ "$type" == "1" ]]; then
    method="ping"; port=0
  elif [[ "$type" == "2" ]]; then
    method="tcp"
    read -rp "  TCP Port   : " port
  else
    echo -e "${RED}  Invalid choice.${RESET}"; pause; return
  fi

  echo
  if check "$host" "$port" "$method"; then
    echo -e "${GREEN}  🟢 ONLINE${RESET}"
  else
    echo -e "${RED}  🔴 DOWN${RESET}"
    read -rp "  Add anyway? [y/N]: " c
    [[ "${c,,}" == "y" ]] || return
  fi

  echo "${name}|${host}|${port}|${method}" >> "$BASE/servers.conf"
  echo -e "${GREEN}  ✓ VPS added.${RESET}"
  "$BASE/telegram.sh" send "➕ VPS ADDED

🖥 $name
🌐 $host
📡 ${method^^}${port:+:$port}" || true
  pause
}

remove_vps() {
  mapfile -t rows < <(grep -vE '^[[:space:]]*(#|$)' "$BASE/servers.conf")
  ((${#rows[@]})) || { echo "  No VPS."; pause; return; }

  echo -e "\n${CYAN}REGISTERED VPS${RESET}\n"
  for i in "${!rows[@]}"; do IFS='|' read -r name host port method <<< "${rows[$i]}"; echo "  [$((i+1))] $name - $host"; done
  echo
  read -rp "  Remove [0=cancel]: " n
  [[ "$n" =~ ^[0-9]+$ && "$n" != 0 ]] || return
  idx=$((n-1)); ((idx < ${#rows[@]})) || return
  IFS='|' read -r name host port method <<< "${rows[$idx]}"
  read -rp "  Remove $name? [y/N]: " c
  [[ "${c,,}" == "y" ]] || return
  printf '%s\n' "${rows[@]}" | sed "${n}d" > "$BASE/servers.conf"
  echo -e "${GREEN}  ✓ Removed $name${RESET}"
  "$BASE/telegram.sh" send "➖ VPS REMOVED

🖥 $name
🌐 $host" || true
  pause
}

rename_vps() {
  mapfile -t rows < <(grep -vE '^[[:space:]]*(#|$)' "$BASE/servers.conf")
  ((${#rows[@]})) || { echo "  No VPS."; pause; return; }

  echo -e "\n${CYAN}REGISTERED VPS${RESET}\n"
  for i in "${!rows[@]}"; do IFS='|' read -r name host port method <<< "${rows[$i]}"; echo "  [$((i+1))] $name - $host"; done
  echo
  read -rp "  Rename [0=cancel]: " n
  [[ "$n" =~ ^[0-9]+$ && "$n" != 0 ]] || return
  idx=$((n-1)); ((idx < ${#rows[@]})) || return
  IFS='|' read -r old host port method <<< "${rows[$idx]}"
  read -rp "  New name [$old]: " new
  [[ -n "$new" ]] || return
  rows[$idx]="$new|$host|$port|$method"
  printf '%s\n' "${rows[@]}" > "$BASE/servers.conf"
  echo -e "${GREEN}  ✓ $old → $new${RESET}"
  "$BASE/telegram.sh" send "✏️ VPS RENAMED

$old → $new" || true
  pause
}

while true; do
  clear
  echo -e "${CYAN}"
  cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║              V P S   M O N I T O R                     ║
║                                                          ║
║                 M A N A G E R                           ║
║                                                          ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║   [ 1 ]  SHOW VPS              [ 4 ]  RENAME VPS        ║
║   [ 2 ]  ADD VPS               [ 5 ]  TELEGRAM STATUS   ║
║   [ 3 ]  REMOVE VPS            [ 0 ]  EXIT              ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
  echo -e "${RESET}"

  show_status

  echo -e "${CYAN}  Select option ${WHITE}[0-5]${CYAN}:${RESET} \c"
  read -r choice

  case "$choice" in
    1) clear; show_status; pause ;;
    2) add_vps ;;
    3) remove_vps ;;
    4) rename_vps ;;
    5) "$BASE/telegram.sh" send "$(status_text)" && echo -e "${GREEN}  ✓ Telegram updated.${RESET}" || echo -e "${RED}  ✗ Telegram failed.${RESET}"; pause ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}  ✗ Invalid option.${RESET}"; sleep 1 ;;
  esac
done
