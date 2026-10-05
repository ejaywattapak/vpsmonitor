#!/usr/bin/env bash
set -euo pipefail

BASE="/opt/vps-monitor"
RAW="https://raw.githubusercontent.com/ejaywattapak/vpsmonitor/main"
INSTALLER_PATH="$(readlink -f "${BASH_SOURCE[0]}")"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

die() {
    echo -e "${RED}✗ $1${RESET}"
    exit 1
}

cleanup() {
    # Delete only the temporary installer downloaded from GitHub.
    # Installed monitor files and credentials are kept.
    if [[ -n "${INSTALLER_PATH:-}" && -f "$INSTALLER_PATH" && "$INSTALLER_PATH" != "$BASE/installer.sh" ]]; then
        rm -f -- "$INSTALLER_PATH"
    fi
}
trap cleanup EXIT

[[ $EUID -eq 0 ]] || die "Run this installer as root."

echo -e "${CYAN}Checking required packages...${RESET}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget python3 iputils-ping

clear
echo -e "${CYAN}"
cat <<'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║                    EJ-VPS MONITOR                       ║
║                      INSTALLER                          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${RESET}"

echo -e "${CYAN}[1/7] Checking GitHub files...${RESET}"
for f in menu.sh monitor.sh telegram.sh servers.conf.example; do
    curl -fsSL --max-time 15 -o /dev/null "$RAW/$f" || die "Cannot access GitHub file: $f"
done
echo -e "${GREEN}✓ GitHub repository reachable${RESET}"

echo
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗"
echo -e "║                 TELEGRAM BOT TOKEN                      ║"
echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
cat <<'EOF'
HOW TO GET BOT TOKEN

1. Open Telegram.
2. Search @BotFather.
3. Open the official BotFather.
4. Send /newbot.
5. Follow the instructions.
6. Copy the Bot Token given by BotFather.

Example:
123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

Keep this token private.
EOF
echo
read -rp "Press ENTER to continue..." _

while true; do
    echo
    read -rsp "Enter Telegram Bot Token: " BOT_TOKEN
    echo

    [[ -n "$BOT_TOKEN" ]] || {
        echo -e "${RED}✗ Token cannot be empty.${RESET}"
        continue
    }

    RESULT="$(curl -fsS --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null || true)"

    if echo "$RESULT" | python3 -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if d.get("ok") else 1)' 2>/dev/null; then
        BOT_NAME="$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["username"])')"
        echo -e "${GREEN}✓ Bot Token valid: @${BOT_NAME}${RESET}"
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
3. Open this URL in your browser:

https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates

4. Find:

"chat":{"id":123456789

5. The number after "id" is your Telegram Chat ID.

Example:
8474044977

You can also use a Telegram ID bot to find your personal Chat ID.
EOF

echo
read -rp "Press ENTER to continue..." _

while true; do
    echo
    read -rp "Enter Telegram Chat ID: " CHAT_ID

    [[ "$CHAT_ID" =~ ^-?[0-9]+$ ]] || {
        echo -e "${RED}✗ Chat ID must be numeric.${RESET}"
        continue
    }

    TEST="$(curl -fsS --max-time 10 -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=🚀 EJ-VPS Monitor installer test: Telegram is connected." \
        2>/dev/null || true)"

    if echo "$TEST" | python3 -c 'import sys,json; d=json.load(sys.stdin); raise SystemExit(0 if d.get("ok") else 1)' 2>/dev/null; then
        echo -e "${GREEN}✓ Chat ID valid. Test message sent.${RESET}"
        break
    fi

    echo -e "${RED}✗ Cannot send to this Chat ID. Send /start first and verify the ID.${RESET}"
done

echo
echo -e "${CYAN}[3/7] Creating installation directory...${RESET}"
mkdir -p "$BASE"
chmod 700 "$BASE"

echo -e "${CYAN}[4/7] Downloading application files from GitHub...${RESET}"

download_file() {
    local file="$1"
    echo -e "  ${CYAN}→${RESET} $file"
    curl -fsSL --retry 3 --max-time 30 "$RAW/$file" -o "$BASE/$file"
    chmod 700 "$BASE/$file"
}

download_file menu.sh
download_file monitor.sh
download_file telegram.sh

# Example only; the real server list is kept locally and is never overwritten.
download_file servers.conf.example

# Local configuration. Real token/chat ID never goes to GitHub.
cat > "$BASE/config.sh" <<EOF
BOT_TOKEN='$BOT_TOKEN'
CHAT_ID='$CHAT_ID'
CHECK_INTERVAL=30
EOF
chmod 600 "$BASE/config.sh"

# Preserve an existing VPS list during reinstall/update.
if [[ ! -f "$BASE/servers.conf" ]]; then
    cat > "$BASE/servers.conf" <<'EOF'
# NAME|HOST|PORT|METHOD
EOF
fi
chmod 600 "$BASE/servers.conf"

echo -e "${GREEN}✓ Files installed from GitHub${RESET}"

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

echo -e "${GREEN}✓ VPS Monitor service started${RESET}"

echo -e "${CYAN}[6/7] Installing SSH auto-menu...${RESET}"

ln -sf "$BASE/menu.sh" /usr/local/bin/vps
chmod +x /usr/local/bin/vps

# Remove our previous auto-menu blocks, if any.
if [[ -f /root/.bashrc ]]; then
    sed -i '/# EJ-VPS-MONITOR-AUTO-MENU/,/# END-EJ-VPS-MONITOR-AUTO-MENU/d' /root/.bashrc
fi

# Preserve existing /root/.bashrc and append only our marked block.
cat >> /root/.bashrc <<'EOF'

# EJ-VPS-MONITOR-AUTO-MENU
if [ -t 0 ] && [ -t 1 ] && [ -x /usr/local/bin/vps ] && [ -z "${EJ_VPS_MONITOR_MENU:-}" ]; then
    export EJ_VPS_MONITOR_MENU=1
    clear
    /usr/local/bin/vps
fi
# END-EJ-VPS-MONITOR-AUTO-MENU
EOF

# SSH login shells may read .bash_profile instead of .bashrc.
# Preserve an existing .bash_profile and add a marked loader.
touch /root/.bash_profile
sed -i '/# EJ-VPS-MONITOR-BASH-PROFILE/,/# END-EJ-VPS-MONITOR-BASH-PROFILE/d' /root/.bash_profile

cat >> /root/.bash_profile <<'EOF'

# EJ-VPS-MONITOR-BASH-PROFILE
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
# END-EJ-VPS-MONITOR-BASH-PROFILE
EOF

echo -e "${GREEN}✓ SSH auto-menu enabled${RESET}"

echo -e "${CYAN}[7/7] Sending Telegram startup alert...${RESET}"
"$BASE/telegram.sh" send "🚨 VPS MONITOR STARTED

🖥 Monitor: $(hostname)
🟢 Status: ONLINE
📡 Telegram: Connected" >/dev/null 2>&1 || true

# Remove the temporary installer BEFORE opening the menu.
# The installed scripts/config remain in /opt/vps-monitor.
if [[ -f "$INSTALLER_PATH" && "$INSTALLER_PATH" != "$BASE/installer.sh" ]]; then
    rm -f -- "$INSTALLER_PATH"
fi

trap - EXIT

clear
echo -e "${GREEN}Installation complete. Opening VPS menu...${RESET}"
sleep 1
clear

# Start the menu immediately after installation.
# The menu itself remains installed as /usr/local/bin/vps.
exec /usr/local/bin/vps
