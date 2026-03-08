#!/usr/bin/env bash
# =============================================================================
#  Nedry Uninstaller
#  Detects and removes SDDM login screen and/or KDE lock screen installations
# =============================================================================

set -e

SDDM_THEMES_DIR="/usr/share/sddm/themes"
LOCK_QML_FILE="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreenUi.qml"
LOCK_MEDIA_DIR="/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   🦖  NEDRY UNINSTALLER                       🦖  ║"
    echo "  ║      Restoring your system to its original state  ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./uninstall.sh"
        exit 1
    fi
}

# ── Detection ─────────────────────────────────────────────────────────────────

find_sddm_installs() {
    local found=()
    while IFS= read -r conf; do
        found+=("$(dirname "$conf")")
    done < <(find "$SDDM_THEMES_DIR" -maxdepth 2 -name "nedry.conf" 2>/dev/null)
    echo "${found[@]}"
}

lock_is_installed() {
    [[ -f "$LOCK_MEDIA_DIR/nedry-lock.conf" ]]
}

# ── Uninstall actions ─────────────────────────────────────────────────────────

uninstall_sddm_theme() {
    local theme_dir="$1"
    local theme_name
    theme_name=$(basename "$theme_dir")
    local qml="$theme_dir/Main.qml"
    local bak="$theme_dir/Main.qml.bak"
    local conf="$theme_dir/nedry.conf"
    local video="$theme_dir/fail_h264.mp4"
    local audio="$theme_dir/fail.wav"

    echo -e "${BOLD}  Uninstalling SDDM: $theme_name${NC}"

    if [[ -f "$bak" ]]; then
        cp "$bak" "$qml"
        rm "$bak"
        echo -e "${GREEN}  ✓ Restored original Main.qml${NC}"
    else
        echo -e "${YELLOW}  [WARN]${NC} No backup found at $bak — Main.qml was not restored."
        echo "         You may need to reinstall the SDDM theme manually."
    fi

    for f in "$video" "$audio" "$conf"; do
        if [[ -f "$f" ]]; then
            rm "$f"
            echo -e "${GREEN}  ✓ Removed $(basename "$f")${NC}"
        fi
    done

    rm -rf /var/cache/sddm/* 2>/dev/null || true
    rm -rf /root/.cache/sddm* 2>/dev/null || true
    rm -rf /var/lib/sddm/.cache 2>/dev/null || true
    echo -e "${GREEN}  ✓ Cleared SDDM cache${NC}"
    echo ""
}

uninstall_lockscreen() {
    local bak="${LOCK_QML_FILE}.nedry.bak"
    local conf="$LOCK_MEDIA_DIR/nedry-lock.conf"
    local video="$LOCK_MEDIA_DIR/fail_h264.mp4"
    local audio="$LOCK_MEDIA_DIR/fail.wav"
    local helper="$LOCK_MEDIA_DIR/nedry-play.sh"

    echo -e "${BOLD}  Uninstalling KDE lock screen${NC}"

    if [[ -f "$bak" ]]; then
        cp "$bak" "$LOCK_QML_FILE"
        rm "$bak"
        echo -e "${GREEN}  ✓ Restored original LockScreenUi.qml${NC}"
    else
        echo -e "${YELLOW}  [WARN]${NC} No backup found at $bak — LockScreenUi.qml was not restored."
        echo "         You may need to reinstall plasma-workspace manually."
    fi

    for f in "$video" "$audio" "$helper" "$conf"; do
        if [[ -f "$f" ]]; then
            rm "$f"
            echo -e "${GREEN}  ✓ Removed $(basename "$f")${NC}"
        fi
    done

    echo ""
}

# ── Selection logic ───────────────────────────────────────────────────────────
select_and_uninstall() {
    local sddm_dirs=("$@")
    local has_sddm=$(( ${#sddm_dirs[@]} > 0 ? 1 : 0 ))
    local has_lock=0
    lock_is_installed && has_lock=1

    # Build menu options
    local options=()
    if (( has_sddm )); then
        if [[ ${#sddm_dirs[@]} -eq 1 ]]; then
            options+=("sddm:${sddm_dirs[0]}")
        else
            for dir in "${sddm_dirs[@]}"; do
                options+=("sddm:$dir")
            done
            options+=("sddm_all")
        fi
    fi
    (( has_lock )) && options+=("lock")
    (( has_sddm && has_lock )) && options+=("both_all")

    # If there's only one thing installed and it's a single SDDM theme, just confirm
    if [[ ${#options[@]} -eq 1 && "${options[0]}" == sddm:* ]]; then
        local theme_name
        theme_name=$(basename "${sddm_dirs[0]}")
        echo -e "  Found Nedry installed in SDDM theme: ${BOLD}$theme_name${NC}"
        echo ""
        local confirm
        read -rp "  Uninstall? [Y/n]: " confirm
        [[ "$confirm" == "n" || "$confirm" == "N" ]] && { echo "  Aborted."; exit 0; }
        uninstall_sddm_theme "${sddm_dirs[0]}"
        return
    fi

    # If there's only one thing and it's the lock screen, just confirm
    if [[ ${#options[@]} -eq 1 && "${options[0]}" == "lock" ]]; then
        echo -e "  Found Nedry installed in: ${BOLD}KDE lock screen${NC}"
        echo ""
        local confirm
        read -rp "  Uninstall? [Y/n]: " confirm
        [[ "$confirm" == "n" || "$confirm" == "N" ]] && { echo "  Aborted."; exit 0; }
        uninstall_lockscreen
        return
    fi

    # Multiple things — show a menu
    echo "  Found Nedry installed in:"
    echo ""
    local index=1
    for opt in "${options[@]}"; do
        case "$opt" in
            sddm:*)
                printf "  [%d] SDDM theme: %s\n" "$index" "$(basename "${opt#sddm:}")"
                ;;
            sddm_all)
                printf "  [%d] All SDDM themes\n" "$index"
                ;;
            lock)
                printf "  [%d] KDE lock screen\n" "$index"
                ;;
            both_all)
                printf "  [%d] Everything (all SDDM themes + lock screen)\n" "$index"
                ;;
        esac
        ((index++))
    done
    echo ""

    local choice
    while true; do
        read -rp "  Which to uninstall? [1-$((index-1))]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice < index )); then
            break
        fi
        echo "  Please enter a number between 1 and $((index-1))."
    done

    local selected="${options[$((choice-1))]}"
    case "$selected" in
        sddm:*)
            uninstall_sddm_theme "${selected#sddm:}"
            ;;
        sddm_all)
            for dir in "${sddm_dirs[@]}"; do
                uninstall_sddm_theme "$dir"
            done
            ;;
        lock)
            uninstall_lockscreen
            ;;
        both_all)
            for dir in "${sddm_dirs[@]}"; do
                uninstall_sddm_theme "$dir"
            done
            uninstall_lockscreen
            ;;
    esac
}

# ── Main ──────────────────────────────────────────────────────────────────────
print_banner
check_root

read -ra sddm_installs <<< "$(find_sddm_installs)"
has_lock=false
lock_is_installed && has_lock=true

if [[ ${#sddm_installs[@]} -eq 0 ]] && ! $has_lock; then
    echo -e "${YELLOW}  No Nedry installations found.${NC}"
    echo "  Nothing to uninstall."
    exit 0
fi

select_and_uninstall "${sddm_installs[@]}"

echo -e "${GREEN}${BOLD}  Uninstall complete!${NC}"
echo ""

