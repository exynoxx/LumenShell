#!/usr/bin/env bash
# make-tarball.sh — produce a self-contained LumenShell source tarball.
#
# Emits  <outdir>/lumenshell-<version>.tar.gz  with every path under a
# `lumenshell-<version>/` prefix (what the rpm spec's %autosetup expects).
#
# The version is read from the top-level meson.build so it stays in one place.
# Uncommitted *tracked* changes are included (via `git stash create`) so you
# can test packaging without committing first; untracked files are not.
#
# Usage:
#   packaging/make-tarball.sh [OUTDIR]      # default OUTDIR: build/dist
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n "s/^[[:space:]]*version:[[:space:]]*'\([^']*\)'.*/\1/p" meson.build | head -n1)"
if [ -z "$version" ]; then
    echo "make-tarball: could not read version from meson.build" >&2
    exit 1
fi

name="lumenshell"
prefix="${name}-${version}"
outdir="${1:-build/dist}"
mkdir -p "$outdir"
tarball="${outdir}/${prefix}.tar.gz"

# Capture the working tree (tracked changes included) without disturbing it.
ref="$(git stash create || true)"
[ -n "$ref" ] || ref="HEAD"

git archive --format=tar.gz --prefix="${prefix}/" -o "$tarball" "$ref"

echo "$tarball"
