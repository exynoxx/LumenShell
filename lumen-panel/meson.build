project('lumen-panel', ['c', 'vala'],
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

vapi_dir = meson.project_source_root() / '..' / 'vapi'

sources = files(
  'src/main.vala',
  'src/animation.vala',
  'src/utils.vala',
  'src/ini.vala',
  'src/theme.vala',
  'src/common/button.vala',
  'src/common/chip.vala',
  'src/common/horizontal_slider.vala',
  'src/common/progressbar.vala',
  'src/common/scrollview.vala',
  'src/common/signalbars.vala',
  'src/common/textfield.vala',
  'src/components/app.vala',
  'src/components/apppopup.vala',
  'src/components/panel.vala',
  'src/components/tray.vala',
  'src/components/hoverableicon.vala',
  'src/components/iconandtext.vala',
  'src/components/itray.vala',
  'src/components/itraypage.vala',
  'src/components/battery/battery.vala',
  'src/components/battery/battery_service.vala',
  'src/components/battery/batterypage.vala',
  'src/components/clock/clock.vala',
  'src/components/exit/exit.vala',
  'src/components/sound/pactl.vala',
  'src/components/sound/sound.vala',
  'src/components/sound/soundpage.vala',
  'src/components/sound/sound_service.vala',
  'src/components/wifi/nmcli.vala',
  'src/components/wifi/wifi.vala',
  'src/components/wifi/wifi_service.vala',
  'src/components/wifi/wifipage.vala',
  'src/components/wifi/wifirow.vala',
)

executable('lumen-panel',
  sources,
  vala_args: [
    '--vapidir=' + vapi_dir,
    '--pkg=libdrawkit',
    '--pkg=libwlhooks',
    '--pkg=glesv2',
    '--pkg=egl',
    '--pkg=json-glib-1.0',
  ],
  dependencies: [
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
  ],
  install: true,
)
