project('lumenshell', ['c', 'vala'],
  version: '1.0',
  default_options: ['buildtype=release']
)

cc = meson.get_compiler('c')

glib_dep        = dependency('glib-2.0')
gio_dep         = dependency('gio-2.0')
gee_dep         = dependency('gee-0.8')
json_dep        = dependency('json-glib-1.0')
wayland_dep     = dependency('wayland-client')
m_dep           = cc.find_library('m')

wlhooks_sub = subproject('wlhooks')
wlhooks_dep = wlhooks_sub.get_variable('wlhooks_dep')

vapi_dir = meson.project_source_root() / 'vapi'

# Install datadir baked in for Paths.theme_file; required on every target
# compiling paths_source (it declares extern LUMEN_DATADIR).
lumen_datadir_c_args = [
  '-DLUMEN_DATADIR="' + (get_option('prefix') / get_option('datadir')) + '"',
]

# Requires lumen_datadir_c_args on the consuming target.
paths_source = files(
  'lumen-common/paths.vala',
)

# Needs json-glib + gtk4 on the consuming target.
theme_json_source = files(
  'lumen-common/theme_json.vala',
)

# Needs --pkg=posix on the consuming target.
diaglog_source = files(
  'lumen-common/diaglog.vala',
)

desktop_exec_source = files(
  'lumen-common/desktop_exec.vala',
)

proc_source = files(
  'lumen-common/proc.vala',
)

display_profiles_source = files(
  'lumen-common/display_profiles.vala',
)

# Requires wayland + wlhooks + display_profiles_source on the consuming target.
display_ctl_source = files(
  'lumen-common/display_ctl.vala',
)

# --- lumen-osd ---
gtk4_dep             = dependency('gtk4')
gtk4_layer_shell_dep = dependency('gtk4-layer-shell-0')
# Top-level only for lumen-drawer's Adw.Carousel.
adwaita_dep          = dependency('libadwaita-1')

osd_deps = [
  glib_dep,
  gio_dep,
  json_dep,
  gtk4_dep,
  gtk4_layer_shell_dep,
  wayland_dep,
  wlhooks_dep,
  m_dep,
]

osd_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=json-glib-1.0',
  '--pkg=wayland-client',
  '--pkg=libwlhooks',
]

osd_sources = files(
  'lumen-osd/src/main.vala',
  'lumen-osd/src/window.vala',
  'lumen-osd/src/window_group.vala',
  'lumen-osd/src/utils.vala',
  'lumen-osd/src/theme.vala',
  'lumen-osd/src/pill.vala',
  'lumen-osd/src/selector.vala',
  'lumen-osd/src/picker.vala',
  'lumen-osd/src/presenter.vala',
  'lumen-osd/src/dbus.vala',
  'lumen-osd/src/state_watcher.vala',
)

executable('lumen-osd',
  osd_sources + paths_source + theme_json_source + proc_source + display_ctl_source + display_profiles_source,
  vala_args: osd_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: osd_deps,
  install: true,
)

# --- lumen-panel (GTK4 + gtk4-layer-shell + GSK) ---
gtk4_wayland_dep = dependency('gtk4-wayland')
gnome = import('gnome')

panel_resources = gnome.compile_resources(
  'lumen-panel-resources',
  'lumen-panel/src/resources.gresource.xml',
  source_dir: 'lumen-panel/src',
  c_name: 'panel',
)

gio_unix_dep = dependency('gio-unix-2.0')

panel_deps = [
  # gtk4-layer-shell MUST appear before gtk4/wayland-client in the link line,
  # otherwise gtk_layer_init_for_window() silently no-ops at runtime.
  # See https://github.com/wmww/gtk4-layer-shell/blob/main/linking.md
  gtk4_layer_shell_dep,
  gtk4_dep,
  gtk4_wayland_dep,
  wayland_dep,
  wlhooks_dep,
  glib_dep,
  gio_dep,
  gio_unix_dep,
  gee_dep,
  json_dep,
  m_dep,
]

panel_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=gtk4-wayland',
  '--pkg=gee-0.8',
  '--pkg=json-glib-1.0',
  '--pkg=libwlhooks',
  '--pkg=cairo',
  '--pkg=posix',
  # gio-unix: UnixFDList for the logind delay-inhibitor (lumen-common/logind.vala)
  '--pkg=gio-unix-2.0',
]

lumen_common_sources = files(
  'lumen-common/logind.vala',
)

accounts_source = files(
  'lumen-common/accounts.vala',
)

# Needs proc_source + json_dep on the consuming target.
network_backend_source = files(
  'lumen-common/nmcli.vala',
  'lumen-common/wifi_service.vala',
  'lumen-common/btctl.vala',
  'lumen-common/bluetooth_service.vala',
  'lumen-common/radio_state.vala',
)

# Needs proc_source on the consuming target.
sound_source = files(
  'lumen-common/sound_pactl.vala',
  'lumen-common/sound_service.vala',
)

dbus_cli_source = files(
  'lumen-common/dbus_cli.vala',
)

tray_catalog_source = files(
  'lumen-common/tray_applets.vala',
)

panel_peek_sources = []
if get_option('with_panel_peek')
  panel_vala_args += ['--define=PANEL_PEEK']
  panel_peek_sources = files(
    'lumen-common/wayfire_ipc.vala',
    'lumen-panel/src/peek_ipc.vala',
    'lumen-panel/src/components/launcher.vala',
  )
endif

panel_sources = files(
  'lumen-panel/src/main.vala',
  'lumen-panel/src/panel_window.vala',
  'lumen-panel/src/theme.vala',
  'lumen-panel/src/panel_config.vala',
  'lumen-panel/src/panel_service.vala',
  'lumen-panel/src/utils.vala',
  'lumen-panel/src/wl/toplevels.vala',
  'lumen-panel/src/widgets/tray_button.vala',
  'lumen-panel/src/widgets/tray.vala',
  'lumen-panel/src/widgets/tray_reveal.vala',
  'lumen-panel/src/widgets/tray_registry.vala',
  'lumen-panel/src/widgets/wifi_arc.vala',
  'lumen-panel/src/widgets/cc_slider.vala',
  'lumen-panel/src/widgets/progress_bar.vala',
  'lumen-panel/src/widgets/text_field.vala',
  'lumen-panel/src/widgets/segmented_control.vala',
  'lumen-panel/src/components/control_center/control_module.vala',
  'lumen-panel/src/components/control_center/control_center.vala',
  'lumen-panel/src/components/clock/clock.vala',
  'lumen-panel/src/components/exit/exit.vala',
  'lumen-panel/src/components/app.vala',
  'lumen-panel/src/components/apppopup.vala',
  'lumen-panel/src/components/panel.vala',
  'lumen-panel/src/components/sni/sni_watcher.vala',
  'lumen-panel/src/components/sni/sni_item.vala',
  'lumen-panel/src/components/sni/sni_menu.vala',
  'lumen-panel/src/components/sni/systray.vala',
  'lumen-panel/src/components/battery/battery.vala',
  'lumen-panel/src/components/battery/battery_service.vala',
  'lumen-panel/src/components/battery/battery_module.vala',
  'lumen-panel/src/components/battery/power_profile.vala',
  'lumen-panel/src/components/battery/power_profile_service.vala',
  'lumen-panel/src/components/sound/sound.vala',
  'lumen-panel/src/components/sound/sound_module.vala',
  'lumen-panel/src/components/sound/sound_detail.vala',
  'lumen-panel/src/components/brightness/brightness_service.vala',
  'lumen-panel/src/components/wifi/wifi.vala',
  'lumen-panel/src/components/wifi/wifirow.vala',
  'lumen-panel/src/components/wifi/wifi_module.vala',
  'lumen-panel/src/components/wifi/wifi_detail.vala',
  'lumen-panel/src/components/bluetooth/bluetooth.vala',
  'lumen-panel/src/components/bluetooth/bluetoothrow.vala',
  'lumen-panel/src/components/bluetooth/bluetooth_module.vala',
  'lumen-panel/src/components/bluetooth/bluetooth_detail.vala',
)

executable('lumen-panel',
  panel_sources + panel_peek_sources + panel_resources + lumen_common_sources + proc_source + tray_catalog_source + network_backend_source + sound_source + paths_source,
  vala_args: panel_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: panel_deps,
  link_args: ['-Wl,--no-as-needed'],
  install: true,
)

install_data(
  'default-theme.json',
  install_dir: get_option('datadir') / 'lumen-panel',
)

# --- lumen-notifications ---
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
  notif_sources + paths_source + theme_json_source,
  vala_args: notif_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: notif_deps,
  install: true,
)

# --- lumen-drawer ---
drawer_deps = [
  # Same link-order rule as lumen-panel: gtk4-layer-shell must come before
  # gtk4/wayland-client/wlhooks for layer-shell init to actually take effect.
  gtk4_layer_shell_dep,
  gtk4_dep,
  gtk4_wayland_dep,
  wayland_dep,
  wlhooks_dep,
  adwaita_dep,
  glib_dep,
  gio_dep,
  gio_unix_dep,
  m_dep,
]

drawer_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=gtk4-wayland',
  '--pkg=libadwaita-1',
  '--pkg=glib-2.0',
  '--pkg=gio-2.0',
  '--pkg=gio-unix-2.0',
  '--pkg=libwlhooks',
]

drawer_sources = files(
  'lumen-common/wayfire_ipc.vala',
  'lumen-drawer/src/main.vala',
  'lumen-drawer/src/drawer_config.vala',
  'lumen-drawer/src/window.vala',
  'lumen-drawer/src/appentry.vala',
  'lumen-drawer/src/searchdb.vala',
  'lumen-drawer/src/curtain_ipc.vala',
  'lumen-drawer/src/wl/toplevels.vala',
  'lumen-drawer/src/components/apptile.vala',
  'lumen-drawer/src/components/pagedgrid.vala',
  'lumen-drawer/src/components/searchresults.vala',
  'lumen-drawer/src/components/pagedots.vala',
)

executable('lumen-drawer',
  drawer_sources + paths_source + desktop_exec_source,
  vala_args: drawer_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: drawer_deps,
  link_args: ['-Wl,--no-as-needed'],
  install: true,
)

# --- lumen-desktop ---
# Same link-order rule as lumen-panel: gtk4-layer-shell first.
desktopwidgets_deps = [
  gtk4_layer_shell_dep,
  gtk4_dep,
  gtk4_wayland_dep,
  wayland_dep,
  glib_dep,
  gio_dep,
  json_dep,
  m_dep,
]

desktopwidgets_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=gtk4-wayland',
  '--pkg=glib-2.0',
  '--pkg=gio-2.0',
  '--pkg=json-glib-1.0',
]

desktopwidgets_sources = files(
  'lumen-desktop/src/main.vala',
  'lumen-desktop/src/window.vala',
  'lumen-desktop/src/desktop_config.vala',
  'lumen-desktop/src/widget/widget_shape.vala',
  'lumen-desktop/src/widget/widget_settings.vala',
  'lumen-desktop/src/widget/chrome_buttons.vala',
  'lumen-desktop/src/widget/desktop_widget.vala',
  'lumen-desktop/src/widget/widget_registry.vala',
  'lumen-desktop/src/widget/widget_host.vala',
  'lumen-desktop/src/widgets/filebrowser/fs_model.vala',
  'lumen-desktop/src/widgets/filebrowser/file_row.vala',
  'lumen-desktop/src/widgets/filebrowser/file_column.vala',
  'lumen-desktop/src/widgets/filebrowser/column_browser.vala',
  'lumen-desktop/src/widgets/filebrowser/file_browser_widget.vala',
)

executable('lumen-desktop',
  desktopwidgets_sources + paths_source,
  vala_args: desktopwidgets_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: desktopwidgets_deps,
  link_args: ['-Wl,--no-as-needed'],
  install: true,
)

install_data('lumen-desktop/default-desktop.json',
  install_dir: get_option('datadir') / 'lumen-desktop')

# --- lumen-osdctl ---
osdctl_deps = [glib_dep, gio_dep, json_dep, wayland_dep, wlhooks_dep, m_dep]

osdctl_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gio-2.0',
  '--pkg=glib-2.0',
  '--pkg=json-glib-1.0',
  '--pkg=wayland-client',
  '--pkg=libwlhooks',
]

osdctl_sources = files(
  'lumen-osdctl/src/main.vala',
  'lumen-osdctl/src/backends.vala',
  'lumen-osdctl/src/dbus_proxy.vala',
)

executable('lumen-osdctl',
  osdctl_sources + proc_source + dbus_cli_source + paths_source + display_profiles_source + display_ctl_source,
  vala_args: osdctl_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: osdctl_deps,
  install: true,
)

# --- lumen-session (headless; no GTK) ---
session_deps = [
  glib_dep,
  gio_dep,
  json_dep,
  wayland_dep,
  wlhooks_dep,
  m_dep,
]

session_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=glib-2.0',
  '--pkg=gio-2.0',
  '--pkg=json-glib-1.0',
  '--pkg=wayland-client',
  '--pkg=libwlhooks',
]

session_sources = files(
  'lumen-session/src/main.vala',
)

executable('lumen-session',
  session_sources + display_profiles_source + accounts_source + paths_source,
  vala_args: session_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: session_deps,
  install: true,
)

# --- lumen-settings (drop-in fragment) ---
subdir('lumen-settings')

# --- lumen-polkit-agent ---
# The polkit vapis ship with Vala; only the -devel .pc files are a build prereq.
polkit_agent_dep   = dependency('polkit-agent-1',   required: get_option('with_polkit_agent'))
polkit_gobject_dep = dependency('polkit-gobject-1', required: get_option('with_polkit_agent'))

if get_option('with_polkit_agent').allowed() and polkit_agent_dep.found() and polkit_gobject_dep.found()
  executable('lumen-polkit-agent',
    files(
      'lumen-polkit-agent/src/main.vala',
      'lumen-polkit-agent/src/listener.vala',
      'lumen-polkit-agent/src/auth_flow.vala',
      'lumen-polkit-agent/src/dialog.vala',
    ),
    vala_args: [
      '--vapidir=' + vapi_dir,
      '--pkg=gtk4',
      '--pkg=gtk4-layer-shell-0',
      '--pkg=polkit-agent-1',
      '--pkg=polkit-gobject-1',
      '--pkg=posix',
    ],
    # polkit refuses to expose its headers without these opt-in defines.
    c_args: [
      '-DPOLKIT_AGENT_I_KNOW_API_IS_SUBJECT_TO_CHANGE',
      '-DPOLKIT_GOBJECT_I_KNOW_API_IS_SUBJECT_TO_CHANGE',
    ],
    dependencies: [
      # gtk4-layer-shell MUST precede gtk4 (same rule as lumen-panel).
      gtk4_layer_shell_dep,
      gtk4_dep,
      glib_dep,
      gio_dep,
      polkit_agent_dep,
      polkit_gobject_dep,
      m_dep,
    ],
    # Keep the linker from dropping layer-shell as "unused".
    link_args: ['-Wl,--no-as-needed'],
    install: true,
  )
  message('lumen-polkit-agent: enabled')
else
  message('lumen-polkit-agent: disabled (need polkit-agent-1 + polkit-gobject-1)')
endif

# --- lumen-lockscreen + lumen-lockctl ---
gtk4_session_lock_dep = dependency('gtk4-session-lock-0', required: get_option('with_lockscreen'))
pam_dep               = cc.find_library('pam', required: get_option('with_lockscreen'))

if get_option('with_lockscreen').allowed() and gtk4_session_lock_dep.found() and pam_dep.found()

  lockscreen_resources = gnome.compile_resources(
    'lumen-lockscreen-resources',
    'lumen-lockscreen/src/resources.gresource.xml',
    source_dir: 'lumen-lockscreen/src',
    c_name: 'lumen_lockscreen',
  )

  lockscreen_deps = [
    # gtk4-session-lock MUST precede gtk4/wayland in the link line (same rule as
    # gtk4-layer-shell), or the lock-surface protocol hook silently no-ops.
    gtk4_session_lock_dep,
    gtk4_dep,
    gtk4_wayland_dep,
    wayland_dep,
    wlhooks_dep,
    glib_dep,
    gio_dep,
    # UnixFDList for logind.vala's sleep delay-inhibitor.
    gio_unix_dep,
    json_dep,
    pam_dep,
    m_dep,
  ]

  lockscreen_vala_args = [
    '--vapidir=' + vapi_dir,
    '--pkg=gtk4',
    '--pkg=gtk4-session-lock-0',
    '--pkg=gtk4-wayland',
    '--pkg=libwlhooks',
    '--pkg=json-glib-1.0',
    '--pkg=glib-2.0',
    '--pkg=gio-2.0',
    '--pkg=gio-unix-2.0',
    '--pkg=posix',
    '--pkg=pam_auth',
  ]

  lockscreen_sources = files(
    'lumen-lockscreen/src/main.vala',
    'lumen-lockscreen/src/manager.vala',
    'lumen-lockscreen/src/window.vala',
    'lumen-lockscreen/src/theme.vala',
    'lumen-lockscreen/src/utils.vala',
    'lumen-lockscreen/src/dbus.vala',
    'lumen-lockscreen/src/auth.vala',
    'lumen-lockscreen/src/idle.vala',
    'lumen-lockscreen/src/widgets/background.vala',
    'lumen-lockscreen/src/widgets/blurred_wallpaper.vala',
    'lumen-lockscreen/src/widgets/clock.vala',
    'lumen-lockscreen/src/widgets/avatar.vala',
    'lumen-lockscreen/src/widgets/password.vala',
    'lumen-lockscreen/src/widgets/power_menu.vala',
    'lumen-lockscreen/src/pam_auth.c',
  )

  executable('lumen-lockscreen',
    lockscreen_sources + lockscreen_resources + lumen_common_sources + accounts_source + paths_source + theme_json_source + diaglog_source,
    vala_args: lockscreen_vala_args,
    c_args: lumen_datadir_c_args,
    dependencies: lockscreen_deps,
    include_directories: include_directories('lumen-lockscreen/src'),
    link_args: ['-Wl,--no-as-needed'],
    install: true,
  )

  executable('lumen-lockctl',
    files(
      'lumen-lockctl/src/main.vala',
      'lumen-lockctl/src/dbus_proxy.vala',
    ) + dbus_cli_source,
    vala_args: ['--pkg=gio-2.0', '--pkg=glib-2.0'],
    dependencies: [glib_dep, gio_dep, m_dep],
    install: true,
  )

  # Always /etc/pam.d, never under the install prefix.
  install_data(
    'lumen-lockscreen/data/pam.d/lumen-lockscreen',
    install_dir: '/etc/pam.d',
  )

  message('lumen-lockscreen: enabled')
else
  message('lumen-lockscreen: disabled (need gtk4-session-lock-0 + pam)')
endif

# --- session / XDG portal glue ---
# The target binds graphical-session.target so xdg-desktop-portal can start
# under Wayfire. systemd user units always go in <prefix>/lib, never lib64.
install_data(
  'data/systemd/lumenshell-session.target',
  install_dir: get_option('prefix') / 'lib' / 'systemd' / 'user',
)
install_data(
  'data/xdg-desktop-portal/lumenshell-portals.conf',
  install_dir: get_option('datadir') / 'xdg-desktop-portal',
)

# Display-manager session glue. @BINDIR@ is substituted so Exec= matches the
# actual install prefix.
session_conf = configuration_data()
session_conf.set('BINDIR', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'lumen-lockscreen/data/wayland-sessions/lumenshell.desktop.in',
  output: 'lumenshell.desktop',
  configuration: session_conf,
  install_dir: get_option('datadir') / 'wayland-sessions',
)
install_data(
  'lumen-lockscreen/data/bin/start-lumenshell',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)
# Path is referenced by the snippet's own header; keep them in sync.
install_data(
  'lumen-lockscreen/data/wayfire/lumenshell.ini.d/autostart.ini',
  install_dir: get_option('datadir') / 'lumenshell' / 'wayfire.ini.d',
)

# --- wayfire-plugins/* ---
# C++ is only enabled when a plugin is, so the Vala tree builds without it.
if get_option('with_desktop_peek') \
   or get_option('with_curtain_peek') \
   or get_option('with_slide_peek') \
   or get_option('with_panel_push') \
   or get_option('with_startup_zoom') \
   or get_option('with_night_light')
  add_languages('cpp', native: false)
endif

if get_option('with_desktop_peek')
  subdir('wayfire-plugins/desktop-peek')
endif

if get_option('with_curtain_peek')
  subdir('wayfire-plugins/curtain-peek')
endif

if get_option('with_slide_peek')
  subdir('wayfire-plugins/slide-peek')
endif

if get_option('with_panel_push')
  subdir('wayfire-plugins/panel-push')
endif

if get_option('with_startup_zoom')
  subdir('wayfire-plugins/startup-zoom')
endif

if get_option('with_night_light')
  subdir('wayfire-plugins/night-light')
endif

# --- dev environment (`meson devenv -C build`) ---
# GSK_RENDERER mirrors start-lumenshell so dev runs match the real session.
devenv = environment()
devenv.set('LUMEN_THEME_FILE', meson.project_source_root() / 'default-theme.json')
devenv.set('GSK_RENDERER', 'ngl')
meson.add_devenv(devenv)
