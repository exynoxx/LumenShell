#!/usr/bin/env bash
# build-rpm.sh — build the LumenShell RPM in a self-contained tree.
#
# Produces SRPM + binary RPM(s) under build/rpmbuild/{SRPMS,RPMS}.
# No system dirs are touched; rpmbuild's _topdir is redirected into build/.
#
# Usage:
#   packaging/build-rpm.sh [extra rpmbuild args...]
#   packaging/build-rpm.sh --with wayfire_plugins   # build the C++ plugins too
#
# Requires: rpmbuild (rpm-build), plus the spec's BuildRequires. Install the
# build deps first with:  sudo dnf builddep packaging/rpm/lumenshell.spec
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

spec="packaging/rpm/lumenshell.spec"
topdir="$repo_root/build/rpmbuild"

mkdir -p "$topdir"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS}

tarball="$(packaging/make-tarball.sh "$topdir/SOURCES")"
echo "Source tarball: $tarball"

rpmbuild \
    --define "_topdir $topdir" \
    -ba "$spec" "$@"

echo
echo "Built packages:"
find "$topdir/RPMS" "$topdir/SRPMS" -name '*.rpm' -printf '  %p\n'
