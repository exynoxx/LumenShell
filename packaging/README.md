# Packaging

Build native `.rpm` (Fedora) and `.deb` (Debian/Ubuntu) packages of LumenShell.
Both drive the same `meson install`, so a built package installs every
`lumen-*` binary plus the session glue (`start-lumenshell`, the
`wayland-sessions` entry, and the Wayfire autostart snippet) — enough for a
display manager to list and launch a "LumenShell" session.

```
packaging/
├── make-tarball.sh        # source tarball (version read from meson.build)
├── build-rpm.sh           # → build/rpmbuild/RPMS/…
├── build-deb.sh           # → build/deb/*.deb
├── rpm/lumenshell.spec
└── debian/{control,rules,changelog,copyright,source/format}
```

All output lands under `build/` (git-ignored). Nothing touches system dirs.

## RPM (Fedora)

```sh
sudo dnf install rpm-build
sudo dnf builddep packaging/rpm/lumenshell.spec
packaging/build-rpm.sh
```

The C++ Wayfire plugins (desktop-peek, curtain-peek, startup-zoom,
default-focus) are **off by default** — they need `wayfire`/`wlroots` dev
headers that aren't always packaged. Enable them with:

```sh
packaging/build-rpm.sh --with wayfire_plugins
```

## DEB (Debian/Ubuntu)

```sh
sudo apt-get install dpkg-dev debhelper
# install Build-Depends from debian/control, then:
packaging/build-deb.sh
```

The Wayfire C++ plugins are disabled in the Debian build (`debian/rules`); the
Vala panel-peek (Win+D from the panel) stays on.

## Versioning

The version comes from `version:` in the top-level `meson.build`. To cut a new
release, bump it there and add a matching entry to both `rpm/lumenshell.spec`
`%changelog` and `debian/changelog`.

## Not yet packaged

`lumen-greeter`, `lumen-dock`, and the `lumen-lockscreen` daemon are
planning-stage (no buildable source yet) and are intentionally excluded. The
session autostart snippet does not start them. Wire them in here once they
build.
