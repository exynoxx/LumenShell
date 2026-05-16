# wlhooks — partially deprecated

`wlhooks` originally wrapped every Wayland protocol the legacy
`lumen-panel` needed: layer-shell + EGL + seat (pointer/keyboard) +
output + foreign-toplevel + xdg-activation + screencopy.

After the GTK4 port of `lumen-panel`, only the **foreign-toplevel +
xdg-activation slice** is still used. GTK4 + `gtk4-layer-shell` now
own layer-shell, EGL, pointer, keyboard, and output handling.

The new entry points used by the GTK4 panel:

- `wlhooks_init_toplevel_with_display(struct wl_display *)` — binds
  foreign-toplevel + activation on a wl_display owned by GTK/GDK,
  skipping EGL/layer-shell/pointer/keyboard.
- `wlhooks_destroy_toplevel()` — tears down only what the above
  initialized; does **not** disconnect the wl_display.
- `seat_set_minimal_mode(bool)` — suppresses pointer/keyboard
  attachment in `seat.c` so GTK keeps ownership of input.

The legacy `wlhooks_init()` / `init_layer_shell()` / EGL / pointer /
keyboard / output / screencopy code paths are still compiled but are
no longer reached by any binary in this repo. They can stay until a
follow-up cleanup decides to delete them, or until another consumer
(`lumen-osd`, `lumen-notifications`) is reworked.

If a future cleanup removes the unused paths, the foreign-toplevel
slice (`wlhooks/protocols/wlr_toplevel.c`,
`wlhooks/protocols/window_list.c`,
`wlhooks/protocols/toplevel.c`, `wlhooks/protocols/activation.c`,
`wlhooks/registry.c`, plus the minimal `seat.c`) is the only part that
must be kept.
