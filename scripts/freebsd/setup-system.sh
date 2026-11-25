#!/bin/sh
#
# setup-system.sh — one-time FreeBSD system setup for a LumenShell session.
#
# On Linux, systemd + udev + logind do all of this implicitly. On FreeBSD it is
# plain rc.conf(5)/devfs.rules(5)/syslog.conf(5) configuration, which this
# script applies idempotently (re-running it changes nothing). It never adds
# anyone to `wheel` and only edits a file after copying it to <file>.lumenshell.bak.
#
#   doas scripts/freebsd/setup-system.sh [-n] [-u user] [-w wifi_group]
#                                        [--drm i915kms|amdgpu|radeonkms]
#                                        [--pam-xdg]
#
#   -n               dry run: print what would change
#   -u user          the desktop user (default: $DOAS_USER / $SUDO_USER)
#   -w group         group allowed to drive wpa_supplicant (default: wheel)
#   --drm module     add the DRM driver from graphics/drm-kmod to kld_list
#   --pam-xdg        add pam_xdg(8) (FreeBSD 14.1+) to /etc/pam.d/system so
#                    logins get XDG_RUNTIME_DIR; start-lumenshell otherwise
#                    falls back to a private dir in /tmp
#
set -eu

DRY=0
USER_NAME="${DOAS_USER:-${SUDO_USER:-}}"
WIFI_GROUP=wheel
DRM=""
PAM_XDG=0

while [ $# -gt 0 ]; do
    case "$1" in
        -n) DRY=1 ;;
        -u) USER_NAME="$2"; shift ;;
        -w) WIFI_GROUP="$2"; shift ;;
        --drm) DRM="$2"; shift ;;
        --pam-xdg) PAM_XDG=1 ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

[ "$(uname -s)" = FreeBSD ] || { echo "This script is for FreeBSD." >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || { echo "Run as root (doas/sudo), or with -n." >&2; exit 1; }
[ -n "$USER_NAME" ] || { echo "Which user? Pass -u <user>." >&2; exit 2; }
id "$USER_NAME" >/dev/null 2>&1 || { echo "No such user: $USER_NAME" >&2; exit 2; }

LOCALBASE="${LOCALBASE:-/usr/local}"
here=$(cd "$(dirname "$0")" && pwd)
if [ -f "$here/devfs.rules" ]; then
    DATA="$here"                       # installed copy, beside its data
elif [ -d "$here/../../data/freebsd" ]; then
    DATA=$(cd "$here/../../data/freebsd" && pwd)
else
    DATA="$LOCALBASE/share/lumenshell/freebsd"
fi
[ -d "$DATA" ] || { echo "Cannot find data/freebsd (looked in $DATA)." >&2; exit 1; }

say()  { printf '==> %s\n' "$*"; }
run()  { if [ "$DRY" -eq 1 ]; then printf '    would run: %s\n' "$*"; else "$@"; fi; }
backup() { [ -f "$1" ] && [ ! -f "$1.lumenshell.bak" ] && run cp -p "$1" "$1.lumenshell.bak"; return 0; }
in_group() { id -Gn "$1" | tr ' ' '\n' | grep -qx "$2"; }

# --- groups -----------------------------------------------------------------
# video: DRM nodes and backlight(9). operator: shutdown(8) and zzz(8) when no
# ConsoleKit2 is running (LumenShell falls back to them).
for g in video operator; do
    if in_group "$USER_NAME" "$g"; then
        say "$USER_NAME already in $g"
    else
        say "adding $USER_NAME to $g"
        run pw groupmod "$g" -m "$USER_NAME"
    fi
done
if ! in_group "$USER_NAME" "$WIFI_GROUP"; then
    say "NOTE: $USER_NAME is not in '$WIFI_GROUP'; the Wi-Fi panel needs that group"
    say "      to talk to wpa_supplicant. Re-run with -w <group> to pick another one."
fi

# --- rc.conf services -------------------------------------------------------
# dbus: system bus (UPower, polkit, ConsoleKit2, AccountsService activate on it).
# seatd: seat/DRM/input access for Wayfire without running it as root.
for kv in dbus_enable=YES seatd_enable=YES; do
    name=${kv%%=*}
    if [ "$(sysrc -n "$name" 2>/dev/null || true)" = YES ]; then
        say "$name already set"
    else
        say "rc.conf: $kv"
        run sysrc "$kv"
    fi
done
if [ -n "$DRM" ]; then
    case " $(sysrc -n kld_list 2>/dev/null || true) " in
        *" $DRM "*) say "kld_list already has $DRM" ;;
        *) say "rc.conf: kld_list += $DRM"; run sysrc kld_list+="$DRM" ;;
    esac
fi

# --- devfs rules ------------------------------------------------------------
if grep -q '^\[lumenshell=' /etc/devfs.rules 2>/dev/null; then
    say "devfs.rules already has the lumenshell ruleset"
else
    say "appending the lumenshell ruleset to /etc/devfs.rules"
    backup /etc/devfs.rules
    if [ "$DRY" -eq 0 ]; then
        { echo; sed -n '/^\[lumenshell=/,$p' "$DATA/devfs.rules"; } >> /etc/devfs.rules
    fi
fi
current_rs=$(sysrc -n devfs_system_ruleset 2>/dev/null || true)
if [ -z "$current_rs" ]; then
    say "rc.conf: devfs_system_ruleset=lumenshell"
    run sysrc devfs_system_ruleset=lumenshell
    run service devfs restart
elif [ "$current_rs" != lumenshell ]; then
    say "NOTE: devfs_system_ruleset is '$current_rs'; copy the rules from"
    say "      [lumenshell] in /etc/devfs.rules into that ruleset."
fi

# --- syslog / newsyslog -----------------------------------------------------
# Wayfire autostarts the shell via `daemon -T lumen-…`; collect it in one log.
for d in syslog.d newsyslog.conf.d; do
    dst="$LOCALBASE/etc/$d/lumenshell.conf"
    if cmp -s "$DATA/$d/lumenshell.conf" "$dst" 2>/dev/null; then
        say "$dst up to date"
    else
        say "installing $dst"
        run install -d "$LOCALBASE/etc/$d"
        run install -m 0644 "$DATA/$d/lumenshell.conf" "$dst"
    fi
done
if [ ! -e /var/log/lumenshell.log ]; then
    run install -m 0644 /dev/null /var/log/lumenshell.log
fi
run service syslogd reload

# --- wpa_supplicant ---------------------------------------------------------
WPA=/etc/wpa_supplicant.conf
if [ ! -f "$WPA" ]; then
    say "creating $WPA (mode 0600)"
    if [ "$DRY" -eq 0 ]; then
        sed "s/^ctrl_interface_group=.*/ctrl_interface_group=$WIFI_GROUP/" \
            "$DATA/wpa_supplicant.conf.sample" > "$WPA"
        chmod 0600 "$WPA"
    fi
else
    need=""
    grep -q '^ctrl_interface=' "$WPA"       || need="$need ctrl_interface=/var/run/wpa_supplicant"
    grep -q '^ctrl_interface_group=' "$WPA" || need="$need ctrl_interface_group=$WIFI_GROUP"
    grep -q '^update_config=1' "$WPA"       || need="$need update_config=1"
    if [ -z "$need" ]; then
        say "$WPA already usable from the panel"
    else
        say "prepending to $WPA:$need"
        backup "$WPA"
        if [ "$DRY" -eq 0 ]; then
            tmp=$(mktemp)
            for line in $need; do echo "$line"; done > "$tmp"
            cat "$WPA" >> "$tmp"
            install -m 0600 "$tmp" "$WPA"
            rm -f "$tmp"
        fi
        say "restart Wi-Fi to apply: service netif restart <wlanN>"
    fi
fi

# --- pam_xdg (optional) -----------------------------------------------------
if [ "$PAM_XDG" -eq 1 ]; then
    if [ ! -e /usr/lib/pam_xdg.so ]; then
        say "pam_xdg.so not in base (needs FreeBSD 14.1+); skipped"
    elif grep -q 'pam_xdg.so' /etc/pam.d/system; then
        say "/etc/pam.d/system already runs pam_xdg"
    else
        say "adding pam_xdg to /etc/pam.d/system (session)"
        backup /etc/pam.d/system
        [ "$DRY" -eq 1 ] || printf 'session\t\toptional\tpam_xdg.so\n' >> /etc/pam.d/system
    fi
fi

say "done. Log out and back in for group changes; start the session with"
say "start-lumenshell (or pick LumenShell in your display manager)."
