# lumen-corner

Hot-corner app launcher for wlroots-based Wayland compositors (Wayfire, Sway, Hyprland, …).
Move the pointer into the bottom-left corner and a quarter-ring slides out holding four app icons.
Click an icon to launch it.

Standalone: depends only on GTK4 and gtk4-layer-shell.

## Build

```sh
meson setup build
meson compile -C build
meson install -C build     # optional; or --prefix=$HOME/.local at setup
```

## Run

```sh
lumen-corner                                   # built-in default app list
lumen-corner firefox.desktop kitty.desktop …   # first 4 desktop IDs that exist
```

`LUMEN_CORNER_OPEN=1` starts it already open (screenshots/debugging).

## Config — `~/.config/lumen-corner/config.ini`

```ini
[style]
size=medium            # small | medium | large
background=#eee        # any CSS colour, rgba(30,30,35,0.85), or transparent
```

Read at startup; restart after editing.
