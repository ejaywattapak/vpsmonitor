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

[[ $EUID -eq 0 ]] || die "Run this installer as root."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wget curl python3 iputils-ping

clear
echo -e "${CYAN}"
cat <<'EOF'
==============================================================
                     EJ-VPS MONITOR
                       INSTALLER
==============================================================
EOF
echo -e "${RESET}"

echo -e "${CYAN}[1/7] Checking GitHub files...${RESET}"
for f in menu.sh monitor.sh telegram.sh telegram_bot.py; do
    curl -fsSL --max-time 20 -o /dev/null "$RAW/$f" || die "Cannot access GitHub file: $f"
done
echo -e "${GREEN}✓ GitHub repository reachable${RESET}"

clear
echo -e "${CYAN}"
cat <<'EOF'
==============================================================
                 TELEGRAM BOT TOKEN
==============================================================
EOF
echo -e "${RESET}"

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
==============================================================
                    TELEGRAM CHAT ID
==============================================================
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

echo -e "${CYAN}[3/7] Installing VPS Monitor files...${RESET}"
mkdir -p "$BASE"
chmod 700 "$BASE"

download_file() {
    local file="$1"
    echo -e "  ${CYAN}→${RESET} $file"
    curl -fsSL --retry 3 --max-time 30 "$RAW/$file" -o "$BASE/$file"
    chmod 700 "$BASE/$file"
}

download_file menu.sh
download_file monitor.sh
download_file telegram.sh
download_file telegram_bot.py

cat > "$BASE/config.sh" <<EOF
BOT_TOKEN='$BOT_TOKEN'
CHAT_ID='$CHAT_ID'
CHECK_INTERVAL=30
EOF
chmod 600 "$BASE/config.sh"

# Keep existing VPS registrations during reinstall.
if [[ ! -f "$BASE/servers.conf" ]]; then
    printf '# NAME|HOST|PORT|METHOD\n' > "$BASE/servers.conf"
fi
chmod 600 "$BASE/servers.conf"

echo -e "${GREEN}✓ Application files installed${RESET}"

echo -e "${CYAN}[4/7] Installing services...${RESET}"

cat > /etc/systemd/system/vps-monitor.service <<EOF
[Unit]
Description=EJ-VPS Monitor
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

cat > /etc/systemd/system/vps-telegram.service <<EOF
[Unit]
Description=EJ-VPS Telegram Command Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $BASE/telegram_bot.py
WorkingDirectory=$BASE
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vps-monitor >/dev/null
systemctl enable vps-telegram >/dev/null
systemctl restart vps-monitor
systemctl restart vps-telegram

echo -e "${GREEN}✓ VPS Monitor service started${RESET}"
echo -e "${GREEN}✓ Telegram command bot started${RESET}"

echo -e "${CYAN}[5/7] Installing SSH menu...${RESET}"
ln -sf "$BASE/menu.sh" /usr/local/bin/vps
chmod +x "$BASE/menu.sh"

# Replace only our own marked SSH block.
touch /root/.bashrc
sed -i '/# EJ-VPS-MONITOR-AUTO-MENU/,/# END-EJ-VPS-MONITOR-AUTO-MENU/d' /root/.bashrc
cat >> /root/.bashrc <<'EOF'

# EJ-VPS-MONITOR-AUTO-MENU
if [ -t 0 ] && [ -t 1 ] && [ -x /usr/local/bin/vps ] && [ -z "${EJ_VPS_MONITOR_MENU:-}" ]; then
    export EJ_VPS_MONITOR_MENU=1
    printf '\033[2J\033[H'
    /usr/local/bin/vps
fi
# END-EJ-VPS-MONITOR-AUTO-MENU
EOF

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

echo -e "${CYAN}[6/7] Telegram startup test...${RESET}"
"$BASE/telegram.sh" send "🚨 VPS MONITOR STARTED

🖥 Monitor: $(hostname)
🟢 Status: ONLINE
📡 Telegram: Connected" >/dev/null 2>&1 || true

echo -e "${GREEN}✓ Startup alert sent${RESET}"

echo -e "${CYAN}[7/7] Cleaning installer...${RESET}"
# Remove the temporary installer downloaded by the one-line command.
# Never remove files from /opt/vps-monitor here.
if [[ -f "$INSTALLER_PATH" && "$INSTALLER_PATH" != "$BASE/installer.sh" ]]; then
    rm -f -- "$INSTALLER_PATH"
fi

echo -e "${GREEN}✓ Installation complete${RESET}"
sleep 1
printf '\033[2J\033[H'
exec /usr/local/bin/vps
