project('lumen-corner', ['c', 'vala'], version: '0.1')

# gtk4-layer-shell MUST come before gtk4 in the link line or
# gtk_layer_init_for_window() silently no-ops.
executable('lumen-corner', 'main.vala',
  dependencies: [
    dependency('gtk4-layer-shell-0'),
    dependency('gtk4'),
    dependency('gio-unix-2.0'),
    meson.get_compiler('c').find_library('m'),
  ],
  install: true,
)
