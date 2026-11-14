# lumen-corner

Hot-corner app launcher for wlroots-based Wayland compositors (Wayfire, Sway, Hyprland, …).
Move the pointer into the bottom-left corner and a quarter-ring slides out holding four app icons.
Click an icon to launch it.

Standalone: depends only on GTK4 and gtk4-layer-shell. `lumen-corner-settings` is a small
GTK4 window for picking the apps and style.

## Build

```sh
meson setup build
meson compile -C build
meson install -C build     # optional; or --prefix=$HOME/.local at setup
```

## Run

```sh
lumen-corner                                   # apps from config.ini
lumen-corner firefox.desktop kitty.desktop …   # override slots 1–4 for this run
lumen-corner-settings                          # edit config.ini
```

`LUMEN_CORNER_OPEN=1` starts it already open (screenshots/debugging).

## Config — `~/.config/lumen-corner/config.ini`

```ini
[style]
size=medium            # small | medium | large
background=#eee        # any CSS colour, rgba(30,30,35,0.85), or transparent

[apps]
slots=org.gnome.Nautilus.desktop;;foot.desktop;   # 4 desktop IDs, bottom→top; empty = no app
```

The running overlay reloads whenever the file changes. Without `[apps]`, the first four
installed apps from a built-in list are used.
