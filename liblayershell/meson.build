project('layershell', 'c',
  version : '1.0',
  default_options : ['c_std=c11']
)

# --- Find dependencies using pkg-config ---
wayland_client_dep = dependency('wayland-client', required: true)
wayland_egl_dep    = dependency('wayland-egl', required: true)
egl_dep            = dependency('egl', required: true)
glesv2_dep         = dependency('glesv2', required: true)

# --- Source and header files ---
sources = [
  'liblayershell.c',
  'wayland/wlr-layer-shell-unstable-v1-protocol.c',
  'wayland/xdg-shell-client-protocol.c'

]

headers = [
  'liblayershell.h',
  'xdg-shell-client-protocol.h',
  'wayland/wlr-layer-shell-unstable-v1-client-protocol.h'
]

# --- Build shared library ---
liblayershell = shared_library(
  'layershell',
  sources,
  dependencies: [wayland_client_dep, wayland_egl_dep, egl_dep, glesv2_dep],
  include_directories: include_directories('.'),
  version: '1.0',
  soversion: '1'
)