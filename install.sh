#!/usr/bin/env bash
# =============================================================================
#  Nedry SDDM Installer
#  "You didn't say the magic word!" — Jurassic Park login fail theme
#  Requires: Fedora/KDE Plasma 6, any standard KDE SDDM theme
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDDM_THEMES_DIR="/usr/share/sddm/themes"
VIDEO_SRC="$SCRIPT_DIR/fail_h264.mp4"
AUDIO_SRC="$SCRIPT_DIR/fail.wav"

# Set by select_theme()
THEME_NAME=""
THEME_DIR=""
CONFIG_FILE=""
QML_FILE=""
QML_BAK=""
VIDEO_DEST=""
AUDIO_DEST=""
ALSA_DEVICE=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   🦖  NEDRY SDDM LOGIN FAIL THEME INSTALLER  🦖   ║"
    echo "  ║      \"You didn't say the magic word!\"            ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./install.sh"
        exit 1
    fi
}

check_dependencies() {
    echo -e "${BOLD}[1/5] Checking dependencies...${NC}"
    local missing=()
    for cmd in aplay python3; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Missing: ${missing[*]}"
        echo "  Install with: sudo dnf install alsa-utils python3"
        exit 1
    fi
    if [[ ! -f "$VIDEO_SRC" ]]; then
        echo -e "${RED}[ERROR]${NC} fail_h264.mp4 not found next to install.sh"
        exit 1
    fi
    if [[ ! -f "$AUDIO_SRC" ]]; then
        echo -e "${RED}[ERROR]${NC} fail.wav not found next to install.sh"
        exit 1
    fi
    echo -e "${GREEN}  ✓ Dependencies OK${NC}"
}

# Returns true if a theme's Main.qml looks like a standard KDE Plasma theme
is_compatible_theme() {
    local qml="$1"
    # Must have org.kde.breeze.components — the common base of all KDE SDDM themes
    grep -q "org.kde.breeze.components" "$qml" || return 1
    # Must have onLoginFailed somewhere
    grep -q "onLoginFailed" "$qml" || return 1
    # Must NOT use the old plasma.core 2.0 (deprecated, incompatible)
    grep -q "org.kde.plasma.core 2.0" "$qml" && return 1
    return 0
}

select_theme() {
    echo -e "${BOLD}[2/5] Selecting SDDM theme...${NC}"
    echo ""

    local themes=()
    local skipped=()

    while IFS= read -r qml; do
        local name
        name="$(basename "$(dirname "$qml")")"
        if is_compatible_theme "$qml"; then
            themes+=("$name")
        else
            skipped+=("$name")
        fi
    done < <(find "$SDDM_THEMES_DIR" -maxdepth 2 -name "Main.qml" 2>/dev/null | sort)

    if [[ ${#skipped[@]} -gt 0 ]]; then
        echo -e "  ${YELLOW}Skipping incompatible themes:${NC} ${skipped[*]}"
        echo ""
    fi

    if [[ ${#themes[@]} -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} No compatible KDE SDDM themes found."
        echo "  Install breeze or a standard KDE-based SDDM theme first."
        exit 1
    fi

    if [[ ${#themes[@]} -eq 1 ]]; then
        THEME_NAME="${themes[0]}"
        echo -e "  Only one compatible theme found, using: ${BOLD}$THEME_NAME${NC}"
    else
        echo "  Compatible SDDM themes:"
        echo ""
        for i in "${!themes[@]}"; do
            printf "  [%d] %s\n" "$((i+1))" "${themes[$i]}"
        done
        echo ""
        local choice
        while true; do
            read -rp "  Enter number [1-${#themes[@]}]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#themes[@]} )); then
                THEME_NAME="${themes[$((choice-1))]}"
                break
            else
                echo "  Please enter a number between 1 and ${#themes[@]}."
            fi
        done
    fi

    THEME_DIR="$SDDM_THEMES_DIR/$THEME_NAME"
    CONFIG_FILE="$THEME_DIR/nedry.conf"
    QML_FILE="$THEME_DIR/Main.qml"
    QML_BAK="$THEME_DIR/Main.qml.bak"
    VIDEO_DEST="$THEME_DIR/fail_h264.mp4"
    AUDIO_DEST="$THEME_DIR/fail.wav"

    echo -e "${GREEN}  ✓ Selected: $THEME_NAME${NC}"

    # Always restore from backup before patching so re-runs are safe
    if [[ ! -f "$QML_BAK" ]]; then
        cp "$QML_FILE" "$QML_BAK"
        echo -e "${GREEN}  ✓ Backed up Main.qml → Main.qml.bak${NC}"
    else
        cp "$QML_BAK" "$QML_FILE"
        echo -e "${GREEN}  ✓ Restored clean backup before patching${NC}"
    fi

    cp "$VIDEO_SRC" "$VIDEO_DEST"
    cp "$AUDIO_SRC" "$AUDIO_DEST"
    echo -e "${GREEN}  ✓ Media files copied to theme directory${NC}"
}

select_audio_device() {
    echo -e "${BOLD}[3/5] Selecting audio output device...${NC}"
    echo ""

    local raw
    raw=$(sudo -u sddm aplay -l 2>/dev/null | grep "^card" || true)

    if [[ -z "$raw" ]]; then
        echo -e "${YELLOW}  [WARN]${NC} Could not list ALSA devices as sddm user. Defaulting to hw:0,0"
        echo "  Change later with: sudo ./configure.sh"
        ALSA_DEVICE="hw:0,0"
        return
    fi

    local cards=()
    local labels=()
    local index=1

    echo "  Available ALSA playback devices:"
    echo ""
    while IFS= read -r line; do
        local card_num dev_num dev_label
        card_num=$(echo "$line" | grep -oP '(?<=card )\d+')
        dev_num=$(echo "$line"  | grep -oP '(?<=device )\d+')
        dev_label=$(echo "$line" | grep -oP '(?<=\[)[^\]]+(?=\])' | paste -sd ' / ')
        cards+=("hw:${card_num},${dev_num}")
        labels+=("$dev_label")
        printf "  [%d] hw:%s  →  %s\n" "$index" "${card_num},${dev_num}" "$dev_label"
        ((index++))
    done <<< "$raw"

    echo ""
    local choice
    while true; do
        read -rp "  Enter number [1-$((index-1))]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
            ALSA_DEVICE="${cards[$((choice-1))]}"
            echo -e "${GREEN}  ✓ Selected: $ALSA_DEVICE — ${labels[$((choice-1))]}${NC}"
            break
        else
            echo "  Please enter a number between 1 and $((index-1))."
        fi
    done

    echo ""
    read -rp "  Play a test sound now? [Y/n]: " test_choice
    if [[ "$test_choice" != "n" && "$test_choice" != "N" ]]; then
        echo "  Playing test audio..."
        sudo -u sddm aplay -D "$ALSA_DEVICE" "$AUDIO_DEST" 2>/dev/null \
            && echo -e "${GREEN}  ✓ Audio test passed!${NC}" \
            || echo -e "${YELLOW}  [WARN]${NC} aplay returned an error — try a different device with: sudo ./configure.sh"
    fi
}

patch_qml() {
    echo -e "${BOLD}[4/5] Patching Main.qml...${NC}"

    python3 << PYEOF
import re, sys

qml_file   = "${QML_FILE}"
audio_dest = "${AUDIO_DEST}"
alsa_device = "${ALSA_DEVICE}"
duration   = "10000"

with open(qml_file, 'r') as f:
    content = f.read()

# ── 1. Add "import QtMultimedia" if not already present ──────────────────────
if 'import QtMultimedia' not in content:
    last_import = max(
        (m.end() for m in re.finditer(r'^import .+', content, re.MULTILINE)),
        default=0
    )
    content = content[:last_import] + '\nimport QtMultimedia' + content[last_import:]
    print("  Added: import QtMultimedia")
else:
    print("  import QtMultimedia already present, skipping")

# ── 2. Ensure plasma5support is imported and get its alias ───────────────────
p5_match = re.search(r'import org\.kde\.plasma\.plasma5support[^\n]+as\s+(\w+)', content)
if p5_match:
    plasmacore_alias = p5_match.group(1)
    print(f"  Found plasma5support alias: {plasmacore_alias}")
else:
    # Not present — inject it after the last import line
    plasmacore_alias = "PlasmaCore"
    last_import = max(
        (m.end() for m in re.finditer(r'^import .+', content, re.MULTILINE)),
        default=0
    )
    inject = '\nimport org.kde.plasma.plasma5support 2.0 as PlasmaCore'
    content = content[:last_import] + inject + content[last_import:]
    print("  Added: import org.kde.plasma.plasma5support 2.0 as PlasmaCore")

# ── 3. Inject Nedry QML elements into the root Item block ────────────────────
nedry_elements = f"""
    // --- Nedry fail video ---
    MediaPlayer {{
        id: failVideo
        source: Qt.resolvedUrl("fail_h264.mp4")
        videoOutput: failVideoOutput
    }}

    VideoOutput {{
        id: failVideoOutput
        anchors.fill: parent
        visible: false
        z: 100
    }}

    // --- Audio via executable engine (QtMultimedia audio unavailable pre-login) ---
    {plasmacore_alias}.DataSource {{
        id: audioRunner
        engine: "executable"
        connectedSources: []
        onNewData: disconnectSource(sourceName)
    }}

    function playFailAudio() {{
        audioRunner.connectSource("aplay -D {alsa_device} {audio_dest}")
    }}

    Timer {{
        id: hideVideoTimer
        interval: {duration}
        repeat: false
        onTriggered: {{
            failVideoOutput.visible = false
            failVideo.stop()
        }}
    }}
"""

if 'id: failVideo' not in content:
    match = re.search(r'^Item\s*\{', content, re.MULTILINE)
    if match:
        insert_pos = content.find('\n', match.end())
        content = content[:insert_pos] + '\n' + nedry_elements + content[insert_pos:]
        print("  Injected Nedry elements into Item block")
    else:
        print("  ERROR: Could not find root Item { block", file=sys.stderr)
        sys.exit(1)
else:
    print("  Nedry elements already present, skipping")

# ── 4. Inject trigger calls into onLoginFailed ────────────────────────────────
trigger_calls = """            // Nedry
            failVideo.stop()
            failVideo.position = 0
            failVideoOutput.visible = true
            failVideo.play()
            playFailAudio()
            hideVideoTimer.restart()"""

if 'failVideo.play()' not in content:
    # Style A: onLoginFailed: {
    style_a = re.search(r'(onLoginFailed\s*:\s*\{[^\}]*?)(notificationMessage\s*=)', content, re.DOTALL)
    # Style B: function onLoginFailed() {
    style_b = re.search(r'(function\s+onLoginFailed\s*\(\s*\)\s*\{[^\}]*?)(notificationMessage\s*=)', content, re.DOTALL)

    match = style_a or style_b
    if match:
        nm_end = content.find('\n', match.start(2))
        content = content[:nm_end] + '\n' + trigger_calls + content[nm_end:]
        syntax = "A (signal handler)" if style_a else "B (function)"
        print(f"  Injected trigger calls into onLoginFailed (syntax {syntax})")
    else:
        print("  ERROR: Could not find onLoginFailed block", file=sys.stderr)
        sys.exit(1)
else:
    print("  Trigger calls already present, skipping")

with open(qml_file, 'w') as f:
    f.write(content)

print("  Patch complete.")
PYEOF

    echo -e "${GREEN}  ✓ Main.qml patched successfully${NC}"
}

write_config() {
    echo -e "${BOLD}[5/5] Saving config...${NC}"

    cat > "$CONFIG_FILE" <<EOF
# Nedry SDDM Theme Config
# Generated by install.sh on $(date)
# To change audio device later: sudo ./configure.sh

THEME_NAME=$THEME_NAME
THEME_DIR=$THEME_DIR
ALSA_DEVICE=$ALSA_DEVICE
AUDIO_FILE=$AUDIO_DEST
VIDEO_FILE=$VIDEO_DEST
CLIP_DURATION_MS=10000
EOF
    echo -e "${GREEN}  ✓ Config saved → $CONFIG_FILE${NC}"

    echo ""
    echo -e "${CYAN}  Running QML syntax check...${NC}"
    sddm-greeter-qt6 --test-mode --theme "$THEME_DIR" &>/dev/null &
    sleep 3
    kill %1 2>/dev/null && echo -e "${GREEN}  ✓ QML loaded without errors${NC}" || \
        echo -e "${YELLOW}  Could not auto-verify. Test manually:${NC}
    sddm-greeter-qt6 --test-mode --theme $THEME_DIR"

    echo ""
    echo -e "${GREEN}${BOLD}  Installation complete! 🦖${NC}"
    echo ""
    echo "  → Fully log out and enter a wrong password to test."
    echo "  → To change audio device later: sudo ./configure.sh"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
print_banner
check_root
check_dependencies
select_theme
select_audio_device
patch_qml
write_config
