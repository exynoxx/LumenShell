project('lumenshell', ['c', 'vala'],
  version: '1.0',
  default_options: ['optimization=2']
)

cc = meson.get_compiler('c')

glib_dep        = dependency('glib-2.0')
gio_dep         = dependency('gio-2.0')
gee_dep         = dependency('gee-0.8')
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
]

# --- lumen-panel ---

panel_sources = files(
  'lumen-panel/src/main.vala',
  'lumen-panel/src/animation.vala',
  'lumen-panel/src/utils.vala',
  'lumen-panel/src/ini.vala',
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
  'lumen-panel/src/components/trays/battery.vala',
  'lumen-panel/src/components/trays/battery_service.vala',
  'lumen-panel/src/components/trays/batterypage.vala',
  'lumen-panel/src/components/trays/clock.vala',
  'lumen-panel/src/components/trays/exit.vala',
  'lumen-panel/src/components/trays/hoverableicon.vala',
  'lumen-panel/src/components/trays/iconandtext.vala',
  'lumen-panel/src/components/trays/itray.vala',
  'lumen-panel/src/components/trays/itraypage.vala',
  'lumen-panel/src/components/trays/nmcli.vala',
  'lumen-panel/src/components/trays/pactl.vala',
  'lumen-panel/src/components/trays/sound.vala',
  'lumen-panel/src/components/trays/soundpage.vala',
  'lumen-panel/src/components/trays/wifi.vala',
  'lumen-panel/src/components/trays/wifipage.vala',
  'lumen-panel/src/components/trays/wifirow.vala',
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
