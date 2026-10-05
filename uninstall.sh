#!/usr/bin/env bash
set -e
BASE="/opt/vps-monitor"
CYAN='\033[1;36m'; RED='\033[1;31m'; GREEN='\033[1;32m'; RESET='\033[0m'

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }

echo -e "${CYAN}VPS Telegram Monitor Uninstaller${RESET}"
read -rp "Remove VPS Monitor completely? [y/N]: " c
[[ "${c,,}" == "y" ]] || exit 0

systemctl disable --now vps-monitor 2>/dev/null || true
rm -f /etc/systemd/system/vps-monitor.service
systemctl daemon-reload
rm -f /usr/local/bin/vps

if [[ -f /root/.bashrc ]]; then
  sed -i '/# VPS-MONITOR-AUTO-MENU/,/# END VPS-MONITOR-AUTO-MENU/d' /root/.bashrc
fi

rm -rf "$BASE"

echo -e "${GREEN}✓ VPS Monitor removed.${RESET}"
