# LumenShell on FreeBSD

LumenShell builds and runs on FreeBSD 14 and later. Meson detects the host
(`host_machine.system() == 'freebsd'`). It then swaps every Linux-only backend
for the FreeBSD tool that does the same job, so you don't need any Linux
compatibility layers (linprocfs, linsysfs, NetworkManager, PulseAudio,
systemd shims).

## Quick start

```sh
# 1. Packages (pkg). Names the repository doesn't carry are skipped.
python3 install_dependencies.py

# 2. One-time system setup: groups, rc.conf, devfs rules, wpa_supplicant
#    control socket, syslog. Idempotent; -n shows what it would change.
doas scripts/freebsd/setup-system.sh -u "$USER"

# 3. Wayfire 0.10 for the C++ plugins (x11-wm/wayfire is 0.11 on wlroots 0.20),
#    then build + install LumenShell against it.
scripts/freebsd/build-extern.sh all
```

Then merge `/usr/local/share/lumenshell/wayfire.ini.d/autostart.ini` into
`~/.config/wayfire.ini` and start the session with `start-lumenshell` from a
console, or pick **LumenShell** in your display manager.

You can skip the plugins and use the packaged Wayfire. In that case, build
with the plugin options off, as on any distro:

```sh
meson setup build -Dwith_desktop_peek=false -Dwith_curtain_peek=false \
    -Dwith_slide_peek=false -Dwith_zoom_peek=false -Dwith_panel_push=false \
    -Dwith_startup_zoom=false -Dwith_night_light=false
meson compile -C build && doas meson install -C build
```

## What changes on FreeBSD

| Concern | Linux | FreeBSD | Where |
|---|---|---|---|
| Child dies with parent | `prctl(PR_SET_PDEATHSIG)` | `procctl(PROC_PDEATHSIG_CTL)` | `lumen-common/proc.vala`, `lumen-common/bsd/lumen_bsd.c` |
| Session, lock/unlock, sleep inhibitor, power | systemd-logind (`org.freedesktop.login1`) | ConsoleKit2 (`org.freedesktop.ConsoleKit`), same Manager/Session API. Without it: `zzz(8)`, `shutdown -r/-p now` (group `operator`) | `lumen-common/logind.vala` |
| Log out | `TerminateSession` | SIGTERM to the user's `wayfire` (CK2 has no TerminateSession) | `lumen-common/logind.vala` |
| Screen brightness | sysfs `/sys/class/backlight` + `brightnessctl` | `backlight(9)` ioctls on `/dev/backlight/backlightN` (root:video 0660) | panel `brightness_service.vala`, `lumen-osd/src/state_watcher.vala`, `lumen-osdctl/src/backends.vala` |
| Keyboard backlight | sysfs `::kbd_backlight` LED | `backlight(9)` units of type `BACKLIGHT_TYPE_KEYBOARD` | same |
| Caps Lock OSD | sysfs `::capslock` LED | not exported to userland, so it always reports off | `lumen-osdctl/src/backends.vala` |
| Sound | `pactl`/`wpctl` (PulseAudio/PipeWire) | OSS through `mixer(8)`; devices from `/dev/sndstat`; default device = `hw.snd.default_unit` (changed via `pkexec sysctl`); mic meter reads `/dev/dspN` | `lumen-common/bsd/oss_mixer.vala`, `lumen-common/bsd/sound_oss.vala` |
| Wi-Fi | `nmcli` + `rfkill`, `nmcli monitor` | `wpa_cli(8)` against `wpa_supplicant(8)`, `ifconfig -g wlan`; change events from `route -n monitor` | `lumen-common/bsd/wpa_cli.vala`, `lumen-common/wifi_service.vala` |
| Ethernet | `nmcli device connect/disconnect` | `ifconfig -l ether`; toggling via `pkexec service netif start/stop <if>` | `lumen-common/bsd/wpa_cli.vala` |
| Addresses / DNS | `nmcli device show` | `ifconfig`, `route -n get default`, `/etc/resolv.conf` | same |
| Bluetooth | BlueZ over DBus + `bluetoothctl` | Hidden: FreeBSD's netgraph stack has no DBus API to drive | `BluetoothService.supported`, `lumen-common/tray_applets.vala` |
| Power profiles | power-profiles-daemon / TLP | `hwpstate_intel(4)` EPP (`dev.hwpstate_intel.N.epp`, set via `pkexec sysctl`) | `lumen-panel/src/components/battery/power_profile.vala` |
| Battery | UPower | UPower (has a FreeBSD backend) | unchanged |
| About page | `/proc`, `/sys/class/dmi`, `lspci` | `sysctl(3)` (`kern.osrelease`, `hw.model`, `hw.physmem`, `vm.stats.vm.*`), `kenv(2)` (`smbios.system.*`), `CLOCK_UPTIME`, `pciconf -lv` | `lumen-common/bsd/bsd.vala` |
| Locale list | `localectl list-locales` | `locale -a` (UTF-8 only) | `lumen-settings/src/pages/users_page.vala` |
| Formats env (`LC_TIME`, …) | `~/.config/environment.d` via systemd | same file, sourced by `start-lumenshell` | `lumen-lockscreen/data/bin/start-lumenshell.in` |
| Lock-screen auth | PAM in-process (`unix_chkpwd` does the privileged part) | setuid-root `libexec/lumen-chkpass`, since OpenPAM's `pam_unix` needs root to read `master.passwd` | `lumen-lockscreen/src/bsd/lumen-chkpass.c`, `lumen-lockscreen/src/pam_auth.c` |
| PAM policy | `/etc/pam.d/lumen-lockscreen` → `system-auth`/`common-*` | `/usr/local/etc/pam.d/lumen-lockscreen` → `include system` | `meson.build` (`pam_base=system`) |
| Session lock library | `gtk4-session-lock-0` | `gtk4-layer-shell` ≥ 1.1 (same API, used automatically when the standalone lib is absent) | `meson.build` |
| Portal activation | `lumenshell-session.target` + `systemctl --user` | not installed; `dbus-update-activation-environment` only, and the bus activates xdg-desktop-portal | `meson.build`, `lumen-session/src/main.vala` |
| Runtime dir / session bus | logind / pam_systemd | `pam_xdg(8)` if configured, else `/tmp/<uid>-runtime-dir` (0700); `dbus-run-session` when no bus | `start-lumenshell.in` |
| Logs of autostarted binaries | `systemd-cat -t lumen-x` → journal | `daemon -T lumen-x` → syslogd → `/var/log/lumenshell.log` (rotated by newsyslog) | `autostart.ini.in`, `data/freebsd/syslog.d`, `data/freebsd/newsyslog.conf.d` |
| Pre-start hooks | `/etc/lumenshell/pre-start.d` | `/usr/local/etc/lumenshell/pre-start.d` (hier(7)) | `start-lumenshell.in` |
| Data from other packages | `/usr/share/...` | First match in `XDG_DATA_DIRS` (`/usr/local/share` first): Wayfire metadata, xkb `evdev.lst`, wallpapers | `Paths.system_data_file()` |

In Vala, the FreeBSD code sits behind `#if FREEBSD`. In C it sits behind
`#ifdef LUMEN_FREEBSD`. The Linux code paths and the Linux install layout are
unchanged.

## System setup in detail

`scripts/freebsd/setup-system.sh` makes these changes. It's also installed as
`/usr/local/share/lumenshell/freebsd/setup-system.sh`.

- **Groups**: adds you to `video` (DRM render nodes, `backlight(9)`) and
  `operator` (`shutdown(8)`, `/dev/acpi` for `zzz(8)`). It never adds you to
  `wheel`.
- **rc.conf**: sets `dbus_enable=YES` and `seatd_enable=YES` (seat access for
  Wayfire without root). With `--drm i915kms|amdgpu|radeonkms` it also loads
  the graphics/drm-kmod driver through `kld_list`.
- **devfs.rules**: adds a `[lumenshell]` ruleset that makes `backlight/*`,
  `dri/*` and `drm/*` 0660 group `video`. It's enabled only if you don't
  already use a `devfs_system_ruleset`.
- **syslog**: installs `/usr/local/etc/syslog.d/lumenshell.conf` and
  `/usr/local/etc/newsyslog.conf.d/lumenshell.conf`.
- **wpa_supplicant**: makes sure `/etc/wpa_supplicant.conf` has
  `ctrl_interface=/var/run/wpa_supplicant`, `ctrl_interface_group=<group>`
  (default `wheel`, change it with `-w`) and `update_config=1`, so the panel
  can scan, join and save networks without root.
- **pam_xdg** (`--pam-xdg`, FreeBSD 14.1+): adds `session optional pam_xdg.so`
  to `/etc/pam.d/system` so logins get a proper `XDG_RUNTIME_DIR`.

Before editing a file, the script saves a `.lumenshell.bak` copy next to it.

The sample files are in `data/freebsd/`. Meson installs them to
`/usr/local/share/lumenshell/freebsd/` if you'd rather merge them by hand.

## External components

`scripts/freebsd/build-extern.sh` builds what `pkg` doesn't provide in the
version LumenShell needs.

- **`wayfire`**: builds Wayfire 0.10.1 against `wlroots019` from `pkg`, plus
  the vendored wf-config/wf-utils/wf-touch. Upstream needs no FreeBSD
  patches: its `meson.build` already links `libinotify` and `libexecinfo` on
  FreeBSD.
  - If the `wayfire` package is installed, the script installs to
    `/usr/local/lumenshell` with an RPATH, so pkg's 0.11 `libwf-config` can't
    take over the soname. It also writes
    `/usr/local/etc/lumenshell/pre-start.d/50-wayfire-0.10.sh`, which points
    `start-lumenshell` at this Wayfire.
  - Use `-p <prefix>` to choose a different location.
- **`gtk4-layer-shell`**: needed only if `pkg`'s version is older than 1.1.
- **`lumenshell`**: configures, builds and installs this tree, with
  `PKG_CONFIG_PATH` pointing at the Wayfire above. If no Wayfire 0.10 is found,
  it turns the C++ plugins off.

## Ports

`packaging/freebsd/` is a ports skeleton (`Makefile`, `pkg-descr`,
`pkg-message`, `pkg-plist`) with options for CONSOLEKIT, LOCKSCREEN, POLKIT
and SEARCH. It builds with the plugins off, because the ports tree carries
Wayfire 0.11. The plist installs `libexec/lumen-chkpass` as
`@(root,wheel,4555)`.

## Known limitations

- **Bluetooth**: not available. There is no BlueZ, and the base system's stack
  (`hccontrol`, `hcsecd`) offers no session API, so the applet and the
  Settings group are left out.
- **Caps Lock OSD**: always reports off, because FreeBSD doesn't export the
  keyboard LED state to unprivileged processes.
- **Sound**: OSS has no per-application streams, so the per-app volume list
  is empty and output volume tops out at 100%.
- **Root-only changes**: these prompt for a password through polkit
  (`lumen-polkit-agent`): switching the default sound device
  (`hw.snd.default_unit`), wired up/down (`service netif`) and EPP power
  profiles. Wi-Fi works without root once the `wpa_supplicant` control group
  is set.
- **Saved Wi-Fi passwords**: the "show password" field stays empty.
  `wpa_supplicant` never returns stored PSKs, and `/etc/wpa_supplicant.conf`
  is root-only.
- **Wi-Fi radio switch**: turning Wi-Fi off is a supplicant-level `disconnect`
  that holds until you turn it back on, not an rfkill block.
