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

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./configure.sh"
    exit 1
fi

# Auto-discover theme — no hardcoded path needed
CONFIG_FILE=""
while IFS= read -r conf; do
    CONFIG_FILE="$conf"
    break
done < <(find "$SDDM_THEMES_DIR" -maxdepth 2 -name "nedry.conf" 2>/dev/null)

if [[ -z "$CONFIG_FILE" ]]; then
    echo -e "${RED}[ERROR]${NC} No nedry.conf found under $SDDM_THEMES_DIR"
    echo "  Please run install.sh first."
    exit 1
fi

THEME_DIR="$(dirname "$CONFIG_FILE")"
QML_FILE="$THEME_DIR/Main.qml"

# Load current config
source "$CONFIG_FILE"

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   🦖  NEDRY SDDM — RECONFIGURE AUDIO  🦖  ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  Theme:                ${BOLD}$THEME_NAME${NC}"
echo -e "  Current audio device: ${BOLD}$ALSA_DEVICE${NC}"
echo ""

# Build device list from aplay -L
# We want 'sysdefault:CARD=X' entries — one clean entry per physical device,
# works on both classic ALSA and PipeWire systems.
# Fall back to hdmi: entries if nothing else found.
raw_all=$(aplay -L 2>/dev/null || true)

# Prefer sysdefault: (one per card, covers analog + USB audio)
local_raw=$(echo "$raw_all" | grep -E '^sysdefault:CARD=' || true)

# If no sysdefault entries, fall back to front: (also one per analog card)
if [[ -z "$local_raw" ]]; then
    local_raw=$(echo "$raw_all" | grep -E '^front:CARD=' || true)
fi

# Last resort — plughw/hw for classic ALSA without PipeWire
if [[ -z "$local_raw" ]]; then
    local_raw=$(echo "$raw_all" | grep -E '^(plughw|hw):CARD=' || true)
fi

if [[ -z "$local_raw" ]]; then
    echo -e "${YELLOW}[WARN]${NC} Could not detect any ALSA output devices."
    echo "  Is alsa-utils installed?  Try: sudo dnf install alsa-utils"
    echo ""
    read -rp "  Enter device manually (e.g. sysdefault:CARD=Generic_1): " NEW_DEVICE
else
    cards=()
    descriptions=()
    index=1

    echo "  Available audio output devices:"
    echo ""

    # Read both the device line and the description line below it
    while IFS= read -r line; do
        if [[ "$line" =~ ^(sysdefault|front|plughw|hw):CARD= ]]; then
            device="$line"
            # Peek at next non-empty line for the human-readable description
            desc=$(echo "$raw_all" | grep -A2 "^${line}$" | grep -v "^${line}$" | grep -v '^\s*$' | head -1 | sed 's/^\s*//')
            cards+=("$device")
            descriptions+=("$desc")
            printf "  [%d] %-35s  %s\n" "$index" "$device" "$desc"
            ((index++))
        fi
    done <<< "$local_raw"

    echo ""
    while true; do
        read -rp "  Enter number [1-$((index-1))]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
            NEW_DEVICE="${cards[$((choice-1))]}"
            echo -e "${GREEN}  ✓ Selected: $NEW_DEVICE${NC}"
            echo -e "  ${CYAN}(Uses card name — stable even if USB devices are added/removed)${NC}"
            break
        else
            echo "  Please enter a number between 1 and $((index-1))."
        fi
    done
fi

echo ""
read -rp "  Play a test sound? [Y/n]: " test_choice
if [[ "$test_choice" != "n" && "$test_choice" != "N" ]]; then
    echo "  Playing test audio..."
    aplay -D "$NEW_DEVICE" "$AUDIO_FILE" 2>/dev/null \
        && echo -e "${GREEN}  ✓ Audio test passed!${NC}" \
        || echo -e "${YELLOW}  [WARN]${NC} aplay returned an error — device may still work at login. Try another if unsure."
fi

# Update config
sed -i "s|^ALSA_DEVICE=.*|ALSA_DEVICE=$NEW_DEVICE|" "$CONFIG_FILE"
echo -e "${GREEN}  ✓ Config updated${NC}"

# Patch QML — replace old device string with new one
# | delimiter handles colons and commas in device names safely
OLD_DEVICE="$ALSA_DEVICE"
sed -i "s|aplay -D ${OLD_DEVICE}|aplay -D ${NEW_DEVICE}|g" "$QML_FILE"
echo -e "${GREEN}  ✓ Main.qml updated${NC}"

# Clear all known SDDM cache locations
rm -rf /var/cache/sddm/* 2>/dev/null || true
rm -rf /root/.cache/sddm* 2>/dev/null || true
rm -rf /var/lib/sddm/.cache 2>/dev/null || true
echo -e "${GREEN}  ✓ SDDM cache cleared${NC}"

echo ""
echo -e "${GREEN}${BOLD}  Done! Log out fully and enter a wrong password to test. 🦖${NC}"
echo ""
