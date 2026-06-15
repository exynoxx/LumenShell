# wayfire-desktop-peek

A Wayfire plugin that slides every visible toplevel on the active output toward
its nearest screen corner so only a small sliver peeks from the two adjacent
edges, revealing the wallpaper / desktop underneath. Toggling again animates the
windows back to their original positions. No logical geometry mutation — clients
see no configure events, the focused view stays focused, move/resize handles
remain where they were.

Equivalent of KWin's "Peek at Desktop" / GNOME's "Show Desktop".

Target: Wayfire **0.10.1** (wlroots 0.19.x).

## Build

Build-time prerequisites (Fedora package names):

- `wayfire-devel` (0.10.x)
- `wlroots-devel` (0.19.x — `wlroots0.19-devel` if the parallel-installable package is used)
- `glm-devel` — Wayfire's public headers `#include <glm/vec4.hpp>` even though
  `wayfire.pc` does not list GLM as a `Requires`. Without it, compilation fails
  with `fatal error: glm/vec4.hpp: No such file or directory`.

```sh
meson setup build
ninja -C build
sudo ninja -C build install
```

Installs `libwayfire-desktop-peek.so` into Wayfire's `plugindir` and the
metadata XML into `metadatadir`, as discovered via the `wayfire.pc` pkg-config
variables.

For a user-local install:

```sh
meson setup build --prefix=$HOME/.local
ninja -C build install
# then in wayfire.ini's [core] section, or via env:
#   WAYFIRE_PLUGIN_PATH=$HOME/.local/lib/wayfire
#   WAYFIRE_PLUGIN_XML_PATH=$HOME/.local/share/wayfire/metadata
```

## Activate

Add `wayfire-desktop-peek` to the `plugins` list in `~/.config/wayfire.ini`'s
`[core]` section, then restart Wayfire (or reload via WCM).

Default binding: `<super> KEY_D`. Reconfigure under
`[wayfire-desktop-peek] toggle = ...` or through Wayfire Config Manager.

Other options:

- `peek_px` — sliver size in pixels (default 10, range 0..200).
- `duration` — animation length and easing (default `250ms circle`).

## Triggering from outside

The plugin only exposes an activator binding; it does not run any DBus or
custom IPC. To toggle from a script:

1. Synthesize the bound key — for instance `wtype -M super d` or `ydotool key
   125:1 32:1 32:0 125:0` (adjust to your seat).
2. Or, with Wayfire's `ipc` + `ipc-rules` plugins enabled, fire the binding via
   the Wayfire IPC socket using one of the `wayfire-ipc`-style helpers.

## Behaviour

- Tracks only mapped, non-minimized toplevels on the **current workspace of the
  active output**. Each per-output plugin instance peeks its own output
  independently — there is no cross-output coordination in v0.1.
- The slide is implemented as a non-destructive `wf::scene::view_2d_transformer_t`
  added to each view's transformed node; logical geometry is never touched.
- While peeked, the plugin holds `CAPABILITY_GRAB_INPUT` and an input grab over
  the workspace layer. A pointer-button press anywhere on the workspace
  dismisses. The activator binding still works to toggle while peeked.
- If a window closes while the desktop is peeked, its transformer is dropped
  cleanly. If the last tracked window closes, the plugin returns to idle.
- Compositor preempts (e.g. lock screen) call into `plugin_activation_data_t::cancel`,
  which performs an immediate reset with no animation.

## Out of scope (v0.1)

- Multi-output coordination (each output peeks independently).
- Per-window stagger / wobble.
- Hold-to-peek (Wayfire's activator API doesn't model press-and-hold cleanly).
- Hot-corner trigger — already possible by binding `hot-corners` to the same
  activator; no code change needed here.
