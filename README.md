### Work in progress!!

# Introduction
LumenShell is a ChromeOS-inspired desktop shell for Wayland. It uses Wayfire as compositor and a collection of small `gtk4-layer-shell` apps written in Vala. Graphics are rendered with the Gtk scene graph kit (GSK) and are hardware-accelerated.

# Show case
<table align="center">
  <tr>
    <td colspan="2" align="center">
      <img src="docs/shots/shot-1779036345.png" width="700"><br>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/shots/shot-1779035985.png" width="340"><br>
      <sub>status strip</sub>
    </td>
    <td align="center">
      <img src="docs/shots/shot-1779036456.png" width="340"><br>
      <sub>osd</sub>
    </td>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <img src="docs/shots/f3.gif" width="700"><br>
    </td>
  </tr>
</table>

# What's in the repo
- `lumen-panel` — bottom bar showing open apps and tray area.
- `lumen-desktop` — always-open app drawer that replaces the traditional desktop files view.
- `lumen-osd` — on-screen display (volume, brightness, etc.)
- `lumen-osdctl` — CLI to trigger OSD events
- `lumen-notifications` — display system notification.
- `wayfire-desktop-peek` — Wayfire C++ plugin for show-desktop / peek
- `wlhooks` — Wayland helper library in C. Implements several wayland protocols, including foreign-toplevel-managment, used to retrieve info about open windows.


# Build & install

### 1. Install dependencies

A helper script covers Fedora, Ubuntu/Debian and Arch:

```sh
python3 install_dependencies.py
```
### 2. Configure, build, install

```sh
meson setup build
meson compile -C build
sudo meson install -C build
```

Useful options:

- `-Dwith_desktop_peek=false` — skip the C++ Wayfire plugin (`wayfire-desktop-peek`) if you don't have Wayfire dev headers.
- `--prefix=$HOME/.local` — install to your home instead of the system.

### 3. Run from the build tree (dev)

```sh
source env.sh
./build/lumen-panel
```

### License
GNU General Public License v3.0
