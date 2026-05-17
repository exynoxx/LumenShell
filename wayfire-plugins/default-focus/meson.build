wayfire_dep  = dependency('wayfire',         version: '>=0.10', required: true)
wlroots_dep  = dependency('wlroots-0.19',                       required: true)
wlrproto_dep = dependency('wlr-protocols',                      required: true)

plugindir = wayfire_dep.get_variable(
  pkgconfig: 'plugindir',
  default_value: get_option('libdir') / 'wayfire',
)
metadatadir = wayfire_dep.get_variable(
  pkgconfig: 'metadatadir',
  default_value: get_option('datadir') / 'wayfire' / 'metadata',
)

# wlr-layer-shell C header transitively pulls in the wayland-scanner-
# generated protocol header. Generate it from the XML shipped by
# wlr-protocols-devel.
wayland_scanner = find_program('wayland-scanner')
wlrproto_pkgdatadir = wlrproto_dep.get_variable(pkgconfig: 'pkgdatadir')
layer_shell_xml = wlrproto_pkgdatadir / 'unstable' / 'wlr-layer-shell-unstable-v1.xml'

layer_shell_proto_h = custom_target(
  'wlr-layer-shell-unstable-v1-protocol.h',
  input:   layer_shell_xml,
  output:  'wlr-layer-shell-unstable-v1-protocol.h',
  command: [wayland_scanner, 'server-header', '@INPUT@', '@OUTPUT@'],
)

shared_module(
  'wayfire-default-focus',
  'src/default-focus.cpp',
  layer_shell_proto_h,
  dependencies: [wayfire_dep, wlroots_dep],
  cpp_args:     ['-std=c++17'],
  name_prefix:  'lib',
  install:      true,
  install_dir:  plugindir,
)

install_data(
  'metadata/wayfire-default-focus.xml',
  install_dir: metadatadir,
)
