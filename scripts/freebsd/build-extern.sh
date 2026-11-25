#!/bin/sh
#
# build-extern.sh — build the external pieces LumenShell needs on FreeBSD
# that the pkg repository doesn't provide in the required version.
#
#   scripts/freebsd/build-extern.sh [-p prefix] [-j jobs] <target>...
#
# Targets:
#   wayfire           Wayfire 0.10.x against pkg wlroots019. The LumenShell
#                     Wayfire plugins are written against the 0.10 plugin API,
#                     while x11-wm/wayfire tracks newer releases (0.11 on
#                     wlroots 0.20). If the wayfire package is installed, this
#                     builds side by side into /usr/local/lumenshell (RPATH'd,
#                     so its libwf-config never clashes with the package's)
#                     and drops a start-lumenshell pre-start hook selecting it.
#   gtk4-layer-shell  Only needed if pkg's is older than 1.1 (1.1+ also
#                     carries the session-lock API lumen-lockscreen uses).
#   lumenshell        Configure, build and install this tree against the
#                     above (PKG_CONFIG_PATH set up for a side-by-side Wayfire).
#   all               wayfire, then lumenshell.
#
# Sources are fetched with git into ${LUMEN_BUILD_DIR:-~/.cache/lumenshell-build}.
# Installing uses doas or sudo when not run as root. Upstream needs no FreeBSD
# patches: Wayfire 0.10's own meson.build already links libinotify and
# libexecinfo on FreeBSD; what it needs is the right dependency set (below).
#
set -eu

WAYFIRE_TAG="${WAYFIRE_TAG:-v0.10.1}"
GTK4_LS_TAG="${GTK4_LS_TAG:-v1.3.0}"
LOCALBASE="${LOCALBASE:-/usr/local}"
BUILD_DIR="${LUMEN_BUILD_DIR:-$HOME/.cache/lumenshell-build}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 2)"
PREFIX=""

usage() { sed -n '2,32p' "$0"; exit "${1:-0}"; }

while getopts "p:j:h" opt; do
    case "$opt" in
        p) PREFIX="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 2 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || usage 2
[ "$(uname -s)" = FreeBSD ] || { echo "This script is for FreeBSD." >&2; exit 1; }

say() { printf '==> %s\n' "$*"; }
die() { printf 'build-extern: %s\n' "$*" >&2; exit 1; }

as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    elif command -v doas >/dev/null 2>&1; then doas "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else die "need root for: $*  (install security/doas or security/sudo)"
    fi
}

pkg_install() {
    missing=""
    for p in "$@"; do pkg info -e "$p" || missing="$missing $p"; done
    [ -z "$missing" ] && return 0
    say "installing packages:$missing"
    # shellcheck disable=SC2086
    as_root pkg install -y $missing
}

# Side by side with pkg's wayfire unless told otherwise.
wayfire_prefix() {
    if [ -n "$PREFIX" ]; then echo "$PREFIX"
    elif pkg info -e wayfire; then echo "$LOCALBASE/lumenshell"
    else echo "$LOCALBASE"
    fi
}

fetch() { # url tag dir
    if [ -d "$3/.git" ]; then
        say "updating $3 to $2"
        git -C "$3" fetch --depth 1 origin "refs/tags/$2:refs/tags/$2"
        git -C "$3" checkout -q "$2"
    else
        say "cloning $1 @ $2"
        git clone -q --depth 1 --branch "$2" "$1" "$3"
    fi
}

build_wayfire() {
    wp=$(wayfire_prefix)
    pkg_install git meson ninja pkgconf cmake wlroots019 wayland wayland-protocols \
        libinput libxkbcommon libevdev evdev-proto libinotify libudev-devd \
        pixman cairo pango libdrm mesa-libs png jpeg-turbo glm yyjson

    src="$BUILD_DIR/wayfire"
    mkdir -p "$BUILD_DIR"
    fetch https://github.com/WayfireWM/wayfire "$WAYFIRE_TAG" "$src"
    # wlroots comes from pkg (wlroots019); only the small WayfireWM helpers
    # are vendored. wf-config is too: pkg's wf-config is the 0.11 series.
    git -C "$src" submodule update --init --depth 1 \
        subprojects/wf-config subprojects/wf-utils subprojects/wf-touch

    set -- -Dprefix="$wp" -Dbuildtype=release \
        -Duse_system_wlroots=enabled -Duse_system_wfconfig=disabled \
        -Dxwayland=auto -Dtests=disabled
    # Base LLVM ships OpenMP only on some architectures (as x11-wm/wayfire checks).
    [ -e /usr/include/omp.h ] || set -- "$@" -Denable_openmp=false

    ldflags="-L$LOCALBASE/lib"
    if [ "$wp" != "$LOCALBASE" ]; then
        # Bake the private lib dir in, rather than ldconfig it: the package's
        # libwf-config would otherwise win the soname lookup.
        ldflags="$ldflags -Wl,-rpath,$wp/lib"
    fi

    say "configuring Wayfire $WAYFIRE_TAG for $wp"
    rm -rf "$src/build"
    LDFLAGS="$ldflags" meson setup "$src/build" "$src" "$@"
    ninja -C "$src/build" -j "$JOBS"
    say "installing Wayfire into $wp"
    as_root meson install -C "$src/build" --no-rebuild

    if [ "$wp" != "$LOCALBASE" ]; then
        hookdir="$LOCALBASE/etc/lumenshell/pre-start.d"
        say "writing $hookdir/50-wayfire-0.10.sh (selects this Wayfire for start-lumenshell)"
        tmp=$(mktemp)
        cat > "$tmp" <<HOOK
# Written by scripts/freebsd/build-extern.sh: LumenShell's Wayfire $WAYFIRE_TAG,
# installed beside the wayfire package. Sourced by start-lumenshell.
export WAYFIRE_BIN="$wp/bin/wayfire"
export PATH="$wp/bin:\$PATH"
export XDG_DATA_DIRS="$wp/share:\${XDG_DATA_DIRS:-$LOCALBASE/share:/usr/share}"
HOOK
        as_root install -d "$hookdir"
        as_root install -m 0644 "$tmp" "$hookdir/50-wayfire-0.10.sh"
        rm -f "$tmp"
    fi
    say "Wayfire: $("$wp/bin/wayfire" --version 2>/dev/null || echo installed)"
}

build_gtk4_layer_shell() {
    if pkg-config --atleast-version=1.1.0 gtk4-layer-shell-0 2>/dev/null; then
        say "gtk4-layer-shell $(pkg-config --modversion gtk4-layer-shell-0) is new enough; nothing to do"
        return 0
    fi
    pkg_install git meson ninja pkgconf vala gtk4 wayland wayland-protocols gobject-introspection
    src="$BUILD_DIR/gtk4-layer-shell"
    mkdir -p "$BUILD_DIR"
    fetch https://github.com/wmww/gtk4-layer-shell "$GTK4_LS_TAG" "$src"
    rm -rf "$src/build"
    meson setup "$src/build" "$src" -Dprefix="$LOCALBASE" -Dbuildtype=release \
        -Dintrospection=true -Dvapi=true -Dexamples=false -Ddocs=false \
        -Dtests=false -Dsmoke-tests=false
    ninja -C "$src/build" -j "$JOBS"
    as_root meson install -C "$src/build" --no-rebuild
}

build_lumenshell() {
    here=$(cd "$(dirname "$0")/../.." && pwd)
    wp=$(wayfire_prefix)
    pcpath="$wp/libdata/pkgconfig:$wp/lib/pkgconfig"
    plugins=true
    if ! PKG_CONFIG_PATH="$pcpath" pkg-config --atleast-version=0.10 --max-version=0.10.99 wayfire 2>/dev/null; then
        say "no Wayfire 0.10 found (run: $0 wayfire); building without the C++ plugins"
        plugins=false
    fi
    set -- -Dprefix="$LOCALBASE" -Dbuildtype=release
    for o in desktop_peek curtain_peek slide_peek zoom_peek panel_push startup_zoom night_light; do
        set -- "$@" "-Dwith_$o=$plugins"
    done
    rm -rf "$here/build-freebsd"
    PKG_CONFIG_PATH="$pcpath${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
        meson setup "$here/build-freebsd" "$here" "$@"
    ninja -C "$here/build-freebsd" -j "$JOBS"
    as_root meson install -C "$here/build-freebsd" --no-rebuild
    say "installed. Next, if not done yet: doas $here/scripts/freebsd/setup-system.sh"
}

for target in "$@"; do
    case "$target" in
        wayfire)          build_wayfire ;;
        gtk4-layer-shell) build_gtk4_layer_shell ;;
        lumenshell)       build_lumenshell ;;
        all)              build_wayfire; build_lumenshell ;;
        *) die "unknown target: $target" ;;
    esac
done
