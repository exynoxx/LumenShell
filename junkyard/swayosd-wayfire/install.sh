#!/usr/bin/env bash
# Ready-to-run setup of SwayOSD for Wayfire.
# Installs the daemon, the backlight udev rule, and merges keybinds into
# ~/.config/wayfire.ini.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET="$HERE/wayfire.ini.snippet"
UDEV_RULE_SRC="$HERE/99-swayosd-backlight.rules"
UDEV_RULE_DST="/etc/udev/rules.d/99-swayosd-backlight.rules"
WAYFIRE_INI="${XDG_CONFIG_HOME:-$HOME/.config}/wayfire.ini"
BEGIN_MARK="# >>> swayosd-wayfire BEGIN"
END_MARK="# >>> swayosd-wayfire END"

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

need_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

detect_distro() {
    [ -r /etc/os-release ] || die "Cannot read /etc/os-release"
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
        *fedora*)            echo fedora ;;
        *arch*|*manjaro*)    echo arch ;;
        *debian*|*ubuntu*)   echo debian ;;
        *)                   die "Unsupported distro: ${ID:-unknown}" ;;
    esac
}

install_packages() {
    case "$1" in
        fedora)
            need_sudo dnf install -y swayosd brightnessctl
            ;;
        arch)
            if pacman -Si swayosd >/dev/null 2>&1; then
                need_sudo pacman -S --needed --noconfirm swayosd brightnessctl
            else
                warn "swayosd not in official repos — install from AUR (e.g. 'yay -S swayosd-git') and re-run."
                need_sudo pacman -S --needed --noconfirm brightnessctl
            fi
            ;;
        debian)
            # SwayOSD is not in Debian/Ubuntu repos as of writing.
            need_sudo apt-get update
            need_sudo apt-get install -y brightnessctl
            if ! command -v swayosd-server >/dev/null 2>&1; then
                warn "swayosd-server not found. Debian/Ubuntu have no swayosd package."
                warn "Build from source: https://github.com/ErikReider/SwayOSD"
            fi
            ;;
    esac
}

install_udev_rule() {
    log "Installing udev rule -> $UDEV_RULE_DST"
    need_sudo install -m 0644 "$UDEV_RULE_SRC" "$UDEV_RULE_DST"
    need_sudo udevadm control --reload
    need_sudo udevadm trigger --subsystem-match=backlight --action=add || true
    need_sudo udevadm trigger --subsystem-match=leds --action=add || true
}

add_user_to_video_group() {
    if id -nG "$USER" | tr ' ' '\n' | grep -qx video; then
        log "User '$USER' already in 'video' group."
    else
        log "Adding '$USER' to 'video' group (re-login required)."
        need_sudo usermod -aG video "$USER"
        warn "Log out and back in for group membership to apply."
    fi
}

merge_wayfire_ini() {
    mkdir -p "$(dirname "$WAYFIRE_INI")"
    touch "$WAYFIRE_INI"

    if grep -qF "$BEGIN_MARK" "$WAYFIRE_INI"; then
        log "Updating existing swayosd-wayfire block in $WAYFIRE_INI"
        # Delete old block (between markers, inclusive).
        sed -i "/$BEGIN_MARK/,/$END_MARK/d" "$WAYFIRE_INI"
    else
        log "Appending swayosd-wayfire block to $WAYFIRE_INI"
    fi

    # Ensure a separating blank line, then append snippet.
    if [ -s "$WAYFIRE_INI" ] && [ -n "$(tail -c1 "$WAYFIRE_INI")" ]; then
        printf '\n' >>"$WAYFIRE_INI"
    fi
    printf '\n' >>"$WAYFIRE_INI"
    cat "$SNIPPET" >>"$WAYFIRE_INI"
}

main() {
    [ -f "$SNIPPET" ] || die "Missing $SNIPPET"
    [ -f "$UDEV_RULE_SRC" ] || die "Missing $UDEV_RULE_SRC"

    local distro
    distro="$(detect_distro)"
    log "Detected distro: $distro"

    install_packages "$distro"
    install_udev_rule
    add_user_to_video_group
    merge_wayfire_ini

    cat <<EOF

Done.

Next:
  1. Log out / back in if you were just added to the 'video' group.
  2. Start (or restart) Wayfire.
  3. Press a volume or brightness key — an OSD popup should appear.

Test from a terminal inside Wayfire:
  swayosd-client --output-volume raise
  swayosd-client --brightness raise
EOF
}

main "$@"
