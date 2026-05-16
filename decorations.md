# Wayfire decoration plan (SSD → GNOME-like)

## Context
Wayfire 0.9.0 currently uses the built-in `libdecoration.so` plugin for any
window that asks for server-side decorations. It only knows about a single
title-bar color, an inactive color, a border size, and a title height — no
rounded corners, no shadow, no gradient. Modern GNOME-style decorations need
**pixdecor** (https://github.com/soreau/pixdecor), a third-party Wayfire plugin
that adds rounded corners, drop shadows, gradients, and per-button styling.

CSD apps are unaffected by this plan — `preferred_decoration_mode = client`
stays as is, so libadwaita/GTK apps keep drawing their own headerbars.

Current relevant settings in `~/.config/wayfire.ini`:
- `[core] plugins = … decoration …`
- `[core] preferred_decoration_mode = client`
- `[decoration]` block with `active_color = #222222AA`, `border_size = 4`, etc.

---

## Steps

### 1. Resolve the Wayfire version skew
Installed: `wayfire 0.9.0-4.fc43`. Available: `wayfire-devel 0.10.1-1.fc43`.
A plugin built against 0.10 headers will not load into 0.9.

Pick one:
- **A. Upgrade Wayfire to 0.10** (recommended):
  ```bash
  sudo dnf upgrade wayfire wf-config
  sudo dnf install wayfire-devel wf-config-devel
  ```
  Back up `~/.config/wayfire.ini` first; 0.10 may rename a few keys.
- **B. Stay on 0.9** and check out the last pixdecor commit that targets the
  0.9 API. Requires walking `git log` in the pixdecor repo.

### 2. Build & install pixdecor
```bash
git clone https://github.com/soreau/pixdecor.git ~/src/pixdecor
cd ~/src/pixdecor
meson setup build --prefix=/usr -Dbuildtype=release
meson compile -C build
sudo meson install -C build
```
Drops `libpixdecor.so` into `/usr/lib64/wayfire/` and an XML metadata file into
`/usr/share/wayfire/metadata/`.

Sanity check:
```bash
ls /usr/lib64/wayfire/libpixdecor.so
ls /usr/share/wayfire/metadata/pixdecor.xml
```

### 3. Edit `~/.config/wayfire.ini`

In `[core]`, swap `decoration` → `pixdecor` in the `plugins =` list. Keep
`preferred_decoration_mode = client`.

Delete the whole `[decoration]` block (lines 111–119 in current file) and
replace it with a `[pixdecor]` block. GNOME-ish starting values:

```ini
[pixdecor]
border_size           = 0
titlebar              = true
title_text            = true
rounded_corners       = 12
shadows               = true
shadow_radius         = 20
shadow_color          = \#000000B0
fg_color              = \#242424FF
fg_text_color         = \#FFFFFFFF
bg_color              = \#1E1E1EFF
bg_text_color         = \#CCCCCCFF
button_color          = \#FFFFFF00
effect_type           = none
font                  = Cantarell 11
button_order          = minimize maximize close
title_height          = 36
```

Exact key names vary by pixdecor build — after install, open `wcm`
(`wayfire-config-manager`) and confirm key names against `pixdecor.xml`.
Adjust any name mismatches before restarting Wayfire.

### 4. Reload Wayfire
Either log out / back in, or — if you have IPC enabled (you do; `ipc` and
`ipc-rules` are in `plugins`) — restart Wayfire from a TTY.

### 5. Verify

Temporarily force SSD to exercise the plugin:
```ini
# in [core]
preferred_decoration_mode = server
# in [workarounds]
force_preferred_decoration_mode = true
```
Reload, open a window (e.g. `nautilus`), confirm:
- rounded corners ✓
- soft drop shadow ✓
- dark Adwaita-like title bar with Cantarell text ✓
- buttons in `minimize maximize close` order, hover states visible ✓

Then revert both flags back to `client` / `false` so CSD apps draw their own
headerbars again.

Logs to check on plugin load:
```bash
journalctl --user -b | grep -iE 'pixdecor|wayfire' | tail -50
```
Should show `Loaded plugin pixdecor` and no symbol-lookup errors.

---

## Critical files
- `~/.config/wayfire.ini` — `[core] plugins`, drop `[decoration]`, add `[pixdecor]`
- `/usr/lib64/wayfire/libpixdecor.so` — installed by `meson install`
- `/usr/share/wayfire/metadata/pixdecor.xml` — exposes keys to `wcm`

## Risks
- Version skew between installed Wayfire and the headers used to build pixdecor
  is the #1 failure mode — confirm with `pkg-config --modversion wayfire` before
  `meson setup`.
- 0.9 → 0.10 upgrade may rename a few unrelated config keys; back up
  `wayfire.ini` and diff against the shipped `wayfire.ini.example`.
- pixdecor key names drift between releases; treat the block above as a
  starting point, reconcile with installed `pixdecor.xml`.
