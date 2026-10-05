#!/usr/bin/env python3
import json
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request

BASE = "/opt/vps-monitor"
CONFIG = os.path.join(BASE, "config.sh")
SERVERS = os.path.join(BASE, "servers.conf")
OFFSET_FILE = os.path.join(BASE, ".telegram_offset")

def load_config():
    vals = {}
    try:
        text = open(CONFIG, encoding="utf-8").read()
        for key in ("BOT_TOKEN", "CHAT_ID"):
            m = re.search(rf"^\s*{key}\s*=\s*['\"]?(.*?)['\"]?\s*$", text, re.M)
            if m:
                vals[key] = m.group(1).strip("'\"")
    except Exception:
        pass
    return vals

CFG = load_config()
TOKEN = CFG.get("BOT_TOKEN", "")
ALLOWED_CHAT = str(CFG.get("CHAT_ID", "")).strip()

def api(method, data=None, timeout=35):
    url = f"https://api.telegram.org/bot{TOKEN}/{method}"
    if data is None:
        req = urllib.request.Request(url)
    else:
        body = urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(url, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())

def send(chat_id, text):
    return api("sendMessage", {"chat_id": chat_id, "text": text})

def allowed(chat_id):
    return ALLOWED_CHAT and str(chat_id) == ALLOWED_CHAT

def load_servers():
    rows = []
    if not os.path.exists(SERVERS):
        return rows
    with open(SERVERS, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            p = line.split("|")
            if len(p) >= 4:
                rows.append({"name": p[0], "host": p[1], "port": p[2], "method": p[3], "raw": line})
    return rows

def save_servers(rows):
    with open(SERVERS, "w", encoding="utf-8") as f:
        f.write("# NAME|HOST|PORT|METHOD\n")
        for x in rows:
            f.write(f"{x['name']}|{x['host']}|{x['port']}|{x['method']}\n")
    os.chmod(SERVERS, 0o600)

def check(x):
    try:
        if x["method"].lower() == "ping":
            r = subprocess.run(
                ["ping", "-c", "1", "-W", "2", x["host"]],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4
            )
            return r.returncode == 0
        port = int(x["port"])
        r = subprocess.run(
            ["timeout", "3", "bash", "-c", f"</dev/tcp/{x['host']}/{port}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4
        )
        return r.returncode == 0
    except Exception:
        return False

def status_text():
    rows = load_servers()
    if not rows:
        return "🚨 EJ-VPS MONITOR\n\nNo VPS registered."
    out = ["🚨 EJ-VPS MONITOR", ""]
    online = down = 0
    for i, x in enumerate(rows, 1):
        ok = check(x)
        if ok:
            online += 1
            icon = "🟢"
            state = "ONLINE"
        else:
            down += 1
            icon = "🔴"
            state = "DOWN"
        out.append(f"{i}. {icon} {x['name']}\n   🖥 {x['host']}\n   📡 {state}")
    out += ["", f"🟢 Online: {online}", f"🔴 Down: {down}", f"📊 Total: {len(rows)}"]
    return "\n".join(out)

def help_text():
    return (
        "🚨 EJ-VPS MONITOR\n\n"
        "/status - Show all VPS status\n"
        "/add - Add a VPS\n"
        "/remove - Remove a VPS\n"
        "/rename - Rename a VPS\n"
        "/start - Show this menu\n\n"
        "ADD format:\n"
        "Send /add, then follow the steps."
    )

sessions = {}

def handle(chat_id, text):
    if not allowed(chat_id):
        return

    text = text.strip()
    state = sessions.get(str(chat_id))

    if text in ("/start", "/help"):
        sessions.pop(str(chat_id), None)
        send(chat_id, help_text())
        return

    if text == "/status":
        sessions.pop(str(chat_id), None)
        send(chat_id, status_text())
        return

    if text == "/add":
        sessions[str(chat_id)] = {"step": "name"}
        send(chat_id, "➕ ADD VPS\n\nEnter VPS name:")
        return

    if text == "/remove":
        rows = load_servers()
        if not rows:
            send(chat_id, "No VPS registered.")
            return
        sessions[str(chat_id)] = {"step": "remove"}
        msg = "🗑 REMOVE VPS\n\n"
        for i, x in enumerate(rows, 1):
            msg += f"{i}. {x['name']} — {x['host']}\n"
        msg += "\nEnter number to remove:"
        send(chat_id, msg)
        return

    if text == "/rename":
        rows = load_servers()
        if not rows:
            send(chat_id, "No VPS registered.")
            return
        sessions[str(chat_id)] = {"step": "rename_select"}
        msg = "✏️ RENAME VPS\n\n"
        for i, x in enumerate(rows, 1):
            msg += f"{i}. {x['name']} — {x['host']}\n"
        msg += "\nEnter number:"
        send(chat_id, msg)
        return

    if not state:
        send(chat_id, help_text())
        return

    s = str(chat_id)

    if state["step"] == "name":
        sessions[s] = {"step": "host", "name": text.replace("|", "-")}
        send(chat_id, "Enter VPS IP / hostname:")
    elif state["step"] == "host":
        sessions[s] = {"step": "method", "name": state["name"], "host": text.replace("|", "-")}
        send(chat_id, "Monitoring method:\n\n1 - PING\n2 - TCP PORT\n\nReply 1 or 2:")
    elif state["step"] == "method":
        if text == "1":
            rows = load_servers()
            rows.append({"name": state["name"], "host": state["host"], "port": "0", "method": "ping"})
            save_servers(rows)
            sessions.pop(s, None)
            send(chat_id, f"✅ VPS added.\n\n🖥 {state['name']}\n📡 {state['host']}\n🔎 PING")
        elif text == "2":
            sessions[s] = {**state, "step": "port"}
            send(chat_id, "Enter TCP port:")
        else:
            send(chat_id, "Reply 1 for PING or 2 for TCP PORT.")
    elif state["step"] == "port":
        if not text.isdigit() or not (1 <= int(text) <= 65535):
            send(chat_id, "Invalid port. Enter a number from 1 to 65535:")
            return
        rows = load_servers()
        rows.append({"name": state["name"], "host": state["host"], "port": text, "method": "tcp"})
        save_servers(rows)
        sessions.pop(s, None)
        send(chat_id, f"✅ VPS added.\n\n🖥 {state['name']}\n📡 {state['host']}:{text}\n🔎 TCP")
    elif state["step"] == "remove":
        rows = load_servers()
        if not text.isdigit() or not (1 <= int(text) <= len(rows)):
            send(chat_id, "Invalid number. Try again:")
            return
        x = rows.pop(int(text) - 1)
        save_servers(rows)
        sessions.pop(s, None)
        send(chat_id, f"✅ Removed VPS:\n{x['name']} ({x['host']})")
    elif state["step"] == "rename_select":
        rows = load_servers()
        if not text.isdigit() or not (1 <= int(text) <= len(rows)):
            send(chat_id, "Invalid number. Try again:")
            return
        sessions[s] = {"step": "rename_name", "index": int(text) - 1}
        send(chat_id, "Enter new VPS name:")
    elif state["step"] == "rename_name":
        rows = load_servers()
        idx = state["index"]
        if idx >= len(rows):
            sessions.pop(s, None)
            send(chat_id, "VPS no longer exists.")
            return
        old = rows[idx]["name"]
        rows[idx]["name"] = text.replace("|", "-")
        save_servers(rows)
        sessions.pop(s, None)
        send(chat_id, f"✅ Renamed:\n{old} → {rows[idx]['name']}")

def main():
    if not TOKEN:
        raise SystemExit("BOT_TOKEN missing in /opt/vps-monitor/config.sh")
    # Clear any stale webhook so long polling works.
    try:
        api("deleteWebhook", {"drop_pending_updates": "false"})
    except Exception:
        pass

    offset = 0
    try:
        offset = int(open(OFFSET_FILE).read().strip())
    except Exception:
        pass

    while True:
        try:
            result = api("getUpdates", {
                "timeout": "25",
                "offset": str(offset),
                "allowed_updates": json.dumps(["message"])
            }, timeout=35)
            for u in result.get("result", []):
                offset = int(u["update_id"]) + 1
                try:
                    with open(OFFSET_FILE, "w") as f:
                        f.write(str(offset))
                except Exception:
                    pass
                msg = u.get("message", {})
                chat = msg.get("chat", {})
                text = msg.get("text")
                if text:
                    handle(chat.get("id"), text)
        except Exception:
            time.sleep(3)

if __name__ == "__main__":
    main()
