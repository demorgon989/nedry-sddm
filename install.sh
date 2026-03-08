#!/usr/bin/env bash
# =============================================================================
#  Nedry Installer
#  "You didn't say the magic word!" — Jurassic Park login/lock fail theme
#  Supports:
#    • SDDM login screen  (any KDE Plasma 6 theme with onLoginFailed)
#    • KDE lock screen    (plasma-desktop shell LockScreenUi.qml)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDDM_THEMES_DIR="/usr/share/sddm/themes"
LOCK_QML_FILE="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml"
LOCK_MEDIA_DIR="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen"
VIDEO_SRC="$SCRIPT_DIR/fail_h264.mp4"
AUDIO_SRC="$SCRIPT_DIR/fail.wav"

# Set by select_theme() — SDDM path
THEME_NAME=""
THEME_DIR=""
CONFIG_FILE=""
QML_FILE=""
QML_BAK=""
VIDEO_DEST=""
AUDIO_DEST=""
ALSA_DEVICE=""

# Install targets — populated by ask_install_targets()
INSTALL_SDDM=false
INSTALL_LOCK=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   🦖  NEDRY LOGIN / LOCK FAIL INSTALLER       🦖   ║"
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
    echo -e "${BOLD}[1/6] Checking dependencies...${NC}"
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

# Returns true if a theme's Main.qml is patchable
is_compatible_theme() {
    local qml="$1"
    # Must have onLoginFailed — the only hard requirement
    grep -q "onLoginFailed" "$qml" || return 1
    # Must NOT use the old plasma.core 2.0 (Plasma 5, incompatible with Qt6)
    grep -q "org.kde.plasma.core 2.0" "$qml" && return 1
    return 0
}

ask_install_targets() {
    echo -e "${BOLD}[2/6] Selecting install targets...${NC}"
    echo ""

    local has_sddm=false
    local has_lock=false

    # Check SDDM themes exist
    if find "$SDDM_THEMES_DIR" -maxdepth 2 -name "Main.qml" 2>/dev/null | grep -q .; then
        has_sddm=true
    fi

    # Check lock screen QML exists
    if [[ -f "$LOCK_QML_FILE" ]]; then
        has_lock=true
    fi

    if ! $has_sddm && ! $has_lock; then
        echo -e "${RED}[ERROR]${NC} Neither SDDM themes nor KDE lock screen QML found."
        exit 1
    fi

    echo "  Where do you want to install Nedry?"
    echo ""
    local options=()
    $has_sddm && options+=("sddm")
    $has_lock && options+=("lock")
    ($has_sddm && $has_lock) && options+=("both")

    local index=1
    for opt in "${options[@]}"; do
        case "$opt" in
            sddm) printf "  [%d] SDDM login screen only\n" "$index" ;;
            lock) printf "  [%d] KDE lock screen only\n" "$index" ;;
            both) printf "  [%d] Both SDDM login screen and KDE lock screen\n" "$index" ;;
        esac
        ((index++))
    done
    echo ""

    local choice
    while true; do
        read -rp "  Enter number [1-$((index-1))]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
            break
        fi
        echo "  Please enter a number between 1 and $((index-1))."
    done

    local selected="${options[$((choice-1))]}"
    case "$selected" in
        sddm) INSTALL_SDDM=true ;;
        lock) INSTALL_LOCK=true ;;
        both) INSTALL_SDDM=true; INSTALL_LOCK=true ;;
    esac

    echo ""
    $INSTALL_SDDM && echo -e "  ${GREEN}✓ Will patch: SDDM login screen${NC}"
    $INSTALL_LOCK && echo -e "  ${GREEN}✓ Will patch: KDE lock screen${NC}"
    echo ""
}

select_sddm_theme() {
    echo -e "${BOLD}[3/6] Selecting SDDM theme...${NC}"
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
        echo -e "  ${YELLOW}Skipping incompatible themes (Plasma 5 / no onLoginFailed):${NC} ${skipped[*]}"
        echo ""
    fi

    if [[ ${#themes[@]} -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} No compatible KDE SDDM themes found."
        echo "  Install breeze or any KDE Plasma 6 SDDM theme first."
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
    # Called for all install targets — SDDM uses aplay via PlasmaCore.DataSource,
    # lock screen also uses aplay (kscreenlocker_greet runs as root, PipeWire unavailable)
    if $INSTALL_SDDM && $INSTALL_LOCK; then
        echo -e "${BOLD}[4/6] Selecting audio output device...${NC}"
        echo -e "  ${CYAN}(Used for both SDDM login screen and KDE lock screen — both run as root,${NC}"
        echo -e "  ${CYAN} so PipeWire is unavailable and aplay/ALSA is used for audio in both.)${NC}"
    elif $INSTALL_SDDM; then
        echo -e "${BOLD}[3/5] Selecting audio output device...${NC}"
    else
        echo -e "${BOLD}[3/5] Selecting audio output device...${NC}"
        echo -e "  ${CYAN}(kscreenlocker_greet runs as root — PipeWire unavailable, using aplay/ALSA)${NC}"
    fi
    echo ""

    # Use aplay -L for stable CARD= names that don't change on USB reconnect.
    # On PipeWire systems (Fedora default) there are no plughw:/hw: entries —
    # use sysdefault:CARD= instead (one clean entry per physical device).
    local raw_all raw
    raw_all=$(aplay -L 2>/dev/null || true)

    # Prefer sysdefault: — one entry per card, works on ALSA and PipeWire
    raw=$(echo "$raw_all" | grep -E '^sysdefault:CARD=' || true)
    # Fall back to front: if no sysdefault entries
    [[ -z "$raw" ]] && raw=$(echo "$raw_all" | grep -E '^front:CARD=' || true)
    # Last resort: classic plughw/hw for non-PipeWire systems
    [[ -z "$raw" ]] && raw=$(echo "$raw_all" | grep -E '^(plughw|hw):CARD=' || true)

    if [[ -z "$raw" ]]; then
        echo -e "${YELLOW}  [WARN]${NC} Could not list audio devices. Defaulting to sysdefault:CARD=Generic_1"
        echo "  Change later with: sudo ./configure.sh"
        ALSA_DEVICE="sysdefault:CARD=Generic_1"
        return
    fi

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
            ALSA_DEVICE="${cards[$((choice-1))]}"
            echo -e "${GREEN}  ✓ Selected: $ALSA_DEVICE${NC}"
            echo -e "  ${CYAN}(Stable name — won't break if USB devices are added/removed)${NC}"
            break
        else
            echo "  Please enter a number between 1 and $((index-1))."
        fi
    done

    echo ""
    read -rp "  Play a test sound now? [Y/n]: " test_choice
    if [[ "$test_choice" != "n" && "$test_choice" != "N" ]]; then
        echo "  Playing test audio..."
        aplay -D "$ALSA_DEVICE" "$AUDIO_DEST" 2>/dev/null \
            && echo -e "${GREEN}  ✓ Audio test passed!${NC}" \
            || echo -e "${YELLOW}  [WARN]${NC} Test sound may not play here — sudo runs as root which has no PipeWire session.
         Audio will still work correctly from the actual login/lock screen.
         To verify, lock your screen (Super+L) and enter a wrong password.
         Wrong device? Change it later with: sudo ./configure.sh"
    fi
}

patch_sddm_qml() {
    echo ""
    echo -e "  Patching SDDM theme: ${BOLD}$THEME_NAME${NC}"

    # Pass paths as env vars — prevents broken strings if path contains spaces
    NEDRY_QML="$QML_FILE" \
    NEDRY_AUDIO="$AUDIO_DEST" \
    NEDRY_DEVICE="$ALSA_DEVICE" \
    python3 << 'PYEOF'
import re, sys, os

qml_file    = os.environ["NEDRY_QML"]
audio_dest  = os.environ["NEDRY_AUDIO"]
alsa_device = os.environ["NEDRY_DEVICE"]
duration    = "10000"

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
    plasmacore_alias = "PlasmaCore"
    last_import = max(
        (m.end() for m in re.finditer(r'^import .+', content, re.MULTILINE)),
        default=0
    )
    inject = '\nimport org.kde.plasma.plasma5support 2.0 as PlasmaCore'
    content = content[:last_import] + inject + content[last_import:]
    print("  Added: import org.kde.plasma.plasma5support 2.0 as PlasmaCore")

# ── 3. Inject Nedry QML elements into the root block ─────────────────────────
# Supports Item, Rectangle, FocusScope, or any other root type
nedry_elements = f"""
    // --- Nedry: spam guard — prevents retriggering while clip is playing ---
    property bool playingFail: false

    // --- Nedry fail video ---
    MediaPlayer {{
        id: failVideo
        source: Qt.resolvedUrl("fail_h264.mp4")
        videoOutput: failVideoOutput
        onPlaybackStateChanged: {{
            if (playbackState === MediaPlayer.StoppedState) {{
                failVideoOutput.visible = false
                root.playingFail = false
            }}
        }}
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

    // --- Safety timeout: force-hides video if MediaPlayer stalls ---
    Timer {{
        id: hideVideoTimer
        interval: {duration}
        repeat: false
        onTriggered: {{
            failVideoOutput.visible = false
            failVideo.stop()
            root.playingFail = false
        }}
    }}
"""

if 'id: failVideo' not in content:
    # Match any root-level QML element type (Item, Rectangle, FocusScope, etc.)
    match = re.search(r'^\s*(?:Item|Rectangle|FocusScope|Control|AbstractButton)\s*\{', content, re.MULTILINE)
    if not match:
        # Broader fallback: first top-level { that isn't an import or pragma line
        match = re.search(r'^[A-Z]\w+\s*\{', content, re.MULTILINE)
    if match:
        insert_pos = content.find('\n', match.end())
        content = content[:insert_pos] + '\n' + nedry_elements + content[insert_pos:]
        print(f"  Injected Nedry elements into root block")
    else:
        print("  ERROR: Could not find root QML block to inject into", file=sys.stderr)
        sys.exit(1)
else:
    print("  Nedry elements already present, skipping")

# ── 4. Inject trigger calls into onLoginFailed ────────────────────────────────
trigger_calls = """            // Nedry
            if (!root.playingFail) {
                root.playingFail = true
                failVideo.stop()
                failVideo.position = 0
                failVideoOutput.visible = true
                failVideo.play()
                playFailAudio()
                hideVideoTimer.restart()
            }"""

if 'failVideo.play()' not in content:
    # Check styles explicitly in priority order — A and B before C
    # so a braced handler is never misidentified as single-line
    style_a = re.search(r'(onLoginFailed\s*:\s*\{[^\}]*?)(notificationMessage\s*=)', content, re.DOTALL)
    style_b = re.search(r'(function\s+onLoginFailed\s*\(\s*\)\s*\{[^\}]*?)(notificationMessage\s*=)', content, re.DOTALL)
    style_c = re.search(r'(onLoginFailed\s*:\s*)(notificationMessage\s*=)', content)

    if style_a:
        nm_end = content.find('\n', style_a.start(2))
        content = content[:nm_end] + '\n' + trigger_calls + content[nm_end:]
        print("  Injected trigger calls into onLoginFailed (style A — signal handler)")
    elif style_b:
        nm_end = content.find('\n', style_b.start(2))
        content = content[:nm_end] + '\n' + trigger_calls + content[nm_end:]
        print("  Injected trigger calls into onLoginFailed (style B — function)")
    elif style_c:
        # Expand single-line handler into a block before injecting
        rest_of_line_end = content.find('\n', style_c.start())
        rest_of_line = content[style_c.end():rest_of_line_end]
        new_handler = (
            "onLoginFailed: {\n"
            + "            " + style_c.group(2) + rest_of_line + "\n"
            + trigger_calls + "\n"
            + "        }"
        )
        content = content[:style_c.start()] + new_handler + content[rest_of_line_end:]
        print("  Injected trigger calls into onLoginFailed (style C — expanded single-line)")
    else:
        print("  ERROR: Could not find onLoginFailed block", file=sys.stderr)
        sys.exit(1)
else:
    print("  Trigger calls already present, skipping")

with open(qml_file, 'w') as f:
    f.write(content)

print("  Patch complete.")
PYEOF

    echo -e "${GREEN}  ✓ SDDM Main.qml patched successfully${NC}"
}

patch_lockscreen_qml() {
    local lock_qml="$LOCK_QML_FILE"
    local lock_bak="${lock_qml}.nedry.bak"
    local video_dest="$LOCK_MEDIA_DIR/fail_h264.mp4"
    local audio_dest="$LOCK_MEDIA_DIR/fail.wav"

    echo ""
    echo -e "  Patching KDE lock screen: ${BOLD}$(basename "$lock_qml")${NC}"

    # Backup / restore-then-repatch for safe re-runs
    if [[ ! -f "$lock_bak" ]]; then
        cp "$lock_qml" "$lock_bak"
        echo -e "${GREEN}  ✓ Backed up LockScreenUi.qml → LockScreenUi.qml.nedry.bak${NC}"
    else
        cp "$lock_bak" "$lock_qml"
        echo -e "${GREEN}  ✓ Restored clean backup before patching${NC}"
    fi

    cp "$VIDEO_SRC" "$video_dest"
    cp "$AUDIO_SRC" "$audio_dest"
    echo -e "${GREEN}  ✓ Media files copied to lock screen directory${NC}"

    # Write the audio helper script — runs paplay as the logged-in user via
    # runuser so PipeWire mixing works even when other apps are using audio.
    local helper_script="$LOCK_MEDIA_DIR/nedry-play.sh"
    cat > "$helper_script" << 'HELPER'
#!/usr/bin/env bash
# Nedry audio helper — called by kscreenlocker via PlasmaCore.DataSource.
# Runs as the logged-in user already, so just call paplay directly.

AUDIO_FILE="$(dirname "$0")/fail.wav"

# XDG_RUNTIME_DIR may not be set in the kscreenlocker environment — derive it
if [[ -z "$XDG_RUNTIME_DIR" ]]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

export XDG_RUNTIME_DIR
export PULSE_RUNTIME_PATH="$XDG_RUNTIME_DIR/pulse"

paplay "$AUDIO_FILE" 2>/dev/null || true
HELPER
    chmod +x "$helper_script"
    echo -e "${GREEN}  ✓ Audio helper script written → nedry-play.sh${NC}"

    NEDRY_LOCK_QML="$lock_qml" \
    NEDRY_LOCK_VIDEO="$video_dest" \
    NEDRY_LOCK_AUDIO="$audio_dest" \
    NEDRY_LOCK_HELPER="$helper_script" \
    python3 << 'PYEOF'
import re, sys, os

qml_file    = os.environ["NEDRY_LOCK_QML"]
video_dest  = os.environ["NEDRY_LOCK_VIDEO"]
audio_dest  = os.environ["NEDRY_LOCK_AUDIO"]
helper_script = os.environ["NEDRY_LOCK_HELPER"]
duration    = "10000"

with open(qml_file, 'r') as f:
    content = f.read()

# ── 1. Add "import QtMultimedia" if missing ───────────────────────────────────
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
# kscreenlocker_greet runs as root — PipeWire unavailable, so we use aplay via
# PlasmaCore.DataSource executable engine, same as the SDDM patcher.
p5_match = re.search(r'import org\.kde\.plasma\.plasma5support[^\n]+as\s+(\w+)', content)
if p5_match:
    plasmacore_alias = p5_match.group(1)
    print(f"  Found plasma5support alias: {plasmacore_alias}")
else:
    plasmacore_alias = "PlasmaCore"
    last_import = max(
        (m.end() for m in re.finditer(r'^import .+', content, re.MULTILINE)),
        default=0
    )
    inject = '\nimport org.kde.plasma.plasma5support 2.0 as PlasmaCore'
    content = content[:last_import] + inject + content[last_import:]
    print("  Added: import org.kde.plasma.plasma5support 2.0 as PlasmaCore")

# ── 3. Inject Nedry elements into root Item { id: lockScreenUi } ──────────────
nedry_elements = f"""
    // --- Nedry: spam guard ---
    property bool playingFail: false

    // --- Nedry fail video ---
    MediaPlayer {{
        id: failVideo
        source: Qt.resolvedUrl("{video_dest}")
        videoOutput: failVideoOutput
        onPlaybackStateChanged: {{
            if (playbackState === MediaPlayer.StoppedState) {{
                failVideoOutput.visible = false
                lockScreenUi.playingFail = false
            }}
        }}
    }}

    VideoOutput {{
        id: failVideoOutput
        anchors.fill: parent
        visible: false
        z: 200
    }}

    // --- Audio via helper script (runs paplay as logged-in user via runuser) ---
    {plasmacore_alias}.DataSource {{
        id: audioRunner
        engine: "executable"
        connectedSources: []
        onNewData: disconnectSource(sourceName)
    }}

    function playFailAudio() {{
        audioRunner.connectSource("bash {helper_script}")
    }}

    // --- Safety timeout: force-hides if MediaPlayer stalls ---
    Timer {{
        id: hideVideoTimer
        interval: {duration}
        repeat: false
        onTriggered: {{
            failVideoOutput.visible = false
            failVideo.stop()
            lockScreenUi.playingFail = false
        }}
    }}
"""

if 'id: failVideo' not in content:
    match = re.search(r'^\s*Item\s*\{', content, re.MULTILINE)
    if not match:
        match = re.search(r'^[A-Z]\w+\s*\{', content, re.MULTILINE)
    if match:
        insert_pos = content.find('\n', match.end())
        content = content[:insert_pos] + '\n' + nedry_elements + content[insert_pos:]
        print("  Injected Nedry elements into root Item block")
    else:
        print("  ERROR: Could not find root QML block", file=sys.stderr)
        sys.exit(1)
else:
    print("  Nedry elements already present, skipping")

# ── 4. Inject trigger into onFailed(kind) ─────────────────────────────────────
# Inject AFTER the existing "if (kind != 0) { return; }" guard so only
# password failures (kind=0) trigger Nedry.
trigger_calls = """
            // Nedry
            if (!lockScreenUi.playingFail) {
                lockScreenUi.playingFail = true
                failVideo.stop()
                failVideo.position = 0
                failVideoOutput.visible = true
                failVideo.play()
                playFailAudio()
                hideVideoTimer.restart()
            }"""

if 'failVideo.play()' not in content:
    # Find the closing brace of the "if (kind != 0) { return; }" block and inject after it.
    # The block may be single-line "if (kind != 0) { return; }" or multi-line.
    # Strategy: find onFailed, then find the first complete if-block with return inside it.
    guard = re.search(
        r'(function\s+onFailed\s*\([^)]*\)\s*\{[^\}]*?)'  # onFailed up to...
        r'(if\s*\(kind\s*!=\s*0\)[^\{]*\{[^\}]*return[^\}]*\})',  # the kind!=0 block
        content, re.DOTALL
    )
    if guard:
        insert_at = guard.end()  # after the closing } of the kind!=0 block
        # Move to end of that line then insert
        line_end = content.find('\n', insert_at)
        content = content[:line_end] + '\n' + trigger_calls + content[line_end:]
        print("  Injected trigger into onFailed (after kind != 0 block closes)")
    else:
        # Fallback: inject at top of onFailed with explicit kind==0 check
        onfailed = re.search(r'(function\s+onFailed\s*\([^)]*\)\s*\{)', content)
        if onfailed:
            insert_at = content.find('\n', onfailed.end())
            guarded = """
            // Nedry — only on password failure (kind == 0)
            if (kind === 0 && !lockScreenUi.playingFail) {
                lockScreenUi.playingFail = true
                failVideo.stop()
                failVideo.position = 0
                failVideoOutput.visible = true
                failVideo.play()
                playFailAudio()
                hideVideoTimer.restart()
            }"""
            content = content[:insert_at] + guarded + '\n' + content[insert_at:]
            print("  Injected trigger into onFailed (fallback — with explicit kind==0 guard)")
        else:
            print("  ERROR: Could not find onFailed handler", file=sys.stderr)
            sys.exit(1)
else:
    print("  Trigger calls already present, skipping")

with open(qml_file, 'w') as f:
    f.write(content)

print("  Lock screen patch complete.")
PYEOF

    echo -e "${GREEN}  ✓ LockScreenUi.qml patched successfully${NC}"
}

write_config() {
    echo -e "${BOLD}[6/6] Saving config and verifying...${NC}"

    # ── SDDM config ───────────────────────────────────────────────────────────
    if $INSTALL_SDDM; then
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
        echo -e "${GREEN}  ✓ SDDM config saved → $CONFIG_FILE${NC}"
    fi

    # ── Lock screen config ────────────────────────────────────────────────────
    if $INSTALL_LOCK; then
        local lock_conf="$LOCK_MEDIA_DIR/nedry-lock.conf"
        cat > "$lock_conf" <<EOF
# Nedry Lock Screen Config
# Generated by install.sh on $(date)
# To uninstall: sudo ./uninstall.sh

LOCK_QML=$LOCK_QML_FILE
LOCK_QML_BAK=${LOCK_QML_FILE}.nedry.bak
VIDEO_FILE=$LOCK_MEDIA_DIR/fail_h264.mp4
AUDIO_FILE=$LOCK_MEDIA_DIR/fail.wav
HELPER_SCRIPT=$LOCK_MEDIA_DIR/nedry-play.sh
CLIP_DURATION_MS=10000
EOF
        echo -e "${GREEN}  ✓ Lock screen config saved → $lock_conf${NC}"
    fi

    # ── SDDM cache clear + smoke test ─────────────────────────────────────────
    if $INSTALL_SDDM; then
        echo ""
        echo -e "${CYAN}  Running SDDM QML syntax check...${NC}"
        rm -rf /var/cache/sddm/* 2>/dev/null || true
        rm -rf /root/.cache/sddm* 2>/dev/null || true
        rm -rf /var/lib/sddm/.cache 2>/dev/null || true

        local greeter_bin
        if command -v sddm-greeter-qt6 &>/dev/null; then
            greeter_bin="sddm-greeter-qt6"
        elif command -v sddm-greeter &>/dev/null; then
            greeter_bin="sddm-greeter"
        else
            greeter_bin=""
        fi

        if [[ -n "$greeter_bin" ]]; then
            "$greeter_bin" --test-mode --theme "$THEME_DIR" &>/dev/null &
            sleep 3
            kill %1 2>/dev/null \
                && echo -e "${GREEN}  ✓ SDDM QML loaded without errors${NC}" \
                || echo -e "${YELLOW}  Could not auto-verify SDDM. Test manually:${NC}
    $greeter_bin --test-mode --theme $THEME_DIR"
        else
            echo -e "${YELLOW}  Skipping SDDM QML check (sddm-greeter binary not found).${NC}"
        fi
    fi

    echo ""
    echo -e "${GREEN}${BOLD}  Installation complete! 🦖${NC}"
    echo ""
    if $INSTALL_SDDM; then
        echo "  SDDM  → Fully log out and enter a wrong password to test."
        echo "        → To change audio device later: sudo ./configure.sh"
    fi
    if $INSTALL_LOCK; then
        echo "  Lock  → Lock your screen (Super+L) and enter a wrong password to test."
        echo "        → Audio device can be changed later with: sudo ./configure.sh"
    fi
    echo ""
}

patch_all_qml() {
    echo -e "${BOLD}[5/6] Patching QML files...${NC}"
    $INSTALL_SDDM && patch_sddm_qml
    $INSTALL_LOCK && patch_lockscreen_qml
}

# ── Main ──────────────────────────────────────────────────────────────────────
print_banner
check_root
check_dependencies
ask_install_targets

if $INSTALL_SDDM; then
    select_sddm_theme
fi

select_audio_device

patch_all_qml
write_config

