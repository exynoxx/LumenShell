project('lumenshell', ['c', 'vala'],
  version: '1.0',
  default_options: ['buildtype=release']
)

cc = meson.get_compiler('c')
fs = import('fs')

# FreeBSD: native backends replace the Linux-only ones (sysfs, prctl, nmcli,
# rfkill, BlueZ, brightnessctl, systemd). Vala sees --define=FREEBSD, C sees
# -DLUMEN_FREEBSD. See docs/FREEBSD.md.
is_freebsd = host_machine.system() == 'freebsd'
if is_freebsd
  add_project_arguments('--define=FREEBSD', language: 'vala')
  add_project_arguments(
    '-DLUMEN_FREEBSD',
    '-I' + (meson.project_source_root() / 'lumen-common' / 'bsd'),
    language: 'c',
  )
endif

glib_dep        = dependency('glib-2.0')
gio_dep         = dependency('gio-2.0')
gee_dep         = dependency('gee-0.8')
json_dep        = dependency('json-glib-1.0')
wayland_dep     = dependency('wayland-client')
m_dep           = cc.find_library('m')

wlhooks_sub = subproject('wlhooks')
wlhooks_dep = wlhooks_sub.get_variable('wlhooks_dep')

vapi_dir = meson.project_source_root() / 'vapi'

# lumen-common is compiled into each binary in four groups, split only by the
# libraries they need; a target may carry a few files it never calls.
# Install datadir baked in for Paths.theme_file: every target compiling
# common_base needs lumen_datadir_c_args (paths.vala declares extern LUMEN_DATADIR).
lumen_datadir_c_args = [
  '-DLUMEN_DATADIR="' + (get_option('prefix') / get_option('datadir')) + '"',
]

# glib/gio + json-glib.
common_base = files(
  'lumen-common/paths.vala',
  'lumen-common/proc.vala',
  'lumen-common/dbus_cli.vala',
  'lumen-common/lock_proxy.vala',
  'lumen-common/desktop_exec.vala',
  'lumen-common/accounts.vala',
  'lumen-common/display_profiles.vala',
  'lumen-common/tray_applets.vala',
)

# FreeBSD: sysctl/kenv/procctl/backlight shim (proc.vala needs it in every
# target) and the OSS mixer, which lumen-osdctl uses without common_net.
if is_freebsd
  common_base += files(
    'lumen-common/bsd/lumen_bsd.c',
    'lumen-common/bsd/bsd.vala',
    'lumen-common/bsd/oss_mixer.vala',
  )
endif

# + gtk4.
common_gtk = files(
  'lumen-common/theme_json.vala',
  'lumen-common/css.vala',
  'lumen-common/draw.vala',
  'lumen-common/monitors.vala',
)

# + posix, gio-unix (UnixFDList, UnixSocketAddress).
common_system = files(
  'lumen-common/logind.vala',
  'lumen-common/diaglog.vala',
  'lumen-common/wayfire_ipc.vala',
)

# Network + sound backends (panel tray, settings pages).
common_net = files(
  'lumen-common/nmcli.vala',
  'lumen-common/wifi_service.vala',
  'lumen-common/btctl.vala',
  'lumen-common/bluetooth_service.vala',
  'lumen-common/sound_pactl.vala',
  'lumen-common/sound_service.vala',
)
# FreeBSD: wpa_supplicant/ifconfig Wi-Fi and OSS sound clients. nmcli.vala
# and sound_pactl.vala stay: they also define the shared data classes.
if is_freebsd
  common_net += files(
    'lumen-common/bsd/wpa_cli.vala',
    'lumen-common/bsd/sound_oss.vala',
  )
endif

# + wayland + wlhooks.
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
  osd_sources + common_base + common_gtk + display_ctl_source,
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

panel_peek_sources = []
if get_option('with_panel_peek')
  panel_vala_args += ['--define=PANEL_PEEK']
  panel_peek_sources = files(
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
  'lumen-panel/src/widgets/wifi_arc.vala',
  'lumen-panel/src/widgets/cc_slider.vala',
  'lumen-panel/src/widgets/progress_bar.vala',
  'lumen-panel/src/widgets/text_field.vala',
  'lumen-panel/src/widgets/segmented_control.vala',
  'lumen-panel/src/components/control_center/control_module.vala',
  'lumen-panel/src/components/control_center/control_center.vala',
  'lumen-panel/src/components/search/search.vala',
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
  panel_sources + panel_peek_sources + panel_resources + common_base + common_gtk + common_system + common_net,
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
  notif_sources + common_base + common_gtk,
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
  json_dep,
  m_dep,
]

drawer_vala_args = [
  '--vapidir=' + vapi_dir,
  # Binds PatternSpec.match_string to the non-deprecated GLib ≥ 2.70 symbol.
  '--target-glib=auto',
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=gtk4-wayland',
  '--pkg=libadwaita-1',
  '--pkg=glib-2.0',
  '--pkg=gio-2.0',
  '--pkg=gio-unix-2.0',
  '--pkg=json-glib-1.0',
  '--pkg=posix',
  '--pkg=libwlhooks',
]

drawer_sources = files(
  'lumen-drawer/src/main.vala',
  'lumen-drawer/src/drawer_config.vala',
  'lumen-drawer/src/window.vala',
  'lumen-drawer/src/appentry.vala',
  'lumen-drawer/src/searchdb.vala',
  'lumen-drawer/src/wl/toplevels.vala',
  'lumen-drawer/src/components/apptile.vala',
  'lumen-drawer/src/components/pagedgrid.vala',
  'lumen-drawer/src/components/searchresults.vala',
  'lumen-drawer/src/components/pagedots.vala',
)

executable('lumen-drawer',
  drawer_sources + common_base + common_gtk + common_system,
  vala_args: drawer_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: drawer_deps,
  link_args: ['-Wl,--no-as-needed'],
  install: true,
)

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
  osdctl_sources + common_base + display_ctl_source,
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
  session_sources + common_base,
  vala_args: session_vala_args,
  c_args: lumen_datadir_c_args,
  dependencies: session_deps,
  install: true,
)

test('display-identity', executable('test-display-identity',
  files('tests/display_identity.vala') + common_base,
  c_args: lumen_datadir_c_args,
  dependencies: [glib_dep, gio_dep, json_dep],
))

search_core_source = files(
  'lumen-search/src/fuzzy.vala',
  'lumen-search/src/types.vala',
  'lumen-search/src/junk.vala',
  'lumen-search/src/query.vala',
  'lumen-search/src/rank.vala',
)

test('search-core', executable('test-search-core',
  files('tests/search_core.vala') + search_core_source,
  dependencies: [glib_dep, gio_dep],
))

# --- lumen-search ---
tinysparql_dep = dependency('tinysparql-3.0', required: get_option('with_search'))

if get_option('with_search').allowed() and tinysparql_dep.found()
  search_sources = files(
    'lumen-search/src/config.vala',
    'lumen-search/src/index.vala',
    'lumen-search/src/content.vala',
    'lumen-search/src/result_row.vala',
    'lumen-search/src/window.vala',
    'lumen-search/src/main.vala',
  )

  executable('lumen-search',
    search_sources + search_core_source + common_base + common_gtk,
    vala_args: [
      '--vapidir=' + vapi_dir,
      '--pkg=gtk4',
      '--pkg=gtk4-layer-shell-0',
      '--pkg=json-glib-1.0',
      '--pkg=tinysparql-3.0',
      '--pkg=gio-unix-2.0',
      '--pkg=glib-2.0',
      '--pkg=gio-2.0',
    ],
    c_args: lumen_datadir_c_args,
    # gtk4-layer-shell MUST precede gtk4/wayland.
    dependencies: [gtk4_layer_shell_dep, gtk4_dep, wayland_dep, glib_dep, gio_dep, gio_unix_dep, json_dep, tinysparql_dep, m_dep],
    link_args: ['-Wl,--no-as-needed'],
    install: true,
  )
endif

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
    ) + common_gtk,
    vala_args: [
      '--vapidir=' + vapi_dir,
      '--pkg=gtk4',
      '--pkg=gtk4-layer-shell-0',
      '--pkg=polkit-agent-1',
      '--pkg=polkit-gobject-1',
      '--pkg=posix',
      '--pkg=json-glib-1.0',
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
      json_dep,
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
# gtk4-layer-shell >= 1.1 ships the same gtk_session_lock_* API (header
# gtk4-session-lock.h) inside libgtk4-layer-shell, which is what FreeBSD's
# x11-toolkits/gtk4-layer-shell provides; fall back to it when the standalone
# gtk4-session-lock-0 isn't installed.
gtk4_session_lock_dep = dependency('gtk4-session-lock-0', required: false)
if not gtk4_session_lock_dep.found()
  gtk4_session_lock_dep = dependency('gtk4-layer-shell-0', version: '>=1.1.0',
                                     required: get_option('with_lockscreen'))
endif
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

  lockscreen_c_args = lumen_datadir_c_args
  if is_freebsd
    # OpenPAM's pam_unix needs root to read master.passwd: the locker asks this
    # setuid helper instead (lumen-lockscreen/src/bsd/lumen-chkpass.c).
    chkpass_path = get_option('prefix') / get_option('libexecdir') / 'lumen-chkpass'
    lockscreen_c_args += ['-DLUMEN_CHKPASS_PATH="' + chkpass_path + '"']
    executable('lumen-chkpass',
      files('lumen-lockscreen/src/bsd/lumen-chkpass.c'),
      dependencies: [pam_dep],
      install: true,
      install_dir: get_option('libexecdir'),
      install_mode: 'rwsr-xr-x',
    )
  endif

  executable('lumen-lockscreen',
    lockscreen_sources + lockscreen_resources + common_base + common_gtk + common_system,
    vala_args: lockscreen_vala_args,
    c_args: lockscreen_c_args,
    dependencies: lockscreen_deps,
    include_directories: include_directories('lumen-lockscreen/src'),
    link_args: ['-Wl,--no-as-needed'],
    install: true,
  )

  executable('lumen-lockctl',
    files('lumen-lockctl/src/main.vala') + common_base,
    vala_args: ['--pkg=gio-2.0', '--pkg=glib-2.0', '--pkg=json-glib-1.0'],
    c_args: lumen_datadir_c_args,
    dependencies: [glib_dep, gio_dep, json_dep, m_dep],
    install: true,
  )

  # Linux: always /etc/pam.d, never under the install prefix. FreeBSD: ports
  # convention, <prefix>/etc/pam.d (/usr/local/etc/pam.d), which OpenPAM
  # searches after /etc/pam.d.
  pam_base = get_option('pam_base')
  if pam_base == 'auto'
    if is_freebsd
      pam_base = 'system'
    else
      pam_base = fs.exists('/etc/pam.d/system-auth') ? 'system-auth' : 'common'
    endif
  endif
  pam_conf = configuration_data()
  if pam_base == 'system'
    # FreeBSD/OpenPAM: /etc/pam.d/system holds both stacks.
    pam_conf.set('PAM_AUTH',    'system')
    pam_conf.set('PAM_ACCOUNT', 'system')
  else
    pam_conf.set('PAM_AUTH',    pam_base == 'common' ? 'common-auth'    : 'system-auth')
    pam_conf.set('PAM_ACCOUNT', pam_base == 'common' ? 'common-account' : 'system-auth')
  endif
  # .pam suffix: the build dir already has a lumen-lockscreen executable.
  pam_file = configure_file(
    input: 'lumen-lockscreen/data/pam.d/lumen-lockscreen.in',
    output: 'lumen-lockscreen.pam',
    configuration: pam_conf,
  )
  pam_dir = is_freebsd ? get_option('prefix') / get_option('sysconfdir') / 'pam.d' : '/etc/pam.d'
  install_data(pam_file, rename: 'lumen-lockscreen', install_dir: pam_dir)

  message('lumen-lockscreen: enabled')
else
  message('lumen-lockscreen: disabled (need gtk4-session-lock-0 + pam)')
endif

# --- session / XDG portal glue ---
# The target binds graphical-session.target so xdg-desktop-portal can start
# under Wayfire. systemd user units always go in <prefix>/lib, never lib64.
# FreeBSD has no systemd: dbus-daemon activates the portal directly.
if not is_freebsd
  install_data(
    'data/systemd/lumenshell-session.target',
    install_dir: get_option('prefix') / 'lib' / 'systemd' / 'user',
  )
endif
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
# @SYSCONFDIR@: pre-start hooks live in /etc on Linux and in the ports
# prefix's etc (/usr/local/etc) on FreeBSD, per hier(7).
launcher_conf = configuration_data()
launcher_conf.set('SYSCONFDIR', is_freebsd
  ? get_option('prefix') / get_option('sysconfdir') : '/etc')
configure_file(
  input: 'lumen-lockscreen/data/bin/start-lumenshell.in',
  output: 'start-lumenshell',
  configuration: launcher_conf,
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)
# Path is referenced by the snippet's own header; keep them in sync.
# Wayfire discards autostart output: route it to the journal (systemd-cat) on
# Linux, to syslogd via daemon(8) on FreeBSD (data/freebsd/syslog.d).
autostart_conf = configuration_data()
autostart_conf.set('LOGGER', is_freebsd ? 'daemon -T' : 'systemd-cat -t')
autostart_conf.set('LOG_HINT', is_freebsd
  ? 'syslogd (/var/log/lumenshell.log with data/freebsd/syslog.d, else /var/log/messages)'
  : 'the journal (journalctl --user -t lumen-panel)')
autostart_conf.set('DATADIR', get_option('prefix') / get_option('datadir'))
configure_file(
  input: 'lumen-lockscreen/data/wayfire/lumenshell.ini.d/autostart.ini.in',
  output: 'autostart.ini',
  configuration: autostart_conf,
  install_dir: get_option('datadir') / 'lumenshell' / 'wayfire.ini.d',
)

# FreeBSD system integration samples (devfs.rules, syslog.d, newsyslog.conf.d,
# wpa_supplicant.conf), installed for scripts/freebsd/setup-system.sh and
# for admins who prefer to merge them by hand.
if is_freebsd
  install_subdir('data/freebsd',
    install_dir: get_option('datadir') / 'lumenshell',
    strip_directory: false,
  )
  install_data('scripts/freebsd/setup-system.sh',
    install_dir: get_option('datadir') / 'lumenshell' / 'freebsd',
    install_mode: 'rwxr-xr-x',
  )
endif

# --- wayfire-plugins/* ---
# They build unchanged on FreeBSD against x11-wm/wayfire + graphics/wlroots019
# (or scripts/freebsd/build-extern.sh wayfire when ports lag behind 0.10).
# C++ is only enabled when a plugin is, so the Vala tree builds without it.
if get_option('with_desktop_peek') \
   or get_option('with_curtain_peek') \
   or get_option('with_slide_peek') \
   or get_option('with_zoom_peek') \
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

if get_option('with_zoom_peek')
  subdir('wayfire-plugins/zoom-peek')
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
devenv.set('GSK_RENDERER', 'gl')
meson.add_devenv(devenv)
