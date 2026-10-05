#!/usr/bin/env bash
set -u

BASE="/opt/vps-monitor"
CONFIG="$BASE/config.sh"
SERVERS="$BASE/servers.conf"

CYAN='\033[1;36m'
GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
DIM='\033[0;36m'
RESET='\033[0m'

# Reliable terminal clear; works even when `clear`/TERM is problematic.
clear_screen() {
    printf '\033[2J\033[H'
}

pause_menu() {
    echo
    read -rp "Press ENTER to continue..." _
}

get_status() {
    local host="$1" port="$2" method="$3"
    if [[ "$method" == "ping" ]]; then
        ping -c 1 -W 2 "$host" >/dev/null 2>&1 && echo "ONLINE" || echo "DOWN"
    else
        timeout 3 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1 && echo "ONLINE" || echo "DOWN"
    fi
}

ensure_files() {
    mkdir -p "$BASE"
    [[ -f "$SERVERS" ]] || printf '# NAME|HOST|PORT|METHOD\n' > "$SERVERS"
    chmod 600 "$SERVERS" 2>/dev/null || true
}

show_vps() {
    clear_screen
    echo -e "${CYAN}==============================================================${RESET}"
    echo -e "${CYAN}                     REGISTERED VPS                           ${RESET}"
    echo -e "${CYAN}==============================================================${RESET}"
    printf "\n${WHITE}%-4s %-22s %-18s %-10s${RESET}\n" "#" "NAME" "IP ADDRESS" "STATUS"
    echo -e "${DIM}--------------------------------------------------------------${RESET}"

    local n=0 online=0 down=0
    while IFS='|' read -r name host port method; do
        [[ -z "${name// }" || "$name" == \#* ]] && continue
        n=$((n+1))
        local status
        status="$(get_status "$host" "$port" "$method")"
        if [[ "$status" == "ONLINE" ]]; then
            online=$((online+1))
            printf "%-4s %-22s %-18s ${GREEN}%-10s${RESET}\n" "$n" "$name" "$host" "ONLINE"
        else
            down=$((down+1))
            printf "%-4s %-22s %-18s ${RED}%-10s${RESET}\n" "$n" "$name" "$host" "DOWN"
        fi
    done < "$SERVERS"

    echo -e "${DIM}--------------------------------------------------------------${RESET}"
    echo -e "${GREEN}ONLINE: $online${RESET}    ${RED}DOWN: $down${RESET}    ${WHITE}TOTAL: $n${RESET}"
}

add_vps() {
    clear_screen
    echo -e "${CYAN}==============================================================${RESET}"
    echo -e "${CYAN}                         ADD VPS                              ${RESET}"
    echo -e "${CYAN}==============================================================${RESET}"
    echo

    read -rp "VPS Name: " name
    [[ -n "$name" ]] || { echo -e "${RED}Name cannot be empty.${RESET}"; pause_menu; return; }

    read -rp "IP / Hostname: " host
    [[ -n "$host" ]] || { echo -e "${RED}Host cannot be empty.${RESET}"; pause_menu; return; }

    echo
    echo "Monitoring method:"
    echo "  1) PING"
    echo "  2) TCP PORT"
    read -rp "Select [1-2]: " method_choice

    case "$method_choice" in
        1)
            method="ping"
            port="0"
            ;;
        2)
            method="tcp"
            read -rp "TCP Port: " port
            [[ "$port" =~ ^[0-9]+$ ]] || {
                echo -e "${RED}Invalid port.${RESET}"
                pause_menu
                return
            }
            ;;
        *)
            echo -e "${RED}Invalid option.${RESET}"
            pause_menu
            return
            ;;
    esac

    # Escape the delimiter so names cannot corrupt the config format.
    name="${name//|/-}"
    host="${host//|/-}"

    printf '%s|%s|%s|%s\n' "$name" "$host" "$port" "$method" >> "$SERVERS"
    echo
    echo -e "${GREEN}VPS added successfully.${RESET}"
    echo -e "${WHITE}$name | $host | $method${RESET}"

    # Restart monitor so the new target is picked up immediately.
    systemctl restart vps-monitor 2>/dev/null || true
    pause_menu
}

remove_vps() {
    clear_screen
    echo -e "${CYAN}==============================================================${RESET}"
    echo -e "${CYAN}                        REMOVE VPS                            ${RESET}"
    echo -e "${CYAN}==============================================================${RESET}"
    echo

    mapfile -t entries < <(grep -vE '^[[:space:]]*(#|$)' "$SERVERS")
    ((${#entries[@]})) || {
        echo -e "${YELLOW}No VPS registered.${RESET}"
        pause_menu
        return
    }

    local i=1
    for line in "${entries[@]}"; do
        IFS='|' read -r name host port method <<< "$line"
        printf "%2d) %-22s %s\n" "$i" "$name" "$host"
        i=$((i+1))
    done

    echo
    read -rp "Select VPS to remove [1-${#entries[@]}] (0 cancel): " choice
    [[ "$choice" == "0" ]] && return
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#entries[@]}" ]] || {
        echo -e "${RED}Invalid selection.${RESET}"
        pause_menu
        return
    }

    local selected="${entries[$((choice-1))]}"
    IFS='|' read -r name host port method <<< "$selected"

    read -rp "Remove '$name' ($host)? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || return

    grep -vxF "$selected" "$SERVERS" > "$SERVERS.tmp" || true
    mv "$SERVERS.tmp" "$SERVERS"
    chmod 600 "$SERVERS"

    echo -e "${GREEN}Removed: $name${RESET}"
    systemctl restart vps-monitor 2>/dev/null || true
    pause_menu
}

rename_vps() {
    clear_screen
    echo -e "${CYAN}==============================================================${RESET}"
    echo -e "${CYAN}                         RENAME VPS                            ${RESET}"
    echo -e "${CYAN}==============================================================${RESET}"
    echo

    mapfile -t entries < <(grep -vE '^[[:space:]]*(#|$)' "$SERVERS")
    ((${#entries[@]})) || {
        echo -e "${YELLOW}No VPS registered.${RESET}"
        pause_menu
        return
    }

    local i=1
    for line in "${entries[@]}"; do
        IFS='|' read -r name host port method <<< "$line"
        printf "%2d) %-22s %s\n" "$i" "$name" "$host"
        i=$((i+1))
    done

    echo
    read -rp "Select VPS [1-${#entries[@]}] (0 cancel): " choice
    [[ "$choice" == "0" ]] && return
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#entries[@]}" ]] || {
        echo -e "${RED}Invalid selection.${RESET}"
        pause_menu
        return
    }

    local selected="${entries[$((choice-1))]}"
    IFS='|' read -r old_name host port method <<< "$selected"

    echo
    read -rp "New name: " new_name
    [[ -n "$new_name" ]] || return
    new_name="${new_name//|/-}"

    local replacement="$new_name|$host|$port|$method"
    awk -v old="$selected" -v repl="$replacement" 'BEGIN{FS="\n"} $0==old{$0=repl} {print}' "$SERVERS" > "$SERVERS.tmp"
    mv "$SERVERS.tmp" "$SERVERS"
    chmod 600 "$SERVERS"

    echo -e "${GREEN}Renamed: $old_name -> $new_name${RESET}"
    systemctl restart vps-monitor 2>/dev/null || true
    pause_menu
}

telegram_status() {
    clear_screen
    echo -e "${CYAN}==============================================================${RESET}"
    echo -e "${CYAN}                      TELEGRAM STATUS                         ${RESET}"
    echo -e "${CYAN}==============================================================${RESET}"
    echo

    if [[ ! -f "$CONFIG" ]]; then
        echo -e "${RED}config.sh not found.${RESET}"
        pause_menu
        return
    fi

    # shellcheck disable=SC1090
    source "$CONFIG"

    local result
    result="$(curl -fsS --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null || true)"
    if echo "$result" | grep -q '"ok":true'; then
        echo -e "${GREEN}Telegram: CONNECTED${RESET}"
        echo "Chat ID: $CHAT_ID"
    else
        echo -e "${RED}Telegram: NOT CONNECTED${RESET}"
    fi
    pause_menu
}

menu_loop() {
    ensure_files

    while true; do
        clear_screen

        echo -e "${CYAN}==============================================================${RESET}"
        echo -e "${CYAN}                    EJ-VPS MONITOR                            ${RESET}"
        echo -e "${CYAN}                       MANAGER                                ${RESET}"
        echo -e "${CYAN}==============================================================${RESET}"
        echo
        echo -e "${CYAN}  [1]${WHITE} SHOW VPS${RESET}              ${CYAN}[4]${WHITE} RENAME VPS${RESET}"
        echo -e "${CYAN}  [2]${WHITE} ADD VPS${RESET}               ${CYAN}[5]${WHITE} TELEGRAM STATUS${RESET}"
        echo -e "${CYAN}  [3]${WHITE} REMOVE VPS${RESET}            ${CYAN}[0]${WHITE} EXIT${RESET}"
        echo
        echo -e "${CYAN}--------------------------------------------------------------${RESET}"
        echo -e "${WHITE}REGISTERED VPS${RESET}"
        echo -e "${CYAN}--------------------------------------------------------------${RESET}"

        local n=0 online=0 down=0
        while IFS='|' read -r name host port method; do
            [[ -z "${name// }" || "$name" == \#* ]] && continue
            n=$((n+1))
            local status
            status="$(get_status "$host" "$port" "$method")"
            if [[ "$status" == "ONLINE" ]]; then
                online=$((online+1))
                printf "  %-3s %-22s %-18s ${GREEN}%s${RESET}\n" "$n" "$name" "$host" "ONLINE"
            else
                down=$((down+1))
                printf "  %-3s %-22s %-18s ${RED}%s${RESET}\n" "$n" "$name" "$host" "DOWN"
            fi
        done < "$SERVERS"

        echo -e "${CYAN}--------------------------------------------------------------${RESET}"
        echo -e "${GREEN}ONLINE: $online${RESET}    ${RED}DOWN: $down${RESET}    ${WHITE}TOTAL: $n${RESET}"
        echo

        read -rp "Select option [0-5]: " option
        case "$option" in
            1) show_vps; pause_menu ;;
            2) add_vps ;;
            3) remove_vps ;;
            4) rename_vps ;;
            5) telegram_status ;;
            0) clear_screen; exit 0 ;;
            *) echo -e "${RED}Invalid option.${RESET}"; sleep 1 ;;
        esac
    done
}

menu_loop
