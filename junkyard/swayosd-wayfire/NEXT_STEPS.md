# What to put on top of Wayfire for a fully working UI

Lumen already provides **lumen-panel** and **Kickoff**. To reach a daily-driver
desktop, the following pieces are typically still needed on top of Wayfire.

## System feedback / input

- **OSD** for volume and brightness — see `swayosd-wayfire/` in this repo.
- **Notification daemon** — Wayfire ships none. e.g. `mako`, `dunst`, or
  `swaync`.
- **Idle / lock** — `swayidle` + `swaylock` (or `gtklock` / `waylock`) for
  screen blanking and locking. Wayfire has nothing here.
- **Screenshot tool** — `grim` + `slurp` (+ `wl-clipboard` for
  copy-to-clipboard).
- **Clipboard manager** — `wl-clipboard` at minimum; `cliphist` if you want
  history.
- **Input method** — `fcitx5` or `ibus` if non-Latin input is needed.

## Session plumbing

- **xdg-desktop-portal-wlr** (and `xdg-desktop-portal` itself) — needed for
  screen sharing, file pickers from Flatpak/Electron apps, etc. Without this,
  Zoom/OBS/browsers can't share your screen.
- **PolicyKit agent** — e.g. `polkit-gnome-authentication-agent-1` or
  `lxqt-policykit-agent`, so apps can prompt for sudo-like auth (mounting,
  package managers).
- **D-Bus session activation** — usually handled by your login manager, but
  worth verifying when launching Wayfire from a TTY.
- **GTK / Qt theming bridge** — `gsettings` / `xdg-desktop-portal-gtk` for
  cursor, icon, and dark-mode propagation. Otherwise GTK apps look
  default-grey.

## Hardware integration

- **Network** — `NetworkManager` + a tray/menu UI (or wire it into
  lumen-panel).
- **Bluetooth** — `bluez` + `blueman-applet` (or a panel module).
- **Audio control** — PipeWire / WirePlumber is usually already there;
  `pavucontrol` or `helvum` is handy for routing.
- **Power management** — `tlp` or `power-profiles-daemon`; `UPower` for
  battery readout.
- **Auto-mount** — `udisks2` + something like `udiskie` for USB sticks.

## Display / desktop niceties

- **Wallpaper** — `swaybg` or `mpvpaper`. Wayfire can also show a background
  via its own plugin, but a dedicated tool is simpler.
- **Output / display config** — `wdisplays` or `kanshi` for multi-monitor
  profiles.
- **Cursor & icon themes** — set via `XCURSOR_THEME` / `gsettings` so all apps
  agree.

## Launch / login

- **Display manager** — `greetd` + `tuigreet` or `ly` for graphical login;
  otherwise a `.desktop` file in `/usr/share/wayland-sessions/` lets SDDM/GDM
  list Lumen as a session.
