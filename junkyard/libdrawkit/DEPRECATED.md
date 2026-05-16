# libdrawkit — deprecated

`libdrawkit` was the custom EGL/GLES2 immediate-mode renderer for the
original `lumen-panel`. As of the GTK4 + GSK port, `lumen-panel` no
longer depends on it: GSK now handles all rendering for the panel, and
the top-level `meson.build` no longer builds `libdrawkit` as part of
the default `ninja` target.

The directory is kept on disk in case `lumen-osd` or
`lumen-notifications` is later reworked to use it, or for reference when
investigating the original rendering approach. No further development
is planned.

If nothing in the tree actually uses it after the panel cutover,
`libdrawkit/` is safe to delete in a follow-up commit.
