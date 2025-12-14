project('wlhooks', 'c',
  version : '1.0'
)

# --- Find dependencies using pkg-config ---
wayland_client_dep = dependency('wayland-client', required: true)
wayland_egl_dep    = dependency('wayland-egl', required: true)
egl_dep            = dependency('egl', required: true)
glesv2_dep         = dependency('glesv2', required: true)
xkb_dep            = dependency('xkbcommon', required: true)

# --- Source and header files ---
sources = [
  'main.c',
  'egl.c',
  'registry.c',
  'protocols/compositor.c',
  'protocols/layershell.c',
  'protocols/seat.c',
  'protocols/toplevel.c',
  'protocols/screencopy.c',
  'generated/wlr-layer-shell-unstable-v1-protocol.c',
  'generated/xdg-shell-client-protocol.c',
  'generated/wlr-foreign-toplevel-management-unstable-v1-protocol.c',
  'generated/wlr-screencopy-unstable.c'
]

wayland_unstable = static_library(
  'wlhooks',
  sources,
  dependencies: [wayland_client_dep, wayland_egl_dep, egl_dep, glesv2_dep, xkb_dep],
  include_directories: include_directories('.')
)