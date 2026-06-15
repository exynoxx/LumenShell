# wayfire-curtain-peek

A Wayfire plugin that freezes the current screen, splits that snapshot down a
vertical seam at screen centre, and slides the two halves apart — left half off
the left edge, right half off the right edge, like a pair of double doors opening.
Behind the splitting snapshot it reveals the live `lumen-desktop` app grid sitting
on a flat GNOME-Shell-like grey backdrop (`backdrop_color`). Toggling again closes
the doors.

The desktop grid is **hidden** whenever the curtain is closed and is shown only
for the duration of a peek (its real, interactive view — so revealed tiles stay
clickable). Toggling again closes the doors.

Target: Wayfire **0.10.1** (wlroots 0.19.x).

## How it works

On open the plugin:

1. **Captures** the output into an offscreen `auxilliary_buffer_t` by running a
   `render_pass_t` over the scene (`wf::get_core().scene()->gen_render_instances`).
   The desktop grid is still hidden at this moment, so the snapshot is just the
   wallpaper, app windows and panel — the "curtain".
2. **Reveals** the desktop grid (enables its scene node — it lives on BOTTOM, so
   it is naturally below the OVERLAY snapshot) and inserts an opaque grey
   `curtain_backdrop_node_t` behind it.
3. **Hides** the live BACKGROUND / WORKSPACE / TOP layers (`set_node_enabled` on
   each layer's output node) so only the grid + grey show behind the snapshot —
   the frozen copy of the live content lives in the snapshot.
4. Adds a full-output `curtain_screenshot_node_t` to the **OVERLAY** layer. Its
   render instance draws the captured texture twice via `render_pass_t::add_texture`:
   once clipped to the columns left of the seam and translated left, once clipped
   to the columns right of the seam and translated right. A `simple_animation_t`
   ramps the two translations from 0 to fully-open.

On close everything is reversed: the snapshot un-splits, the OVERLAY node and grey
backdrop are removed, the buffer is freed, the live layers are re-enabled and the
grid is hidden again.

## Build

Build-time prerequisites (Fedora package names):

- `wayfire-devel` (0.10.x)
- `wlroots-devel` (0.19.x — `wlroots0.19-devel` if the parallel-installable package is used)
- `glm-devel` — Wayfire's public headers `#include <glm/vec4.hpp>` even though
  `wayfire.pc` does not list GLM as a `Requires`.

```sh
meson setup build
ninja -C build
sudo ninja -C build install
```

Installs `libwayfire-curtain-peek.so` into Wayfire's `plugindir` and the metadata
XML into `metadatadir`, as discovered via the `wayfire.pc` pkg-config variables.

For a user-local install:

```sh
meson setup build --prefix=$HOME/.local
ninja -C build install
# then in wayfire.ini's [core] section, or via env:
#   WAYFIRE_PLUGIN_PATH=$HOME/.local/lib/wayfire
#   WAYFIRE_PLUGIN_XML_PATH=$HOME/.local/share/wayfire/metadata
```

## Activate

Add `wayfire-curtain-peek` to the `plugins` list in `~/.config/wayfire.ini`'s
`[core]` section, then restart Wayfire (or reload via WCM). For the reveal to
show the app grid, run `lumen-desktop` (it lives on the BOTTOM layer).

Default binding: `<super> KEY_S`. Reconfigure under
`[wayfire-curtain-peek] toggle = ...` or through Wayfire Config Manager.

Options:

- `split_ratio` — where the seam falls, as a fraction of output width (default
  `0.5`, range 0.1..0.9).
- `edge_px` — how many pixels of each half stay on-screen at the edges when fully
  open (default `0` = halves slide completely off; raise it to leave a grabbable
  sliver).
- `duration` — animation length and easing (default `300ms circle`).
- `backdrop_color` — flat colour revealed behind the `lumen-desktop` grid once
  the wallpaper splits away (default `#242424FF`, a GNOME-Shell-like grey).
- `desktop_app_id` — app-id (layer-shell namespace) of the desktop grid surface
  to keep fixed and reveal (default `lumen-desktop`).

## Triggering from outside

Besides the activator binding, the plugin registers Wayfire IPC methods
`wayfire-curtain-peek/{toggle,start,stop}` (requires Wayfire's `ipc` plugin).
These accept the same length-prefixed JSON frames that `lumen-desktop`'s
`peek_ipc.vala` already speaks for `wayfire-desktop-peek/*`. You can also
synthesize the bound key with `wtype` / `ydotool`.

## Behaviour

- The curtain is a single frozen **snapshot** of the whole output, split as one
  texture — no per-view transformers, so it covers any content uniformly and
  pixel-perfectly (the desktop grid is excluded only by being hidden at capture
  time).
- The desktop grid (app-id `desktop_app_id`, on BOTTOM) is kept **hidden** (its
  scene node disabled) whenever the curtain is closed, and is enabled only for the
  duration of a peek. The plugin catches it via the `view-mapped` signal so it is
  hidden from the moment it maps, and re-enables it on `fini()` so unloading the
  plugin never leaves it stuck hidden. The GTK app stays mapped throughout — only
  its rendering is toggled.
- The live BACKGROUND / WORKSPACE / TOP layers are disabled for the peek so only
  the grid + grey backdrop show through the widening gap; they are re-enabled on
  close.
- No input grab (capabilities = 0), like `wayfire-desktop-peek`, so the revealed
  grid stays clickable while open (the snapshot node is render-only).
- Compositor preempts (e.g. lock screen) call `plugin_activation_data_t::cancel`
  for an immediate reset with no animation.

## Out of scope

- Horizontal seam / multi-strip / blinds variants.
- Multi-output coordination (each output splits independently).
- Output rotation/transform on the snapshot (capture assumes `NORMAL`).
- Hold-to-peek; hot-corner trigger (bind `hot-corners` to the same activator).
