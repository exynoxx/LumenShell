wayfire_dep = dependency('wayfire',       version: '>=0.10', required: true)
wlroots_dep = dependency('wlroots-0.19',                       required: true)

plugindir = wayfire_dep.get_variable(
  pkgconfig: 'plugindir',
  default_value: get_option('libdir') / 'wayfire',
)
metadatadir = wayfire_dep.get_variable(
  pkgconfig: 'metadatadir',
  default_value: get_option('datadir') / 'wayfire' / 'metadata',
)

shared_module(
  'wayfire-night-light',
  'src/night-light.cpp',
  dependencies: [wayfire_dep, wlroots_dep],
  cpp_args:     ['-std=c++17'],
  name_prefix:  'lib',
  install:      true,
  install_dir:  plugindir,
)

install_data(
  'metadata/wayfire-night-light.xml',
  install_dir: metadatadir,
)
