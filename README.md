<p align="center">
  <img src="banner.png" alt="VPS Telegram Monitor Banner" width="100%">
</p>

<h1 align="center">VPS Telegram Monitor</h1>

<p align="center">
  Lightweight VPS monitoring with Telegram alerts and a colourful SSH management menu.
</p>

<p align="center">
  <b>🟢 ONLINE</b> · <b>🔴 DOWN</b> · <b>📡 TELEGRAM ALERT</b> · <b>⚡ PING / TCP</b>
</p>

---

## 🚀 One-Line Installation

Run as `root` on Ubuntu/Debian:

```bash
apt update && apt install -y wget && wget -O installer.sh https://raw.githubusercontent.com/ejaywattapak/vpsmonitor/main/installer.sh && chmod +x installer.sh && bash installer.sh
```

The installer will guide you through the setup.

---

## ✨ Features

- 🟢 Monitor VPS online/offline status
- 🔴 Telegram alert when a VPS goes DOWN
- 🟢 Telegram recovery alert when a VPS comes back ONLINE
- 📡 PING monitoring
- 🔌 TCP port monitoring
- 🤖 Telegram commands
- 🖥 Colourful cyan SSH management menu
- ➕ Add VPS
- ➖ Remove VPS
- ✏️ Rename VPS
- 📊 Show all registered VPS and current status
- ⚙️ systemd auto-start
- 🔄 Automatic monitor restart if the service stops
- 📝 Simple `servers.conf` configuration
- 🧩 Modular shell scripts for easy editing

---

## 📱 Telegram Commands

After installation, the bot supports:

```text
/status
/add
/remove
/rename
```

### `/status`

Shows all registered VPS:

```text
📊 VPS STATUS

🖥 Monitor: up1

🟢 1. UPCLOUD
   🌐 127.0.0.1

🟢 2. SVR4U
   🌐 87.76.160.198

🔴 3. READY SERVER
   🌐 113.29.231.246

━━━━━━━━━━━━━━━━━━━━
🟢 ONLINE: 2
🔴 DOWN: 1
```

### `/add`

Interactive VPS setup.

You can choose:

```text
1. PING
2. TCP PORT
```

### `/remove`

Select a VPS from the registered list and remove it.

### `/rename`

Select a VPS and change its display name.

---

## 🚨 VPS DOWN Alerts

The monitor checks VPS status continuously.

When a VPS changes from ONLINE to DOWN, the bot sends:

```text
🚨 VPS DOWN

🖥 Server: SVR4U
🌐 Host: 87.76.160.198
📡 Method: PING
❌ Connection failed
```

When it comes back:

```text
🟢 VPS RECOVERED

🖥 Server: SVR4U
🌐 Host: 87.76.160.198
📡 Method: PING
✅ Server is online again
```

The monitor does **not** repeatedly spam Telegram while the VPS remains down. It alerts on the status change and again when the VPS recovers.

---

## 🤖 Telegram Bot Setup

### 1. Get Bot Token

1. Open Telegram.
2. Search for **@BotFather**.
3. Open the official BotFather.
4. Send:

```text
/newbot
```

5. Follow the instructions.
6. BotFather will give you a Bot Token.
7. Copy it into the installer.

Example:

```text
123456789:AAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

⚠️ **Never publish your Bot Token on GitHub.**

---

### 2. Get Chat ID

1. Open your VPS Monitor bot.
2. Send:

```text
/start
```

3. Open:

```text
https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates
```

4. Find:

```text
"chat":{"id":123456789
```

5. The number after `id` is your Chat ID.

Example:

```text
8474044977
```

The installer will test the Chat ID by sending a Telegram message before continuing.

---

## 🖥 SSH Management Menu

After installation:

```bash
vps
```

The root SSH login can also automatically open the menu.

Example:

```text
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
```

The VPS list appears underneath the menu with live status.

---

## 📋 VPS Configuration

Configuration file:

```text
/opt/vps-monitor/servers.conf
```

Format:

```text
NAME|HOST|PORT|METHOD
```

Examples:

```text
UPCLOUD|127.0.0.1|22|tcp
SVR4U|87.76.160.198|0|ping
READY SERVER|113.29.231.246|0|ping
```

### PING

For basic VPS availability:

```text
SVR4U|87.76.160.198|0|ping
```

### TCP

For checking whether a specific TCP port is reachable:

```text
UPCLOUD|127.0.0.1|22|tcp
```

---

## ⚙️ Service Commands

Check service:

```bash
systemctl status vps-monitor
```

Restart:

```bash
systemctl restart vps-monitor
```

Stop:

```bash
systemctl stop vps-monitor
```

Start:

```bash
systemctl start vps-monitor
```

View live logs:

```bash
journalctl -u vps-monitor -f
```

---

## 📁 Project Structure

```text
vpsmonitor/
├── installer.sh
├── menu.sh
├── monitor.sh
├── telegram.sh
├── config.sh.example
├── servers.conf.example
├── uninstall.sh
├── banner.png
├── README.md
└── LICENSE
```

### `installer.sh`

Main installer.

Handles:

- Dependencies
- Telegram Bot Token
- Telegram Chat ID
- File installation
- systemd service
- SSH menu
- Telegram test

### `menu.sh`

SSH management interface.

### `monitor.sh`

Background VPS monitoring and Telegram alerts.

### `telegram.sh`

Telegram API helper.

### `servers.conf`

Registered VPS list.

---

## 🗑 Uninstall

Run:

```bash
bash /opt/vps-monitor/uninstall.sh
```

This removes:

- VPS Monitor service
- systemd configuration
- `vps` command
- SSH auto-menu
- `/opt/vps-monitor`

---

## 🔐 Security

Your Telegram Bot Token is a secret.

Do **not**:

- Put the token in `README.md`
- Put the token in GitHub
- Commit `config.sh` containing the real token
- Share screenshots containing the token

The installer stores the credentials locally on the VPS.

---

## 📦 Requirements

Recommended:

- Ubuntu 22.04+
- Ubuntu 24.04+
- Debian 12+
- Debian 13+
- Root access
- Internet connection
- Python 3
- `curl`
- `ping`

The installer handles required package installation where needed.

---

## 👨‍💻 Author

**ejaywattapak**

GitHub:

https://github.com/ejaywattapak

Repository:

https://github.com/ejaywattapak/vpsmonitor

---

## 📄 License

MIT License
