# Handoff — Feasibility of porting lumen-panel to GTK4 + gtk4-layer-shell + GSK

**Created:** 2026-05-14 11:38 UTC
**Working directory:** /home/nicholas/Dokumenter/git/LumenShell
**Branch / commit:** master @ a48a0d7

## Objective

Determine whether `lumen-panel` (currently EGL+GLES2 via custom `libdrawkit`
and custom `wlhooks` on top of `wlr-layer-shell-unstable-v1`) can be
rewritten on top of GTK4 + `gtk4-layer-shell` + GSK while staying in Vala.
A specific sub-question: can the rewrite still obtain the running-toplevels
list it needs for the taskbar when GTK does not bind any
foreign-toplevel protocol?

## Context

- Lumen targets **Wayfire** as compositor. The user's `~/.config/wayfire.ini`
  loads the `foreign-toplevel` plugin (`/usr/lib64/wayfire/libforeign-toplevel.so`),
  which exposes `zwlr_foreign_toplevel_manager_v1`.
- The active session while this work was done was **KWin (KDE)**. KWin does
  **not** expose `zwlr_foreign_toplevel_manager_v1`. To validate the spike a
  nested Wayfire was used.
- System versions on this machine: GTK 4.20.3, gtk4-layer-shell 1.2.0
  (pkg-config) / 1.0.3 (Fedora pkg) — two installs coexist (see "Tried and
  rejected"). Vala 0.56.18. Wayfire 0.9.0.
- The user previously hit "`gdk_wayland_display_get_wl_display` does not
  exist" and asked for header-level verification before any rewrite.

## Current state

Feasibility verdict: **yes, feasible**, with foreign-toplevel solved via
GDK's wl_display. Full analysis lives in
`/home/nicholas/.claude/plans/is-it-feasible-to-flickering-lighthouse.md`.

A working proof-of-concept exists at `poc-gtk4-toplevel/`:

- `poc-gtk4-toplevel/main.vala` — GTK4 + gtk4-layer-shell window
  (anchored bottom, 60px exclusive zone, TOP layer), `Gtk.ListBox` showing
  toplevels with `app_id` / `title` / activated state. Calls
  `((Gdk.Wayland.Display) Gdk.Display.get_default()).get_wl_display()` and
  hands the resulting `Wl.Display` to a C shim.
- `poc-gtk4-toplevel/toplevel_shim.{c,h,vapi}` — ~140-LOC shim that
  binds `zwlr_foreign_toplevel_manager_v1` (max v3) on the shared
  wl_display, runs two `wl_display_roundtrip()`s, and fires three Vala
  callbacks (`added`, `changed`, `closed`). No second event loop — GDK
  pumps the wl_display.
- `poc-gtk4-toplevel/meson.build` — reuses
  `wlhooks/generated/wlr-foreign-toplevel-management-unstable-v1-protocol.c`
  and `-client-protocol.h` directly, no scanner regeneration.

Verified end-to-end inside nested Wayfire with two dummy GTK4 toplevels:

```
got wl_display=0x3394f6b0 from GTK
+ toplevel 1  app=dev.lumen.poc.dummy  title=dummy-67450  [active]
+ toplevel 2  app=dev.lumen.poc.dummy  title=dummy-67450
```

Header check confirmed `gdk_wayland_display_get_wl_display` is in
`/usr/include/gtk-4.0/gdk/wayland/gdkwaylanddisplay.h`, marked
`GDK_AVAILABLE_IN_ALL`. The Vala binding is in
`/usr/share/vala-0.56/vapi/gtk4-wayland.vapi` under `Gdk.Wayland.Display`.

Repo state: working tree clean against master before this session; new
untracked files = `poc-gtk4-toplevel/` and this `HANDOFF.md`. The plan
file at `~/.claude/plans/is-it-feasible-to-flickering-lighthouse.md` was
also written during the session. No code under `lumen-panel/`,
`libdrawkit/`, or `wlhooks/` was modified.

## Tried and rejected

- **Vala namespace `GdkWayland.Display`** — compile error. The correct
  Vala namespace is `Gdk.Wayland.Display` (the C symbol is
  `GdkWaylandDisplay` but vapigen places it under `Gdk.Wayland`).
- **`var wl_display = ...get_wl_display()`** — Vala error: "duplicating
  Display instance, use unowned variable". Fix: capture as
  `unowned Wl.Display wl_display`.
- **`win.realize.connect(...)`** to defer protocol binding — error in
  GTK4 Vala bindings: "The name `connect` does not exist in the context
  of `Gtk.Native.realize`". `realize` is a method in GTK4, not a signal.
  Fix: bind directly inside `Gtk.Application.activate` — the GdkDisplay
  exists by then.
- **`strdup()` under `c_std=c11`** — implicit declaration. Fix:
  `#define _POSIX_C_SOURCE 200809L` before headers in `toplevel_shim.c`.
- **Default meson dependency order** — produced gtk4-layer-shell warning
  "linked after libwayland", and `gtk_layer_init_for_window` silently
  no-op'd. Fix in `poc-gtk4-toplevel/meson.build`: list `layer_shell`
  before `gtk4_wayland`/`wl_client` and add
  `link_args: ['-Wl,--no-as-needed']`. After this `wayland-info` inside
  nested Wayfire showed both `zwlr_layer_shell_v1` and the layer surface
  was created cleanly.
- **First PoC run against KWin host session** — no toplevel events. Not a
  bug: KWin doesn't expose `zwlr_foreign_toplevel_manager_v1`. Switched to
  nested Wayfire to verify.
- **`gtk4-demo` as a dummy toplevel** — not installed on this machine.
  Replaced with `/tmp/dummy_toplevel.py` (PyGObject GTK4, 6 lines).

## Open questions / blockers

- **`ext-foreign-toplevel-list-v1` vs `zwlr-foreign-toplevel-management-unstable-v1`**
  for the real port. Plan recommends `zwlr` because lumen needs the write
  actions (`activate`, `close`, `set_minimized`). Confirm this matches
  user's intent before deleting wlhooks's `ext_toplevel.c` path.
- **Two installed gtk4-layer-shell versions** on the dev machine
  (`/usr/lib64/libgtk4-layer-shell.so.1.0.3` from Fedora pkg vs
  `/usr/local/lib64/libgtk4-layer-shell.so.1.2.0` from source). pkg-config
  resolves to the `/usr/local` one; not a blocker but worth pinning before
  packaging.
- **GtkPopover behavior at the bottom edge of a layer-shell surface on
  Wayfire** — not yet verified. Plan step 1 of the real port is to confirm
  this on Wayfire before porting `AppPopup` (referenced sway issue #8518
  shows this is compositor-dependent).

## Next steps

1. **Decide route on foreign-toplevel** — hand-rolled (current PoC pattern,
   reusing `wlhooks/protocols/wlr_toplevel.c` as the template) vs. depend
   on `AstalWayland`. Plan recommends hand-rolled; confirm with the user.
2. **Spike GtkPopover anchored at bottom of layer surface on Wayfire** —
   small extension to the PoC; verifies the one outstanding compositor
   behavior.
3. **If green-lit, port one trivial component end-to-end** — `Clock` is the
   simplest (`lumen-panel/src/components/clock/`); validates the Vala +
   GTK4 + meson + theming pipeline.
4. **Then `Tray` + `BatteryPage`** — validates expandable-height animation
   via `Adw.TimedAnimation` + `queue_resize`, replacing the stencil clip in
   `lumen-panel/src/components/tray.vala`.
5. **Then `AppPopup` as a real `GtkPopover`** — replaces the inline-rendered
   popup in `lumen-panel/src/components/apppopup.vala`.
6. **Finally `App` entries + foreign-toplevel wiring** — at which point
   most of `libdrawkit/` and the dispatch half of `wlhooks/` become dead
   code and can be deleted.

## Success criteria

- `meson setup build && ninja -C build` succeeds inside
  `poc-gtk4-toplevel/`.
- `wayfire --config /tmp/wfnested.ini` (or any Wayfire instance with the
  `foreign-toplevel` plugin loaded) produces `+ toplevel N  app=...
  title=...` lines in the PoC's stdout for every GTK/Qt window present.
- `wayland-info | grep foreign_toplevel` inside the target compositor
  shows `zwlr_foreign_toplevel_manager_v1` (already true on the user's
  Wayfire session per `~/.config/wayfire.ini`).
- Plan file `~/.claude/plans/is-it-feasible-to-flickering-lighthouse.md`
  matches the final design before any non-PoC code is written.

## Key files

- `/home/nicholas/.claude/plans/is-it-feasible-to-flickering-lighthouse.md` —
  full feasibility analysis: drawkit→GSK mapping, wlhooks→gtk4-layer-shell
  mapping, foreign-toplevel resolution, port phase order.
- `/home/nicholas/Dokumenter/git/LumenShell/poc-gtk4-toplevel/main.vala` —
  PoC GTK4 + gtk4-layer-shell Vala app; demonstrates the
  `Gdk.Wayland.Display.get_wl_display()` call and dispatches shim
  callbacks back onto the GTK main loop via `Idle.add`.
- `/home/nicholas/Dokumenter/git/LumenShell/poc-gtk4-toplevel/toplevel_shim.c` —
  Minimal C shim binding `zwlr_foreign_toplevel_manager_v1`. Uses two
  startup `wl_display_roundtrip()`s; afterwards GDK owns dispatch.
- `/home/nicholas/Dokumenter/git/LumenShell/poc-gtk4-toplevel/toplevel_shim.vapi` —
  Vala binding for the shim. Note `has_target = false` on the three
  callback delegates (they take `void *user` explicitly).
- `/home/nicholas/Dokumenter/git/LumenShell/poc-gtk4-toplevel/meson.build` —
  Note dependency order (`layer_shell` first) and
  `link_args: ['-Wl,--no-as-needed']`; pulls
  `../wlhooks/generated/wlr-foreign-toplevel-management-unstable-v1-protocol.c`
  directly.
- `/home/nicholas/Dokumenter/git/LumenShell/wlhooks/generated/wlr-foreign-toplevel-management-unstable-v1-client-protocol.h`
  and `-protocol.c` — wayland-scanner outputs reused by the PoC verbatim.
- `/home/nicholas/Dokumenter/git/LumenShell/wlhooks/protocols/wlr_toplevel.c` —
  Existing C implementation of activate/minimize/close on top of the same
  protocol; the template for the full port (drop its own
  `wl_display_connect()`, take a wl_display from GDK).
- `/usr/include/gtk-4.0/gdk/wayland/gdkwaylanddisplay.h` — confirms the C
  symbol `gdk_wayland_display_get_wl_display` exists and is
  `GDK_AVAILABLE_IN_ALL`.
- `/usr/share/vala-0.56/vapi/gtk4-wayland.vapi` — Vala binding,
  `Gdk.Wayland.Display.get_wl_display()` returning `unowned Wl.Display`.
- `~/.config/wayfire.ini` — confirms `foreign-toplevel` is in the user's
  Wayfire plugin list, so the target deployment will expose the protocol.
- `/tmp/wfnested.ini`, `/tmp/run_nested_poc.sh`, `/tmp/dummy_toplevel.py`,
  `/tmp/nested.log` — nested-Wayfire test harness and last captured run.
