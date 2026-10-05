#!/usr/bin/env bash
set -e

BASE="/opt/vps-monitor"
CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; MAGENTA='\033[1;35m'; WHITE='\033[1;37m'; RESET='\033[0m'

banner() {
  clear
  echo -e "${CYAN}"
  cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║              VPS TELEGRAM MONITOR                       ║
║                    INSTALLER                             ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
  echo -e "${RESET}"
}

die() { echo -e "${RED}✗ $1${RESET}"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run this installer as root."

banner
echo -e "${CYAN}[1/7] Checking operating system...${RESET}"
command -v systemctl >/dev/null || die "systemd is required."
command -v python3 >/dev/null || {
  echo -e "${YELLOW}Installing Python3...${RESET}"
  apt-get update -y
  apt-get install -y python3 iputils-ping curl
}
echo -e "${GREEN}✓ OS/dependencies OK${RESET}"

echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗"
echo -e "║                 TELEGRAM BOT TOKEN                     ║"
echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
cat <<'EOF'
HOW TO GET BOT TOKEN

  1. Open Telegram.
  2. Search for @BotFather.
  3. Open the official BotFather.
  4. Send /newbot
  5. Follow the instructions.
  6. Copy the Bot Token given by BotFather.

Example:
  123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

WARNING:
  Keep your Bot Token private.
  Never upload it to GitHub.
EOF
echo
read -rp "Press ENTER to continue..." _

while true; do
  echo
  read -rsp "Telegram Bot Token: " BOT_TOKEN
  echo
  [[ -n "$BOT_TOKEN" ]] || { echo -e "${RED}Token cannot be empty.${RESET}"; continue; }

  RESULT="$(curl -fsS --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null || true)"
  if echo "$RESULT" | python3 -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if d.get("ok") else 1)' 2>/dev/null; then
    BOT_NAME="$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["username"])')"
    echo -e "${GREEN}✓ Bot token valid: @${BOT_NAME}${RESET}"
    break
  fi
  echo -e "${RED}✗ Invalid Bot Token. Try again.${RESET}"
done

clear
echo -e "${CYAN}"
cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                    TELEGRAM CHAT ID                     ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
cat <<'EOF'
HOW TO GET CHAT ID

  1. Open your VPS Monitor bot in Telegram.
  2. Send /start to the bot.
  3. Then open this URL in your browser:

     https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates

  4. Find:
       "chat":{"id":123456789

  5. The number after "id" is your Chat ID.

Example:
       8474044977

You can also use a Telegram ID bot to find your personal Chat ID.
EOF
echo
read -rp "Press ENTER to continue..." _

while true; do
  echo
  read -rp "Telegram Chat ID: " CHAT_ID
  [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]] || { echo -e "${RED}✗ Chat ID must be numeric.${RESET}"; continue; }

  TEST="$(curl -fsS --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=🚀 VPS Monitor installer test: Telegram configuration is working." 2>/dev/null || true)"

  if echo "$TEST" | python3 -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if d.get("ok") else 1)' 2>/dev/null; then
    echo -e "${GREEN}✓ Chat ID valid. Test message sent.${RESET}"
    break
  fi
  echo -e "${RED}✗ Could not send to this Chat ID. Send /start to your bot and check the ID.${RESET}"
done

echo
echo -e "${CYAN}[3/7] Installing VPS Monitor files...${RESET}"
mkdir -p "$BASE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/menu.sh" "$BASE/menu.sh"
cp "$SCRIPT_DIR/monitor.sh" "$BASE/monitor.sh"
cp "$SCRIPT_DIR/telegram.sh" "$BASE/telegram.sh"
cp "$SCRIPT_DIR/config.sh.example" "$BASE/config.sh"
cp "$SCRIPT_DIR/servers.conf.example" "$BASE/servers.conf"

cat > "$BASE/config.sh" <<EOF
BOT_TOKEN='$BOT_TOKEN'
CHAT_ID='$CHAT_ID'
CHECK_INTERVAL=30
EOF

chmod 700 "$BASE"
chmod 700 "$BASE/config.sh"
chmod +x "$BASE/"*.sh

echo -e "${GREEN}✓ Files installed${RESET}"

echo -e "${CYAN}[4/7] Creating systemd service...${RESET}"
cat > /etc/systemd/system/vps-monitor.service <<EOF
[Unit]
Description=VPS Telegram Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash $BASE/monitor.sh
WorkingDirectory=$BASE
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vps-monitor >/dev/null
systemctl restart vps-monitor

echo -e "${GREEN}✓ vps-monitor.service enabled${RESET}"

echo -e "${CYAN}[5/7] Creating SSH command...${RESET}"
ln -sf "$BASE/menu.sh" /usr/local/bin/vps
chmod +x /usr/local/bin/vps

echo -e "${CYAN}[6/7] Configuring root SSH auto-menu...${RESET}"
touch /root/.bashrc
if ! grep -q 'VPS-MONITOR-AUTO-MENU' /root/.bashrc; then
cat >> /root/.bashrc <<'EOF'

# VPS-MONITOR-AUTO-MENU
if [ -t 1 ] && [ -x /usr/local/bin/vps ] && [ -z "$VPS_MONITOR_MENU" ]; then
  export VPS_MONITOR_MENU=1
  /usr/local/bin/vps
fi
# END VPS-MONITOR-AUTO-MENU
EOF
fi

echo -e "${CYAN}[7/7] Final Telegram test...${RESET}"
"$BASE/telegram.sh" send "✅ VPS Monitor installed successfully on $(hostname)." >/dev/null || true

echo
echo -e "${GREEN}"
cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                 INSTALLATION COMPLETE                   ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "${CYAN}SSH menu:${RESET}       vps"
echo -e "${CYAN}Config:${RESET}          $BASE/config.sh"
echo -e "${CYAN}VPS list:${RESET}        $BASE/servers.conf"
echo -e "${CYAN}Service:${RESET}         systemctl status vps-monitor"
echo -e "${CYAN}Logs:${RESET}            journalctl -u vps-monitor -f"
echo
echo -e "${GREEN}Telegram commands:${RESET} /status  /add  /remove  /rename"
echo
