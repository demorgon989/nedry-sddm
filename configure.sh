#!/usr/bin/env bash
# =============================================================================
#  Nedry SDDM Theme — Audio Reconfiguration
#  Run this any time your audio device changes: sudo ./configure.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SDDM_THEMES_DIR="/usr/share/sddm/themes"

main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./configure.sh"
        exit 1
    fi

    # Auto-discover theme — no hardcoded path needed
    local config_file=""
    while IFS= read -r conf; do
        config_file="$conf"
        break
    done < <(find "$SDDM_THEMES_DIR" -maxdepth 2 -name "nedry.conf" 2>/dev/null)

    if [[ -z "$config_file" ]]; then
        echo -e "${RED}[ERROR]${NC} No nedry.conf found under $SDDM_THEMES_DIR"
        echo "  Please run install.sh first."
        exit 1
    fi

    local theme_dir
    theme_dir="$(dirname "$config_file")"
    local qml_file="$theme_dir/Main.qml"

    # Load current config into local-scoped vars via temp file to avoid polluting globals
    local THEME_NAME ALSA_DEVICE AUDIO_FILE
    # shellcheck source=/dev/null
    source "$config_file"

    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   🦖  NEDRY SDDM — RECONFIGURE AUDIO  🦖  ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Theme:                ${BOLD}$THEME_NAME${NC}"
    echo -e "  Current audio device: ${BOLD}$ALSA_DEVICE${NC}"
    echo ""

    # List devices using stable CARD= names.
    # On PipeWire systems (Fedora default) use sysdefault:CARD= — no plughw/hw entries exist.
    local raw_all raw
    raw_all=$(aplay -L 2>/dev/null || true)
    raw=$(echo "$raw_all" | grep -E '^sysdefault:CARD=' || true)
    [[ -z "$raw" ]] && raw=$(echo "$raw_all" | grep -E '^front:CARD=' || true)
    [[ -z "$raw" ]] && raw=$(echo "$raw_all" | grep -E '^(plughw|hw):CARD=' || true)

    local new_device
    if [[ -z "$raw" ]]; then
        echo -e "${YELLOW}[WARN]${NC} Could not detect any ALSA output devices."
        echo "  Is alsa-utils installed?  Try: sudo dnf install alsa-utils"
        echo ""
        read -rp "  Enter device manually (e.g. sysdefault:CARD=Generic_1): " new_device
    else
        local cards=()
        local index=1
        echo "  Available audio output devices:"
        echo ""
        while IFS= read -r line; do
            local desc
            desc=$(echo "$raw_all" | grep -A2 "^${line}$" | grep -v "^${line}$" | grep -v '^\s*$' | head -1 | sed 's/^\s*//')
            cards+=("$line")
            printf "  [%d] %-35s  %s\n" "$index" "$line" "$desc"
            ((index++))
        done <<< "$raw"

        echo ""
        local choice
        while true; do
            read -rp "  Enter number [1-$((index-1))]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
                new_device="${cards[$((choice-1))]}"
                echo -e "${GREEN}  ✓ Selected: $new_device${NC}"
                echo -e "  ${CYAN}(Stable name — won't break if USB devices are added/removed)${NC}"
                break
            else
                echo "  Please enter a number between 1 and $((index-1))."
            fi
        done
    fi

    echo ""
    local test_choice
    read -rp "  Play a test sound? [Y/n]: " test_choice
    if [[ "$test_choice" != "n" && "$test_choice" != "N" ]]; then
        echo "  Playing test audio..."
        aplay -D "$new_device" "$AUDIO_FILE" 2>/dev/null \
            && echo -e "${GREEN}  ✓ Audio test passed!${NC}" \
            || echo -e "${YELLOW}  [WARN]${NC} aplay returned an error — device may still work at login. Try another if unsure."
    fi

    # Update config — use | delimiter so colons/commas in device names are safe
    sed -i "s|^ALSA_DEVICE=.*|ALSA_DEVICE=$new_device|" "$config_file"
    echo -e "${GREEN}  ✓ Config updated${NC}"

    # Patch QML — replace old device string with new one
    sed -i "s|aplay -D ${ALSA_DEVICE}|aplay -D ${new_device}|g" "$qml_file"
    echo -e "${GREEN}  ✓ Main.qml updated${NC}"

    # Clear all known SDDM cache locations
    rm -rf /var/cache/sddm/* 2>/dev/null || true
    rm -rf /root/.cache/sddm* 2>/dev/null || true
    rm -rf /var/lib/sddm/.cache 2>/dev/null || true
    echo -e "${GREEN}  ✓ SDDM cache cleared${NC}"

    echo ""
    echo -e "${GREEN}${BOLD}  Done! Log out fully and enter a wrong password to test. 🦖${NC}"
    echo ""
}

main
