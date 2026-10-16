settings_gnome = import('gnome')

settings_resources = settings_gnome.compile_resources(
  'lumen-settings-resources',
  'src/resources.gresource.xml',
  source_dir: 'src',
  c_name: 'lumen_settings',
)

settings_deps = [
  glib_dep,
  gio_dep,
  gee_dep,
  json_dep,
  gtk4_dep,
  adwaita_dep,
  m_dep,
  # Display page: wlr-output-management via wlhooks on GTK's wl_display.
  gtk4_wayland_dep,
  wayland_dep,
  wlhooks_dep,
]

settings_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=libadwaita-1',
  '--pkg=gee-0.8',
  '--pkg=json-glib-1.0',
  '--pkg=glib-2.0',
  '--pkg=gio-2.0',
  '--pkg=posix',
  '--pkg=gtk4-wayland',
  '--pkg=libwlhooks',
]

settings_sources = files(
  'src/main.vala',
  'src/window.vala',
  'src/sidebar.vala',
  'src/page.vala',
  'src/registry.vala',
  'src/theme.vala',
  'src/widgets/combo_row.vala',
  'src/widgets/color_row.vala',
  'src/widgets/file_row.vala',
  'src/widgets/binding_row.vala',
  'src/widgets/display_arranger.vala',
  'src/widgets/reorder_list.vala',
  'src/stores/json_store.vala',
  'src/stores/ini_store.vala',
  'src/stores/output_manager.vala',
  'src/pages/wallpaper_page.vala',
  'src/pages/display_page.vala',
  'src/pages/panel_page.vala',
  'src/pages/drawer_page.vala',
  'src/pages/power_page.vala',
  'src/pages/osd_page.vala',
  'src/pages/notifications_page.vala',
  'src/pages/lockscreen_page.vala',
  'src/pages/about_page.vala',
  'src/pages/input_common.vala',
  'src/pages/xkb_layouts.vala',
  'src/pages/keyboard_page.vala',
  'src/pages/mouse_page.vala',
  'src/pages/touchpad_page.vala',
  'src/pages/networking_page.vala',
  'src/pages/sound_page.vala',
)

settings_sources += display_profiles_source
settings_sources += tray_catalog_source

# proc_source is needed by the network/sound backends.
settings_sources += proc_source
settings_sources += network_backend_source
settings_sources += sound_source

settings_sources += paths_source
settings_sources += diaglog_source

libxml_settings_dep = dependency('libxml-2.0', required: false)
settings_wayfire_enabled = libxml_settings_dep.found()

if settings_wayfire_enabled
  settings_deps += [libxml_settings_dep]
  settings_vala_args += ['--pkg=libxml-2.0', '--define=WITH_WAYFIRE_CONFIG']
  settings_sources += files(
    'src/wayfire/metadata.vala',
    'src/wayfire/plugin_page.vala',
    'src/wayfire/generic_section_page.vala',
    'src/wayfire/wayfire_pages.vala',
  )
endif

executable('lumen-settings',
  settings_sources + settings_resources,
  vala_args: settings_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: settings_deps,
  install: true,
)

install_data(
  'default-settings-theme.json',
  install_dir: get_option('datadir') / 'lumen-settings',
)

install_data(
  'data/org.lumenshell.Settings.desktop',
  install_dir: get_option('datadir') / 'applications',
)
