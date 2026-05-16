# SwayOSD for Wayfire

Ready-to-run On-Screen Display setup for Lumen / Wayfire. Adds floating popups
for volume and brightness changes, driven by the standard `XF86Audio*` and
`XF86MonBrightness*` media keys.

## Why this exists

Wayfire is a bare compositor. Out of the box it does **not**:

- react to `XF86AudioRaiseVolume` / `Lower` / `Mute` / `XF86AudioMicMute`,
- react to `XF86MonBrightnessUp` / `Down`,
- run any OSD daemon,
- grant the user write access to `/sys/class/backlight/*/brightness`.

This folder wires all of that up.

## What you get

- `swayosd-server` autostarted with the Wayfire session.
- Keybinds for volume (PipeWire/Pulse via `pactl`) and brightness
  (`/sys/class/backlight` via SwayOSD's helper).
- A udev rule so non-root users can change backlight brightness.

## Install

```bash
./install.sh
```

The script:

1. Installs `swayosd` and `brightnessctl` for your distro (Fedora / Arch /
   Debian-Ubuntu).
2. Installs `99-swayosd-backlight.rules` to `/etc/udev/rules.d/` and reloads
   udev.
3. Adds your user to the `video` group (needed by the udev rule).
4. Merges `wayfire.ini.snippet` into `~/.config/wayfire.ini` (creating the file
   if missing). The snippet is idempotent — re-running won't duplicate it.

After install, **log out and back in** so the `video` group membership takes
effect, then start Wayfire as usual.

## Manual integration

If you'd rather not run the script, copy the contents of `wayfire.ini.snippet`
into your `~/.config/wayfire.ini`, install `swayosd` and `brightnessctl`
yourself, and copy `99-swayosd-backlight.rules` to `/etc/udev/rules.d/`.

## Files

| File | Purpose |
|---|---|
| `install.sh` | One-shot setup script. |
| `wayfire.ini.snippet` | Autostart + keybinds to drop into `wayfire.ini`. |
| `99-swayosd-backlight.rules` | Grants `video` group write on backlight sysfs. |

## Verifying it works

```bash
# server should be running after Wayfire start
pgrep -a swayosd-server

# fire a popup manually
swayosd-client --output-volume raise
swayosd-client --brightness raise
```

If the volume popup shows but brightness doesn't change, your user isn't in
`video` yet (log out / back in), or the backlight device isn't matched by the
udev rule — check `ls /sys/class/backlight/`.
