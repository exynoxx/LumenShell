# liblumen-ext — the extension API. The one exception to "lumen-common is
# source-level only": host and extensions must share one copy of every GType,
# so this is a real shared library with an installed vapi + pkg-config file
# that user extensions are compiled against.

gmodule_dep = dependency('gmodule-2.0')
cairo_dep   = dependency('cairo')

lumen_ext_deps = [
  # Same layer-shell link-order rule as lumen-panel.
  gtk4_layer_shell_dep,
  gtk4_dep,
  glib_dep,
  gio_dep,
  gmodule_dep,
  json_dep,
  cairo_dep,
]

lumen_ext_sources = files(
  'api.vala',
  'manifest.vala',
  'ext_config.vala',
  'registry.vala',
  'slots.vala',
  'compiler.vala',
  'loader.vala',
  'shape.vala',
)

lumen_ext_lib = shared_library('lumen-ext-1',
  lumen_ext_sources,
  vala_header: 'lumen-ext-1.h',
  vala_vapi: 'lumen-ext-1.vapi',
  vala_args: ['--vapidir=' + vapi_dir, '--pkg=gtk4-layer-shell-0', '--pkg=gmodule-2.0', '--pkg=cairo'],
  dependencies: lumen_ext_deps,
  link_args: ['-Wl,--no-as-needed'],
  version: '1.0.0',
  install: true,
  install_dir: [true, get_option('includedir') / 'lumen-ext-1', get_option('datadir') / 'vala' / 'vapi'],
)

# valac reads <pkg>.deps beside the vapi; copied into the build dir so dev runs
# (LUMEN_EXT_VAPIDIR → this dir) resolve it too.
configure_file(input: 'lumen-ext-1.deps', output: 'lumen-ext-1.deps', copy: true)
install_data('lumen-ext-1.deps', install_dir: get_option('datadir') / 'vala' / 'vapi')

import('pkgconfig').generate(lumen_ext_lib,
  name: 'lumen-ext-1',
  description: 'LumenShell extension API',
  version: '1.0',
  subdirs: 'lumen-ext-1',
  requires: ['gtk4', 'gtk4-layer-shell-0', 'gio-2.0', 'gmodule-2.0', 'json-glib-1.0', 'cairo'],
)

lumen_ext_dep = declare_dependency(
  link_with: lumen_ext_lib,
  include_directories: include_directories('.'),
  dependencies: lumen_ext_deps,
)

# Where the host's Compiler finds the API when compiling user extensions.
# Overridable at runtime by $LUMEN_EXT_VAPIDIR / $LUMEN_EXT_PCDIR (set by devenv).
lumen_ext_c_args = [
  '-DLUMEN_EXT_VAPIDIR="' + (get_option('prefix') / get_option('datadir') / 'vala' / 'vapi') + '"',
  '-DLUMEN_EXT_PCDIR="' + (get_option('prefix') / get_option('libdir') / 'pkgconfig') + '"',
]
lumen_ext_build_vapidir = meson.current_build_dir()
