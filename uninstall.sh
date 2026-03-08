#!/usr/bin/env bash
# =============================================================================
#  Nedry SDDM Uninstaller
#  Restores the original Main.qml and removes all Nedry files
# =============================================================================

set -e

SDDM_THEMES_DIR="/usr/share/sddm/themes"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════╗"
    echo "  ║   🦖  NEDRY SDDM UNINSTALLER                  🦖  ║"
    echo "  ║      Restoring your theme to its original state   ║"
    echo "  ╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR]${NC} Please run with sudo: sudo ./uninstall.sh"
        exit 1
    fi
}

find_installed_themes() {
    local found=()
    while IFS= read -r conf; do
        found+=("$(dirname "$conf")")
    done < <(find "$SDDM_THEMES_DIR" -maxdepth 2 -name "nedry.conf" 2>/dev/null)
    echo "${found[@]}"
}

uninstall_theme() {
    local theme_dir="$1"
    local theme_name
    theme_name=$(basename "$theme_dir")
    local qml="$theme_dir/Main.qml"
    local bak="$theme_dir/Main.qml.bak"
    local conf="$theme_dir/nedry.conf"
    local video="$theme_dir/fail_h264.mp4"
    local audio="$theme_dir/fail.wav"

    echo -e "${BOLD}Uninstalling from: $theme_name${NC}"

    if [[ -f "$bak" ]]; then
        cp "$bak" "$qml"
        rm "$bak"
        echo -e "${GREEN}  ✓ Restored original Main.qml${NC}"
    else
        echo -e "${YELLOW}  [WARN]${NC} No backup found at $bak — Main.qml was not restored."
        echo "         You may need to reinstall the theme manually."
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

# Fix for the multi-theme selection — wrapped in a function so 'local' is valid
select_and_uninstall() {
    local installed=("$@")

    if [[ ${#installed[@]} -eq 1 ]]; then
        echo -e "  Found Nedry installed in: ${BOLD}$(basename "${installed[0]}")${NC}"
        echo ""
        local confirm
        read -rp "  Uninstall? [Y/n]: " confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            echo "  Aborted."
            exit 0
        fi
        uninstall_theme "${installed[0]}"
    else
        echo "  Found Nedry installed in multiple themes:"
        echo ""
        for i in "${!installed[@]}"; do
            printf "  [%d] %s\n" "$((i+1))" "$(basename "${installed[$i]}")"
        done
        printf "  [%d] All of the above\n" "$((${#installed[@]}+1))"
        echo ""
        local choice
        while true; do
            read -rp "  Which to uninstall? [1-$((${#installed[@]}+1))]: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#installed[@]}+1 )); then
                break
            else
                echo "  Please enter a valid number."
            fi
        done

        if (( choice == ${#installed[@]}+1 )); then
            for dir in "${installed[@]}"; do
                uninstall_theme "$dir"
            done
        else
            uninstall_theme "${installed[$((choice-1))]}"
        fi
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
print_banner
check_root

read -ra installed <<< "$(find_installed_themes)"

if [[ ${#installed[@]} -eq 0 ]]; then
    echo -e "${YELLOW}  No Nedry installations found in $SDDM_THEMES_DIR${NC}"
    echo "  Nothing to uninstall."
    exit 0
fi

select_and_uninstall "${installed[@]}"

echo -e "${GREEN}${BOLD}  Uninstall complete!${NC}"
echo "  Your original SDDM theme has been restored."
echo ""
