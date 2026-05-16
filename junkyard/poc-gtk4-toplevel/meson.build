project('lumen-poc-gtk4-toplevel', ['c', 'vala'],
  default_options: ['warning_level=2', 'c_std=c11'])

gtk4         = dependency('gtk4')
gtk4_wayland = dependency('gtk4-wayland')
layer_shell  = dependency('gtk4-layer-shell-0')
wl_client    = dependency('wayland-client')

# Reuse the wayland-scanner-generated protocol bindings already in wlhooks/.
proto_dir = meson.project_source_root() / '..' / 'wlhooks' / 'generated'
proto_src = files(proto_dir / 'wlr-foreign-toplevel-management-unstable-v1-protocol.c')

executable('lumen-poc-gtk4-toplevel',
  [ 'main.vala',
    'toplevel_shim.c',
    proto_src,
  ],
  vala_args: [
    '--vapidir=' + meson.current_source_dir(),
    '--pkg=toplevel_shim',
  ],
  c_args: [ '-I' + proto_dir ],
  # gtk4-layer-shell must appear before libwayland-client in the link line;
  # see https://github.com/wmww/gtk4-layer-shell/blob/main/linking.md
  link_args: [ '-Wl,--no-as-needed' ],
  dependencies: [ layer_shell, gtk4, gtk4_wayland, wl_client ],
  install: false,
)
