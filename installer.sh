#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/vps-monitor"
RAW="https://raw.githubusercontent.com/ejaywattapak/vpsmonitor/main"
INSTALLER_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

CYAN='\033[1;36m'; GREEN='\033[1;32m'; RED='\033[1;31m'
YELLOW='\033[1;33m'; WHITE='\033[1;37m'; RESET='\033[0m'

cleanup() {
    # Remove only the temporary installer downloaded to run this installation.
    # Never remove the installed application/configuration.
    if [[ -n "${INSTALLER_PATH:-}" && -f "$INSTALLER_PATH" && "$INSTALLER_PATH" != "$BASE/installer.sh" ]]; then
        rm -f -- "$INSTALLER_PATH"
    fi
    clear 2>/dev/null || true
}
trap cleanup EXIT

die() {
    echo -e "${RED}✗ $1${RESET}"
    exit 1
}

[[ $EUID -eq 0 ]] || die "Run this installer as root."
command -v curl >/dev/null || {
    apt-get update -y
    apt-get install -y curl
}
command -v python3 >/dev/null || {
    apt-get update -y
    apt-get install -y python3
}
command -v ping >/dev/null || {
    apt-get update -y
    apt-get install -y iputils-ping
}
command -v wget >/dev/null || {
    apt-get update -y
    apt-get install -y wget
}

clear
echo -e "${CYAN}"
cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║                 EJ-VPS MONITOR                          ║
║                    INSTALLER                            ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "${CYAN}Installing directly from GitHub...${RESET}"
echo

echo -e "${CYAN}[1/7] Checking GitHub files...${RESET}"
for f in menu.sh monitor.sh telegram.sh servers.conf.example; do
    curl -fsSI --max-time 15 "$RAW/$f" >/dev/null || die "Cannot access GitHub file: $f"
done
echo -e "${GREEN}✓ GitHub repository reachable${RESET}"

echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗"
echo -e "║                 TELEGRAM BOT TOKEN                     ║"
echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
cat <<'EOF'
HOW TO GET BOT TOKEN

1. Open Telegram.
2. Search @BotFather.
3. Send /newbot.
4. Follow the instructions.
5. Copy the Bot Token.

Example:
123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Keep this token private.
EOF
echo
read -rp "Press ENTER to continue..." _

while true; do
    echo
    read -rsp "Telegram Bot Token: " BOT_TOKEN
    echo
    [[ -n "$BOT_TOKEN" ]] || { echo -e "${RED}✗ Token cannot be empty.${RESET}"; continue; }

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

1. Open your VPS Monitor bot.
2. Send /start.
3. Open:

https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates

4. Find:

"chat":{"id":123456789

5. The number after "id" is your Chat ID.

Example:
8474044977
EOF
echo
read -rp "Press ENTER to continue..." _

while true; do
    echo
    read -rp "Telegram Chat ID: " CHAT_ID
    [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]] || {
        echo -e "${RED}✗ Chat ID must be numeric.${RESET}"
        continue
    }

    TEST="$(curl -fsS --max-time 10 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=🚀 EJ-VPS Monitor installer test: Telegram is connected." \
        2>/dev/null || true)"

    if echo "$TEST" | python3 -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if d.get("ok") else 1)' 2>/dev/null; then
        echo -e "${GREEN}✓ Chat ID valid. Test message sent.${RESET}"
        break
    fi
    echo -e "${RED}✗ Could not send to this Chat ID. Send /start first and verify the ID.${RESET}"
done

echo
echo -e "${CYAN}[3/7] Creating installation directory...${RESET}"
mkdir -p "$BASE"
chmod 700 "$BASE"

echo -e "${CYAN}[4/7] Downloading application files from GitHub...${RESET}"
download() {
    local file="$1"
    echo -e "  ${CYAN}→${RESET} $file"
    curl -fsSL --retry 3 --max-time 30 "$RAW/$file" -o "$BASE/$file"
    chmod 700 "$BASE/$file"
}
download menu.sh
download monitor.sh
download telegram.sh
download servers.conf.example

# Create local configuration; this is intentionally never downloaded from GitHub.
cat > "$BASE/config.sh" <<EOF
BOT_TOKEN='$BOT_TOKEN'
CHAT_ID='$CHAT_ID'
CHECK_INTERVAL=30
EOF
chmod 700 "$BASE/config.sh"

# Create the local VPS database only if it does not already exist.
if [[ ! -f "$BASE/servers.conf" ]]; then
    cat > "$BASE/servers.conf" <<'EOF'
# NAME|HOST|PORT|METHOD
EOF
    chmod 600 "$BASE/servers.conf"
fi

echo -e "${GREEN}✓ Application files downloaded from GitHub${RESET}"

echo -e "${CYAN}[5/7] Installing systemd service...${RESET}"
cat > /etc/systemd/system/vps-monitor.service <<EOF
[Unit]
Description=EJ-VPS Telegram Monitor
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

echo -e "${GREEN}✓ Service installed and started${RESET}"

echo -e "${CYAN}[6/7] Installing SSH menu command...${RESET}"
ln -sf "$BASE/menu.sh" /usr/local/bin/vps
chmod +x /usr/local/bin/vps

# Remove old auto-menu block if present, then add the current one.
if [[ -f /root/.bashrc ]]; then
    sed -i '/# EJ-VPS-MONITOR-AUTO-MENU/,/# END-EJ-VPS-MONITOR-AUTO-MENU/d' /root/.bashrc
fi
cat >> /root/.bashrc <<'EOF'

# EJ-VPS-MONITOR-AUTO-MENU
if [ -t 1 ] && [ -x /usr/local/bin/vps ] && [ -z "$EJ_VPS_MONITOR_MENU" ]; then
  export EJ_VPS_MONITOR_MENU=1
  /usr/local/bin/vps
fi
# END-EJ-VPS-MONITOR-AUTO-MENU
EOF

echo -e "${CYAN}[7/7] Final test...${RESET}"
"$BASE/telegram.sh" send "🚀 EJ-VPS MONITOR STARTED

🖥 Server: $(hostname)
🟢 Status: ONLINE
📡 Telegram: Connected" >/dev/null 2>&1 || true

# Make sure no installer copy is left in the current directory/root home.
if [[ "$INSTALLER_PATH" != "$BASE/installer.sh" ]]; then
    rm -f -- "$INSTALLER_PATH"
fi

echo
echo -e "${GREEN}"
cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║              INSTALLATION COMPLETE                     ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"
echo -e "${CYAN}Menu:${RESET}      vps"
echo -e "${CYAN}Config:${RESET}    $BASE/config.sh"
echo -e "${CYAN}VPS list:${RESET}  $BASE/servers.conf"
echo -e "${CYAN}Service:${RESET}   systemctl status vps-monitor"
echo -e "${CYAN}Logs:${RESET}      journalctl -u vps-monitor -f"
echo
echo -e "${GREEN}Temporary installer file will be removed automatically.${RESET}"
echo -e "${YELLOW}Note: installed shell scripts remain in $BASE because the monitor needs them to run.${RESET}"
sleep 2
