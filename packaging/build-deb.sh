#!/usr/bin/env bash
# build-deb.sh — build the LumenShell .deb in a self-contained tree.
#
# Assembles  build/deb/lumenshell-<version>/  from the source tarball, drops
# packaging/debian/ on top, and runs dpkg-buildpackage. The resulting .deb
# lands in build/deb/.
#
# Usage:
#   packaging/build-deb.sh
#
# Requires: dpkg-dev, debhelper, plus the Build-Depends in debian/control.
# Install the build deps first (from the assembled tree) with:
#   sudo apt-get build-dep ./build/deb/lumenshell-<version>
# or just: sudo apt-get install <the Build-Depends list>
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\([^']*\)'.*/\1/p" meson.build | head -n1)"
prefix="lumenshell-${version}"
workdir="$repo_root/build/deb"
srcdir="$workdir/$prefix"

rm -rf "$srcdir"
mkdir -p "$workdir"

tarball="$(packaging/make-tarball.sh "$workdir")"
tar -xzf "$tarball" -C "$workdir"

# Native package: the debian/ dir lives under packaging/ in the repo, so graft
# it onto the exported source tree before building.
cp -a packaging/debian "$srcdir/debian"
chmod +x "$srcdir/debian/rules"

( cd "$srcdir" && dpkg-buildpackage -b -us -uc )

echo
echo "Built packages:"
find "$workdir" -maxdepth 1 -name '*.deb' -printf '  %p\n'
