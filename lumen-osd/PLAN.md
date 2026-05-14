# Plan: lumen-osd (homegrown OSD for LumenShell)

## Context

LumenShell currently runs Wayfire with `lumen-panel` (bottom dock, 60 px exclusive
zone) and `Kickoff`. The only OSD option today is the upstream SwayOSD packaged
under `swayosd-wayfire/` — that subdir is just an installer with udev rules and
Wayfire keybindings, not a real LumenShell component. We want a homegrown OSD
that

- sits in the bottom-center *above* the panel,
- supports the swayosd trigger surface we actually use (output volume, mic
  volume, brightness, keyboard brightness, caps lock, custom messages),
- has position and style configurable from a theme file.

The decision (confirmed with the user) is a daemon + CLI client pair, brightness
driven by shelling out to `brightnessctl`, pactl code duplicated into the new
project, and lock-key support limited to Caps Lock in v1.

**Stack decision:** lumen-osd is a **GTK4 application**. It does **not** use
libdrawkit and it does **not** touch `wlhooks/`. Surfaces are created with
[`gtk4-layer-shell`](https://github.com/wmww/gtk4-layer-shell); drawing is done
with native GTK4 widgets, with the pill body rendered via a `GtkWidget` subclass
that overrides `snapshot()` and emits GSK rounded-rect nodes. This isolates the
new component from the existing GLES/drawkit pipeline used by lumen-panel and
keeps the wlhooks library frozen.

## Architecture

Two Meson executables added to the root `meson.build` (alongside `lumen-panel`
and `kickoff`):

- **`lumen-osd`** — long-running daemon, owns the layer-shell window and renders
  with GTK4 + GSK. Started from Wayfire autostart.
- **`lumen-osdctl`** — small CLI invoked from Wayfire keybinds. Reads/changes
  the underlying system state and asks the daemon to display the result.

### IPC: GDBus on the session bus

Use GLib's built-in GDBus (already a transitive dep of GTK4). Bus name
`org.lumenshell.OSD`, object path `/org/lumenshell/OSD`, interface
`org.lumenshell.OSD1` with one method:

```
Show(s kind, d value, s text, a{sv} opts) -> ()
```

- `kind` ∈ `"volume"`, `"mic"`, `"brightness"`, `"kbd-brightness"`,
  `"caps-lock"`, `"custom"`.
- `value` is 0.0–1.0 for sliders, ignored for caps/custom-without-bar.
- `text` is an override label (e.g. "ON"/"OFF" for caps, free text for custom).
- `opts` carries `muted` (b), `icon` (s, named icon override), `timeout-ms` (i).

Why GDBus over a Unix socket: zero extra plumbing in Vala, the client can detect
"is the daemon up" via `NameHasOwner`, and `gdbus-codegen` produces typed
proxies. swayosd uses the same shape.

### Daemon lifecycle and layer-shell positioning (gtk4-layer-shell)

The daemon is a `Gtk.Application`. On `activate` it constructs a single
`Gtk.Window`, then **before** showing it calls into gtk4-layer-shell:

```vala
GtkLayerShell.init_for_window(window);
GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY);
GtkLayerShell.set_namespace(window, "lumen-osd");
GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.BOTTOM, true);
GtkLayerShell.set_margin(window, GtkLayerShell.Edge.BOTTOM,
                         panel_exclusive_zone + gap);
GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.NONE);
// no set_exclusive_zone() — OSD must never claim screen real estate
```

The window is kept mapped for the whole session. When idle the pill widget is
hidden (`set_visible(false)`) and the window's input region is shrunk to empty
via `surface.set_input_region(empty_region)` on the underlying
`Gdk.Surface` — obtained from `window.get_surface()` after realize — so clicks
pass through to whatever is underneath. Show requests reveal the pill and arm a
hide timer; on timeout it returns to the hidden state.

Because gtk4-layer-shell exposes margins natively (`set_margin(edge, px)`), the
bottom-center-above-the-panel requirement is satisfied without changing
wlhooks. **No edits to `wlhooks/` or `vapi/libwlhooks.vapi` are part of this
plan.** lumen-osd never links against libwlhooks.

### Rendering (GTK4 + GSK, no libdrawkit)

The layer-shell window is full-bottom-width and fully transparent
(`window.set_child(overlay)` where `overlay` is a `Gtk.Box` with a horizontally
centered child). The centered child is the **pill widget** — a custom
`Gtk.Widget` subclass (`Osd.Pill`) sized roughly 360×56 px.

`Osd.Pill` overrides `snapshot(Gtk.Snapshot s)`:

- background — `s.append_rounded_rect_color(...)` or
  `s.push_rounded_clip(...)` + `s.append_color(...)` to draw the pill body
  with corner radius ≈ height/2.
- progress track + fill — two more rounded-rect nodes (track in
  `osd.progress.track`, fill in `osd.progress.fill`, width =
  `value * inner_width`).
- icon — a child `Gtk.Image` packed in a `Gtk.Box` and snapshotted via
  `snapshot_child(image, s)`. Source: themed icons via
  `Gtk.Image.set_from_icon_name` (e.g. `audio-volume-high-symbolic`,
  `display-brightness-symbolic`), so we don't need to ship our own SVGs — the
  user's icon theme provides them. An icon override can still be passed via
  the D-Bus `opts.icon` string.
- text (percentage / chip label) — a child `Gtk.Label` snapshotted the same
  way.

For caps-lock / custom-without-value, the progress track + fill nodes are
omitted and the label fills the right side as a chip.

A single `Gtk.CssProvider` is attached to the display so the few non-GSK bits
(label color, font weight) can be themed from the same JSON file (see Theme
below) — we build a small CSS string at startup from the JSON and load it via
`provider.load_from_string(...)`.

### Backends

Responsibility split: **the daemon owns nothing but display + state polling for
mute/value display.** The CLI client is the side that mutates: it runs
`brightnessctl set 5%+`, then reads the new value, then calls
`Show("brightness", 0.42, "")`. Same for pactl. This mirrors swayosd-client and
keeps the daemon stateless apart from "what's currently on screen."

- **Audio (`pactl`)**: copy `lumen-panel/src/components/sound/pactl.vala` into
  `lumen-osd/src/pactl.vala`. That file is plain process-spawning and parsing —
  no drawkit dependency — so it ports verbatim. The client uses
  `query_volume_percent` / `query_muted` after firing `pactl set-sink-volume
  @DEFAULT_SINK@ ±5%`.
- **Brightness**: shell out to `brightnessctl set 5%+` / `5%-`, then
  `brightnessctl -m` to read back (`current,max,pct`). Same for keyboard
  backlight via `brightnessctl --device='*::kbd_backlight' set 5%+`.
- **Caps Lock**: read `/sys/class/leds/input*::capslock/brightness`. The client
  is invoked from a keybind on the *Caps Lock* key itself, so by the time the
  client runs the kernel has already flipped the LED state. No xkbcommon
  needed.

### Theme / config

JSON loader, same shape as `lumen-panel/src/theme.vala` so the look stays in
family with the panel. New file `lumen-osd/src/theme.vala` adds keys:

```
osd.background, osd.foreground, osd.text,
osd.progress.track, osd.progress.fill,
osd.position           ("bottom-center" | "top-center" | "bottom-right" | ...)
osd.margin             (int px, gap from the anchored edge)
osd.width, osd.height
osd.corner-radius      (int px; default = height / 2 for a pill)
osd.timeout-ms
```

`position` maps to a set of `GtkLayerShell.Edge` anchors. `margin` defaults to
`PANEL_EXCLUSIVE_HEIGHT + 16` (≈ 76) when position is `bottom-center` so the
pill clears the panel. Color keys are read as `#rrggbb`/`#rrggbbaa` and parsed
into `Gdk.RGBA` for use by the GSK snapshot code; the `osd.text` color is also
emitted into the generated CSS so the `Gtk.Label` inherits it. Theme is loaded
once at startup; path resolution mirrors lumen-panel (`$LUMEN_OSD_THEME_FILE`
env, fallback to `/usr/share/lumen-osd/default-theme.json`).

## Files to add / modify

### New files

```
lumen-osd/src/main.vala               # Gtk.Application, GDBus name owner, theme load
lumen-osd/src/window.vala             # layer-shell window setup + show/hide gating
lumen-osd/src/pill.vala               # Osd.Pill : Gtk.Widget — GSK snapshot()
lumen-osd/src/theme.vala              # JSON loader (shape copied from lumen-panel/theme.vala)
lumen-osd/src/utils.vala              # env-var path helpers (copy of lumen-panel/utils.vala)
lumen-osd/src/pactl.vala              # copy of lumen-panel/src/components/sound/pactl.vala
lumen-osd/src/dbus.vala               # [DBus(name="org.lumenshell.OSD1")] interface + skeleton
lumen-osd/default-theme.json          # ships to /usr/share/lumen-osd/

lumen-osdctl/src/main.vala            # arg parser
lumen-osdctl/src/backends.vala        # pactl + brightnessctl + sysfs caps wrappers
lumen-osdctl/src/dbus_proxy.vala      # generated by gdbus-codegen or hand-written

swayosd-wayfire/wayfire.ini.snippet   # update example to call lumen-osdctl (or add a new snippet)
```

No `icons/` directory — we rely on the system symbolic icon theme via
`Gtk.Image.set_from_icon_name`.

### Modified files

- `meson.build` — append two `executable()` blocks for `lumen-osd` and
  `lumen-osdctl`. These targets have their **own** dependency list (see below)
  and explicitly do not include `drawkit_dep` / `wlhooks_dep` / `egl_dep` /
  `glesv2_dep`.

**`wlhooks/` and `vapi/libwlhooks.vapi` are NOT modified.**

### Meson dependencies for the new targets

```
gtk4_dep             = dependency('gtk4')
gtk4_layer_shell_dep = dependency('gtk4-layer-shell-0')

osd_deps = [glib_dep, gio_dep, gee_dep, json_dep,
            gtk4_dep, gtk4_layer_shell_dep, m_dep]

osd_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=json-glib-1.0',
]
```

If a `gtk4-layer-shell-0` VAPI is not present in the system Vala distribution, a
small hand-written `vapi/gtk4-layer-shell-0.vapi` binding goes in alongside the
existing wlhooks/drawkit VAPIs (covering only the half-dozen functions used:
`init_for_window`, `set_layer`, `set_namespace`, `set_anchor`, `set_margin`,
`set_keyboard_mode`, `set_exclusive_zone`). Verify with
`pkg-config --exists gtk4-layer-shell-0` and `valac --pkg=gtk4-layer-shell-0`
before deciding.

`install_dependencies.py` is updated to install `gtk4-devel` and
`gtk4-layer-shell-devel` (Fedora package names).

## CLI surface (`lumen-osdctl`)

```
lumen-osdctl --output-volume raise|lower|mute-toggle [--step 5]
lumen-osdctl --input-volume  raise|lower|mute-toggle [--step 5]
lumen-osdctl --brightness    raise|lower             [--step 5]
lumen-osdctl --kbd-brightness raise|lower            [--step 5]
lumen-osdctl --caps-lock
lumen-osdctl --custom "text" [--value 0.5] [--icon NAME]
```

Mirrors swayosd-client so the existing Wayfire keybinds in
`swayosd-wayfire/wayfire.ini.snippet` need only a binary rename.

## Wayfire integration

Update `swayosd-wayfire/wayfire.ini.snippet` so the autostart line launches
`lumen-osd` and every `binding_*` invokes `lumen-osdctl …`. Keep
`99-swayosd-backlight.rules` and `install.sh` — they're still useful because
`brightnessctl` itself needs the `video` group / udev write access unless you
install its setuid helper.

## Critical files to reference while implementing

- `meson.build:47-90` — pattern for adding the two new executables (but note
  the new targets use a *different* dependency set; do not blindly copy
  `common_deps` / `common_vala_args`).
- `lumen-panel/src/theme.vala` — JSON loader pattern; we keep the *parser*
  shape and replace the *consumers* (drawkit calls → `Gdk.RGBA` / CSS).
- `lumen-panel/src/components/sound/pactl.vala` — copy verbatim, no drawkit
  touch.
- gtk4-layer-shell docs: <https://wmww.github.io/gtk4-layer-shell/> for the
  exact symbol names used above.

## Verification

End-to-end test once implemented:

1. `meson setup build && meson compile -C build` from the repo root. All four
   binaries (`lumen-panel`, `kickoff`, `lumen-osd`, `lumen-osdctl`) build.
   wlhooks/libdrawkit must build untouched — confirm by diffing
   `wlhooks/` and `vapi/libwlhooks.vapi` against `master` (should be empty).
2. Run `./build/lumen-osd` from a Wayfire session and confirm a transparent
   layer-shell surface is created with no visible artefact and no exclusive
   zone (panel still occupies the bottom 60 px alone; OSD surface is visible
   in `wayland-info` / compositor logs as namespace `lumen-osd` on the
   `overlay` layer).
3. From another terminal: `./build/lumen-osdctl --output-volume raise`. Expect
   the volume to step up via pactl AND a pill OSD to appear bottom-center above
   the panel for ~1.5 s.
4. Repeat for `--brightness raise` (sanity check: `brightnessctl` is installed
   and the user is in the `video` group / udev rule from
   `swayosd-wayfire/99-swayosd-backlight.rules` is loaded).
5. Repeat for `--caps-lock` — press Caps Lock first, then run the client,
   confirm "ON"/"OFF" chip displays.
6. Run `gdbus call --session -d org.lumenshell.OSD -o /org/lumenshell/OSD -m org.lumenshell.OSD1.Show "custom" 0.5 "Hello" "{}"`
   to confirm the D-Bus surface independently of the CLI.
7. Edit `/usr/share/lumen-osd/default-theme.json` (or set `$LUMEN_OSD_THEME_FILE`),
   change `osd.position` to `"top-center"` and `osd.progress.fill` to a
   different color, restart the daemon, confirm visual change (top-anchor swap
   verifies the `GtkLayerShell.Edge` mapping is correct).

## Out of scope for v1

- Num Lock / Scroll Lock indicators (user only asked for Caps Lock).
- Media playback (play/pause/next/prev) OSD.
- Passive event-driven monitoring of audio/brightness from PipeWire / UPower
  signals. The client-pushed model is enough for the keybind-driven UX.
- Per-output (per-monitor) OSD placement; v1 shows on the compositor's primary
  output via gtk4-layer-shell's default monitor selection (no
  `set_monitor()` call in v1).
- Animated show/hide transitions; v1 is a hard show/hide on the hide timer.
