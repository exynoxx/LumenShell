project('wlhooks', 'c',
  version : '1.0'
)

# --- Find dependencies using pkg-config ---
wayland_client_dep = dependency('wayland-client', required: true)
glib_dep           = dependency('glib-2.0', required: true)

# --- Source and header files ---
sources = [
  'main.c',
  'registry.c',
  'protocols/seat.c',
  'protocols/toplevel.c',
  'protocols/window_list.c',
  'protocols/wlr_toplevel.c',
  'protocols/ext_toplevel.c',
  'protocols/output.c',
  'protocols/output_management.c',
  'protocols/idle_notify.c',
  'protocols/idle_inhibit.c',
  'generated/wlr-foreign-toplevel-management-unstable-v1-protocol.c',
  'generated/ext-foreign-toplevel-list-v1-protocol.c',
  'generated/wlr-output-management-unstable-v1-protocol.c',
  'generated/ext-idle-notify-v1-protocol.c',
  'generated/idle-inhibit-unstable-v1-protocol.c'
]

wayland_unstable = static_library(
  'wlhooks',
  sources,
  dependencies: [wayland_client_dep, glib_dep],
  include_directories: include_directories('.')
)

wlhooks_dep = declare_dependency(
  link_with: wayland_unstable,
  include_directories: include_directories('.'),
  dependencies: [wayland_client_dep, glib_dep],
)
