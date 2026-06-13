project('wlhooks', 'c',
  version : '1.0'
)

# --- Find dependencies using pkg-config ---
wayland_client_dep = dependency('wayland-client', required: true)
wayland_egl_dep    = dependency('wayland-egl', required: true)
egl_dep            = dependency('egl', required: true)
glesv2_dep         = dependency('glesv2', required: true)
xkb_dep            = dependency('xkbcommon', required: true)
glib_dep           = dependency('glib-2.0', required: true)

# --- Source and header files ---
sources = [
  'main.c',
  'egl.c',
  'registry.c',
  'protocols/compositor.c',
  'protocols/layershell.c',
  'protocols/seat.c',
  'protocols/pointer.c',
  'protocols/keyboard.c',
  'protocols/xkb.c',
  'protocols/toplevel.c',
  'protocols/window_list.c',
  'protocols/wlr_toplevel.c',
  'protocols/ext_toplevel.c',
  'protocols/output.c',
  'protocols/output_management.c',
  'protocols/shm.c',
  'protocols/screencopy.c',
  'protocols/activation.c',
  'protocols/idle_notify.c',
  'generated/wlr-layer-shell-unstable-v1-protocol.c',
  'generated/xdg-shell-client-protocol.c',
  'generated/wlr-foreign-toplevel-management-unstable-v1-protocol.c',
  'generated/wlr-screencopy-unstable.c',
  'generated/ext-foreign-toplevel-list-v1-protocol.c',
  'generated/xdg-activation-v1-protocol.c',
  'generated/wlr-output-management-unstable-v1-protocol.c',
  'generated/ext-idle-notify-v1-protocol.c'
]

wayland_unstable = static_library(
  'wlhooks',
  sources,
  dependencies: [wayland_client_dep, wayland_egl_dep, egl_dep, glesv2_dep, xkb_dep, glib_dep],
  include_directories: include_directories('.')
)

wlhooks_dep = declare_dependency(
  link_with: wayland_unstable,
  include_directories: include_directories('.'),
  dependencies: [wayland_client_dep, egl_dep, glesv2_dep, glib_dep],
  link_args: ['-lwayland-egl', '-lxkbcommon'],
)