# lumen-settings — drop-in build fragment.
#
# To enable in the top-level build, add ONE line near the end of the
# project root meson.build:
#
#   subdir('lumen-settings')
#
# This file references identifiers expected to be defined in the parent
# meson.build (matches existing lumen-osd / lumen-panel blocks):
#   glib_dep, gio_dep, gee_dep, json_dep, gtk4_dep, m_dep, vapi_dir.
#
# Wayfire-config panes (wcm fold) are auto-enabled when libxml-2.0 is
# available on the build host. To force-disable, comment out the
# `if settings_wayfire_enabled` branch below.

settings_gnome = import('gnome')

settings_resources = settings_gnome.compile_resources(
  'lumen-settings-resources',
  'src/resources.gresource.xml',
  source_dir: 'src',
  c_name: 'lumen_settings',
)

adwaita_dep = dependency('libadwaita-1')

settings_deps = [
  glib_dep,
  gio_dep,
  gee_dep,
  json_dep,
  gtk4_dep,
  adwaita_dep,
  m_dep,
  # Display page binds wlr-output-management-v1 in-process via wlhooks on GTK's
  # wl_display (mirrors the lumen-panel link set).
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
  'src/diaglog.vala',
  'src/window.vala',
  'src/sidebar.vala',
  'src/page.vala',
  'src/registry.vala',
  'src/theme.vala',
  'src/widgets/boxed_list.vala',
  'src/widgets/action_row.vala',
  'src/widgets/switch_row.vala',
  'src/widgets/combo_row.vala',
  'src/widgets/spin_row.vala',
  'src/widgets/entry_row.vala',
  'src/widgets/color_row.vala',
  'src/widgets/file_row.vala',
  'src/widgets/binding_row.vala',
  'src/widgets/display_arranger.vala',
  'src/widgets/reorder_list.vala',
  'src/stores/paths.vala',
  'src/stores/json_store.vala',
  'src/stores/ini_store.vala',
  'src/stores/output_manager.vala',
  'src/pages/wallpaper_page.vala',
  'src/pages/display_page.vala',
  'src/pages/panel_page.vala',
  'src/pages/desktop_page.vala',
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
)

# Shared display-profile store (lumen-common) — the Display page saves the
# applied layout here, keyed by the connected monitor set.
settings_sources += display_profiles_source

# Shared tray-applet catalog (lumen-common) — the Panel page's reorder list
# builds its rows from this, the same list lumen-panel resolves config against.
settings_sources += tray_catalog_source

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
