project('lumenshell', ['c', 'vala'],
  version: '1.0',
  default_options: ['optimization=2']
)

cc = meson.get_compiler('c')

glib_dep        = dependency('glib-2.0')
gio_dep         = dependency('gio-2.0')
gee_dep         = dependency('gee-0.8')
json_dep        = dependency('json-glib-1.0')
wayland_dep     = dependency('wayland-client')
egl_dep         = dependency('egl')
glesv2_dep      = dependency('glesv2')
m_dep           = cc.find_library('m')

drawkit_sub = subproject('libdrawkit')
drawkit_dep = drawkit_sub.get_variable('drawkit_dep')

wlhooks_sub = subproject('wlhooks')
wlhooks_dep = wlhooks_sub.get_variable('wlhooks_dep')

vapi_dir = meson.project_source_root() / 'vapi'

common_deps = [
  glib_dep,
  gio_dep,
  gee_dep,
  json_dep,
  wayland_dep,
  egl_dep,
  glesv2_dep,
  m_dep,
  drawkit_dep,
  wlhooks_dep,
]

common_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=libdrawkit',
  '--pkg=libwlhooks',
  '--pkg=glesv2',
  '--pkg=egl',
  '--pkg=json-glib-1.0',
]

# --- lumen-panel ---

panel_sources = files(
  'lumen-panel/src/main.vala',
  'lumen-panel/src/animation.vala',
  'lumen-panel/src/utils.vala',
  'lumen-panel/src/ini.vala',
  'lumen-panel/src/theme.vala',
  'lumen-panel/src/common/button.vala',
  'lumen-panel/src/common/chip.vala',
  'lumen-panel/src/common/horizontal_slider.vala',
  'lumen-panel/src/common/progressbar.vala',
  'lumen-panel/src/common/scrollview.vala',
  'lumen-panel/src/common/signalbars.vala',
  'lumen-panel/src/common/textfield.vala',
  'lumen-panel/src/components/app.vala',
  'lumen-panel/src/components/apppopup.vala',
  'lumen-panel/src/components/panel.vala',
  'lumen-panel/src/components/tray.vala',
  'lumen-panel/src/components/hoverableicon.vala',
  'lumen-panel/src/components/iconandtext.vala',
  'lumen-panel/src/components/itray.vala',
  'lumen-panel/src/components/itraypage.vala',
  'lumen-panel/src/components/battery/battery.vala',
  'lumen-panel/src/components/battery/battery_service.vala',
  'lumen-panel/src/components/battery/batterypage.vala',
  'lumen-panel/src/components/clock/clock.vala',
  'lumen-panel/src/components/exit/exit.vala',
  'lumen-panel/src/components/sound/pactl.vala',
  'lumen-panel/src/components/sound/sound.vala',
  'lumen-panel/src/components/sound/sound_service.vala',
  'lumen-panel/src/components/sound/soundpage.vala',
  'lumen-panel/src/components/wifi/nmcli.vala',
  'lumen-panel/src/components/wifi/wifi.vala',
  'lumen-panel/src/components/wifi/wifi_service.vala',
  'lumen-panel/src/components/wifi/wifipage.vala',
  'lumen-panel/src/components/wifi/wifirow.vala',
)

executable('lumen-panel',
  panel_sources,
  vala_args: common_vala_args,
  dependencies: common_deps,
  install: true,
)

# --- Kickoff ---

kickoff_sources = files(
  'Kickoff/src/main.vala',
  'Kickoff/src/animation.vala',
  'Kickoff/src/appentry.vala',
  'Kickoff/src/keyboard.vala',
  'Kickoff/src/processor.vala',
  'Kickoff/src/searchdb.vala',
  'Kickoff/src/components/appview.vala',
  'Kickoff/src/components/gridview.vala',
  'Kickoff/src/components/igrid.vala',
  'Kickoff/src/components/navigationbar.vala',
  'Kickoff/src/components/position.vala',
  'Kickoff/src/components/searchbar.vala',
  'Kickoff/src/components/searchgridview.vala',
  'Kickoff/src/utils/aliasarray.vala',
  'Kickoff/src/utils/config.vala',
  'Kickoff/src/utils/icon.vala',
  'Kickoff/src/utils/image.vala',
  'Kickoff/src/utils/math.vala',
  'Kickoff/src/utils/serialization.vala',
  'Kickoff/src/utils/span.vala',
  'Kickoff/src/utils/system.vala',
)

executable('kickoff',
  kickoff_sources,
  vala_args: common_vala_args,
  dependencies: common_deps,
  install: true,
)

# --- lumen-osd ---
# Independent dep set: no drawkit, no wlhooks, no GLES.
gtk4_dep             = dependency('gtk4')
gtk4_layer_shell_dep = dependency('gtk4-layer-shell-0')

osd_deps = [
  glib_dep,
  gio_dep,
  json_dep,
  gtk4_dep,
  gtk4_layer_shell_dep,
  m_dep,
]

osd_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=json-glib-1.0',
]

osd_sources = files(
  'lumen-osd/src/main.vala',
  'lumen-osd/src/window.vala',
  'lumen-osd/src/utils.vala',
  'lumen-osd/src/theme.vala',
  'lumen-osd/src/pill.vala',
  'lumen-osd/src/dbus.vala',
  'lumen-osd/src/state_watcher.vala',
)

executable('lumen-osd',
  osd_sources,
  vala_args: osd_vala_args,
  dependencies: osd_deps,
  install: true,
)

install_data(
  'lumen-osd/default-theme.json',
  install_dir: get_option('datadir') / 'lumen-osd',
)

# --- lumen-notifications ---
# Independent dep set: no drawkit, no wlhooks, no GLES.
# Reuses gtk4_dep and gtk4_layer_shell_dep from lumen-osd block above.
notif_deps = [
  glib_dep,
  gio_dep,
  json_dep,
  gtk4_dep,
  gtk4_layer_shell_dep,
  m_dep,
]

notif_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=json-glib-1.0',
]

notif_sources = files(
  'lumen-notifications/src/main.vala',
  'lumen-notifications/src/utils.vala',
  'lumen-notifications/src/theme.vala',
  'lumen-notifications/src/dbus_service.vala',
  'lumen-notifications/src/notification.vala',
  'lumen-notifications/src/notification_manager.vala',
  'lumen-notifications/src/banner.vala',
  'lumen-notifications/src/stack.vala',
  'lumen-notifications/src/layer_window.vala',
)

executable('lumen-notifications',
  notif_sources,
  vala_args: notif_vala_args,
  dependencies: notif_deps,
  install: true,
)

install_data(
  'lumen-notifications/default-notifications-theme.json',
  install_dir: get_option('datadir') / 'lumen-notifications',
)

# --- lumen-osdctl ---
osdctl_deps = [glib_dep, gio_dep, m_dep]

osdctl_vala_args = [
  '--pkg=gio-2.0',
  '--pkg=glib-2.0',
]

osdctl_sources = files(
  'lumen-osdctl/src/main.vala',
  'lumen-osdctl/src/backends.vala',
  'lumen-osdctl/src/dbus_proxy.vala',
)

executable('lumen-osdctl',
  osdctl_sources,
  vala_args: osdctl_vala_args,
  dependencies: osdctl_deps,
  install: true,
)
