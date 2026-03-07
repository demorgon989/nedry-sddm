#!/usr/bin/env bash
# =============================================================================
#  Nedry SDDM Theme — Audio Reconfiguration
#  Run this any time your audio device changes: sudo ./configure.sh
# =============================================================================

set -e

THEME_DIR="/usr/share/sddm/themes/Noir-SDDM-6"
CONFIG_FILE="$THEME_DIR/nedry.conf"
QML_FILE="$THEME_DIR/Main.qml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./configure.sh"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} No config found at $CONFIG_FILE"
    echo "  Please run install.sh first."
    exit 1
fi

# Load current config
source "$CONFIG_FILE"

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   🦖  NEDRY SDDM — RECONFIGURE AUDIO  🦖  ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Current audio device: ${BOLD}$ALSA_DEVICE${NC}"
echo ""

# List devices
local_raw=$(sudo -u sddm aplay -l 2>/dev/null | grep "^card" || true)

if [[ -z "$local_raw" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Could not list ALSA devices as sddm user."
    read -rp "  Enter ALSA device manually (e.g. hw:2,0): " NEW_DEVICE
else
    cards=()
    labels=()
    index=1
    echo "  Available ALSA playback devices:"
    echo ""
    while IFS= read -r line; do
        card_num=$(echo "$line" | grep -oP '(?<=card )\d+')
        dev_num=$(echo "$line"  | grep -oP '(?<=device )\d+')
        dev_label=$(echo "$line" | grep -oP '(?<=\[)[^\]]+(?=\])' | paste -sd ' / ')
        cards+=("hw:${card_num},${dev_num}")
        labels+=("$dev_label")
        printf "  [%d] hw:%s  →  %s\n" "$index" "${card_num},${dev_num}" "$dev_label"
        ((index++))
    done <<< "$local_raw"

    echo ""
    while true; do
        read -rp "  Enter number [1-$((index-1))]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
            NEW_DEVICE="${cards[$((choice-1))]}"
            echo -e "${GREEN}  ✓ Selected: $NEW_DEVICE — ${labels[$((choice-1))]}${NC}"
            break
        else
            echo "  Please enter a number between 1 and $((index-1))."
        fi
    done
fi

echo ""
read -rp "  Play a test sound? [Y/n]: " test_choice
if [[ "$test_choice" != "n" && "$test_choice" != "N" ]]; then
    sudo -u sddm aplay -D "$NEW_DEVICE" "$AUDIO_FILE" 2>/dev/null \
        && echo -e "${GREEN}  ✓ Audio test passed!${NC}" \
        || echo -e "${YELLOW}  [WARN]${NC} aplay returned an error."
fi

# Update config
sed -i "s|^ALSA_DEVICE=.*|ALSA_DEVICE=$NEW_DEVICE|" "$CONFIG_FILE"
echo -e "${GREEN}  ✓ Config updated${NC}"

# Patch QML in place — replace old hw: device string
OLD_DEVICE="$ALSA_DEVICE"
sed -i "s|aplay -D ${OLD_DEVICE}|aplay -D ${NEW_DEVICE}|g" "$QML_FILE"
echo -e "${GREEN}  ✓ Main.qml updated${NC}"

echo ""
echo -e "${GREEN}${BOLD}  Done! Log out fully and enter a wrong password to test. 🦖${NC}"
echo ""
