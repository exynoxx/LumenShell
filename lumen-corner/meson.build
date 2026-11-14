project('lumen-corner', ['c', 'vala'], version: '0.1')

gtk_dep = dependency('gtk4')
gio_unix_dep = dependency('gio-unix-2.0')
m_dep = meson.get_compiler('c').find_library('m')

# gtk4-layer-shell MUST come before gtk4 in the link line or
# gtk_layer_init_for_window() silently no-ops.
executable('lumen-corner', 'main.vala', 'ring.vala', 'config.vala',
  dependencies: [dependency('gtk4-layer-shell-0'), gtk_dep, gio_unix_dep, m_dep],
  install: true,
)

executable('lumen-corner-settings', 'settings.vala', 'config.vala',
  dependencies: [gtk_dep, gio_unix_dep, m_dep],
  install: true,
)

install_data('lumen-corner-settings.desktop', install_dir: get_option('datadir') / 'applications')
