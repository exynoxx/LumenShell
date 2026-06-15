# wayfire-startup-zoom

One-shot Wayfire plugin that plays a single coordinated CRT-style zoom when
the session starts: every view that maps in the first few seconds is scaled
from a small centered square out to its final position, in lockstep.

Different from Wayfire's built-in `animate` plugin (`open_animation = zoom`),
which runs an independent zoom per window. This plugin runs one shared
animation across all of the initial views so the whole desktop feels like it
powers on as a single picture.

## Build & install

The plugin builds as part of the LumenShell meson tree, gated by
`-Dwith_startup_zoom=true` (default).

```sh
cd /home/nicholas/Dokumenter/git/LumenShell
meson setup build
ninja -C build
sudo ninja -C build install
```

Installs to:

- `<prefix>/lib/wayfire/libwayfire-startup-zoom.so`
- `<prefix>/share/wayfire/metadata/wayfire-startup-zoom.xml`

(`<prefix>` resolves from `wayfire.pc`.)

## Enable

Add `wayfire-startup-zoom` to the `plugins =` line in `~/.config/wayfire.ini`:

```ini
[core]
plugins = ... wayfire-startup-zoom

[wayfire-startup-zoom]
duration = 600ms circle
initial_scale = 0.05
grace_ms = 3000
```

Then log out and log back in. The animation only runs once per session — on
first startup — and then the plugin disarms itself until the next login.

## Options

| Option          | Default        | Notes |
|-----------------|----------------|-------|
| `duration`      | `600ms circle` | How long the zoom takes. |
| `initial_scale` | `0.05`         | Starting scale (0.01–1.0). Smaller = farther away. |
| `grace_ms`      | `3000`         | If no view maps within this many ms after plugin load, give up. |

## Notes

- Acts on every view that maps on each output during the grace window —
  including layer-shell surfaces (panel, desktop drawer) and toplevels.
- View geometry is never mutated. The scale is a
  `wf::scene::view_2d_transformer_t` named `"wayfire-startup-zoom-tr"`,
  added to each view's transformed node and removed on completion.
- Scaling is centered on the output, not on each view: every view's center
  is pushed toward the output center by `(1 - s)` so the whole composite
  feels like a single object zooming in.
- Late-mapping views during the in-flight animation are caught up to the
  current progress immediately so nothing pops in at full size.
- Plays nicely with `animate`'s `open_animation = zoom` — the transformers
  are named distinctly and stack.
