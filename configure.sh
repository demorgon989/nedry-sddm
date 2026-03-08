#!/usr/bin/env bash
# =============================================================================
#  Nedry — Audio Reconfiguration
#  Detects SDDM and/or lock screen installations and updates the audio device.
#  Run any time your audio device changes: sudo ./configure.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SDDM_THEMES_DIR="/usr/share/sddm/themes"
LOCK_MEDIA_DIR="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen"
LOCK_QML_FILE="$LOCK_MEDIA_DIR/LockScreenUi.qml"
LOCK_CONF="$LOCK_MEDIA_DIR/nedry-lock.conf"

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   🦖  NEDRY — RECONFIGURE AUDIO       🦖  ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./configure.sh"
        exit 1
    fi
}

# ── Device selection (shared) ─────────────────────────────────────────────────

select_device() {
    local current_device="$1"
    echo -e "  Current audio device: ${BOLD}$current_device${NC}" >&2
    echo "" >&2

    local raw_all raw
    raw_all=$(aplay -L 2>/dev/null || true)
    raw=$(echo "$raw_all" | grep -E '^sysdefault:CARD=' || true)
    [[ -z "$raw" ]] && raw=$(echo "$raw_all" | grep -E '^front:CARD=' || true)
    [[ -z "$raw" ]] && raw=$(echo "$raw_all" | grep -E '^(plughw|hw):CARD=' || true)

    local new_device
    if [[ -z "$raw" ]]; then
        echo -e "${YELLOW}[WARN]${NC} Could not detect any ALSA output devices." >&2
        echo "  Is alsa-utils installed?  Try: sudo dnf install alsa-utils" >&2
        echo "" >&2
        read -rp "  Enter device manually (e.g. sysdefault:CARD=Generic_1): " new_device
    else
        local cards=()
        local index=1
        echo "  Available audio output devices:" >&2
        echo "" >&2
        while IFS= read -r line; do
            local desc
            desc=$(echo "$raw_all" | grep -A2 "^${line}$" | grep -v "^${line}$" | grep -v '^\s*$' | head -1 | sed 's/^\s*//')
            cards+=("$line")
            printf "  [%d] %-35s  %s\n" "$index" "$line" "$desc" >&2
            ((index++))
        done <<< "$raw"

        echo "" >&2
        local choice
        while true; do
            read -rp "  Enter number [1-$((index-1))]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
                new_device="${cards[$((choice-1))]}"
                echo -e "${GREEN}  ✓ Selected: $new_device${NC}" >&2
                echo -e "  ${CYAN}(Stable name — won't break if USB devices are added/removed)${NC}" >&2
                break
            else
                echo "  Please enter a number between 1 and $((index-1))." >&2
            fi
        done
    fi

    echo "" >&2
    local test_choice
    read -rp "  Play a test sound? [Y/n]: " test_choice
    if [[ "$test_choice" != "n" && "$test_choice" != "N" ]]; then
        echo "  Playing test audio..." >&2
        aplay -D "$new_device" "$AUDIO_FILE" 2>/dev/null \
            && echo -e "${GREEN}  ✓ Audio test passed!${NC}" >&2 \
            || echo -e "${YELLOW}  [WARN]${NC} Test sound may not play here — sudo runs as root which has no PipeWire session.
         Audio will still work correctly from the actual login/lock screen.
         To verify, lock your screen (Super+L) and enter a wrong password." >&2
    fi

    # Only the device name goes to stdout — captured by caller
    echo "$new_device"
}

# ── Per-target update functions ───────────────────────────────────────────────

update_sddm() {
    local config_file="$1"
    local theme_dir
    theme_dir="$(dirname "$config_file")"
    local qml_file="$theme_dir/Main.qml"

    local THEME_NAME ALSA_DEVICE AUDIO_FILE
    # shellcheck source=/dev/null
    source "$config_file"

    echo -e "${BOLD}  SDDM theme: $THEME_NAME${NC}"

    local new_device
    new_device=$(select_device "$ALSA_DEVICE")

    sed -i "s|^ALSA_DEVICE=.*|ALSA_DEVICE=$new_device|" "$config_file"
    echo -e "${GREEN}  ✓ Config updated${NC}"

    sed -i "s|aplay -D ${ALSA_DEVICE}|aplay -D ${new_device}|g" "$qml_file"
    echo -e "${GREEN}  ✓ Main.qml updated${NC}"

    rm -rf /var/cache/sddm/* 2>/dev/null || true
    rm -rf /root/.cache/sddm* 2>/dev/null || true
    rm -rf /var/lib/sddm/.cache 2>/dev/null || true
    echo -e "${GREEN}  ✓ SDDM cache cleared${NC}"
    echo ""
}

update_lockscreen() {
    echo -e "${BOLD}  KDE lock screen${NC}"
    echo ""
    echo -e "  ${CYAN}The lock screen uses paplay via your PipeWire session —${NC}"
    echo -e "  ${CYAN}no audio device configuration needed.${NC}"
    echo -e "  ${CYAN}Audio device follows your normal system audio settings.${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    check_root
    print_banner

    # Discover what's installed
    local sddm_conf=""
    while IFS= read -r conf; do
        sddm_conf="$conf"
        break
    done < <(find "$SDDM_THEMES_DIR" -maxdepth 2 -name "nedry.conf" 2>/dev/null)

    local has_sddm=false
    local has_lock=false
    [[ -n "$sddm_conf" ]] && has_sddm=true
    [[ -f "$LOCK_CONF" ]] && has_lock=true

    if ! $has_sddm && ! $has_lock; then
        echo -e "${RED}[ERROR]${NC} No Nedry installations found."
        echo "  Please run install.sh first."
        exit 1
    fi

    # If both installed, ask which to reconfigure
    if $has_sddm && $has_lock; then
        local sddm_name
        sddm_name=$(basename "$(dirname "$sddm_conf")")
        echo "  Found Nedry installed in:"
        echo ""
        echo "  [1] SDDM theme: $sddm_name"
        echo "  [2] KDE lock screen"
        echo "  [3] Both"
        echo ""
        local choice
        while true; do
            read -rp "  Which to reconfigure? [1-3]: " choice
            [[ "$choice" =~ ^[123]$ ]] && break
            echo "  Please enter 1, 2, or 3."
        done
        case "$choice" in
            1) update_sddm "$sddm_conf" ;;
            2) update_lockscreen ;;
            3) update_sddm "$sddm_conf"; update_lockscreen ;;
        esac
    elif $has_sddm; then
        update_sddm "$sddm_conf"
    else
        update_lockscreen
    fi

    echo -e "${GREEN}${BOLD}  Done! 🦖${NC}"
    $has_sddm && echo "  SDDM  → Log out fully and enter a wrong password to test."
    $has_lock && echo "  Lock  → Lock your screen (Super+L) and enter a wrong password to test."
    echo ""
}

main

