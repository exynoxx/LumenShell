project('lumen-panel', ['c', 'vala'],
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

vapi_dir = meson.project_source_root() / '..' / 'vapi'

sources = files(
  'src/main.vala',
  'src/animation.vala',
  'src/utils.vala',
  'src/ini.vala',
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
  'src/components/trays/battery.vala',
  'src/components/trays/battery_service.vala',
  'src/components/trays/batterypage.vala',
  'src/components/trays/clock.vala',
  'src/components/trays/exit.vala',
  'src/components/trays/hoverableicon.vala',
  'src/components/trays/iconandtext.vala',
  'src/components/trays/itray.vala',
  'src/components/trays/itraypage.vala',
  'src/components/trays/nmcli.vala',
  'src/components/trays/pactl.vala',
  'src/components/trays/sound.vala',
  'src/components/trays/soundpage.vala',
  'src/components/trays/wifi.vala',
  'src/components/trays/wifipage.vala',
  'src/components/trays/wifirow.vala',
)

executable('lumen-panel',
  sources,
  vala_args: [
    '--vapidir=' + vapi_dir,
    '--pkg=libdrawkit',
    '--pkg=libwlhooks',
    '--pkg=glesv2',
    '--pkg=egl',
  ],
  dependencies: [
    glib_dep,
    gio_dep,
    gee_dep,
    wayland_dep,
    egl_dep,
    glesv2_dep,
    m_dep,
    drawkit_dep,
    wlhooks_dep,
  ],
  install: true,
)
