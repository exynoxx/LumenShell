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
m_dep           = cc.find_library('m')

# lumen-panel (GTK4 port) extends wlhooks's foreign-toplevel surface to take
# a GDK-owned wl_display. The legacy EGL/GLES2 rendering half of wlhooks and
# libdrawkit remain in tree (see their DEPRECATED.md) but are not built by
# default.
wlhooks_sub = subproject('wlhooks')
wlhooks_dep = wlhooks_sub.get_variable('wlhooks_dep')

vapi_dir = meson.project_source_root() / 'vapi'

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
  'lumen-osd/src/window_group.vala',
  'lumen-osd/src/utils.vala',
  'lumen-osd/src/theme.vala',
  'lumen-osd/src/pill.vala',
  'lumen-osd/src/selector.vala',
  'lumen-osd/src/picker.vala',
  'lumen-osd/src/presenter.vala',
  'lumen-osd/src/dbus.vala',
  'lumen-osd/src/state_watcher.vala',
  'lumen-osd/src/self_test.vala',
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

# --- lumen-panel (GTK4 + gtk4-layer-shell + GSK) ---
gtk4_wayland_dep = dependency('gtk4-wayland')
gnome = import('gnome')

panel_resources = gnome.compile_resources(
  'lumen-panel-resources',
  'lumen-panel/src/resources.gresource.xml',
  source_dir: 'lumen-panel/src',
  c_name: 'panel',
)

# UnixSocketAddress for the Wayfire peek IPC client lives in gio-unix-2.0.
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

# Desktop-peek-on-panel-click is opt-out: gate the peek IPC source, the
# gio-unix dep it needs, and the PANEL_PEEK Vala define behind one option so a
# standalone panel build has zero Wayfire coupling.
# Shared source module(s) reused across components (SESSION_GLUE §3). Scoped to
# what exists today; the lockscreen adds accounts.vala here later. Source-level
# reuse only — no shared .so until a third consumer appears.
lumen_common_sources = files(
  'lumen-common/logind.vala',
)

# Remembered display layouts (written by lumen-settings, read by the upcoming
# lumen-session daemon). Separate from lumen_common_sources so consumers don't
# drag in logind/gio-unix just to read profiles.
display_profiles_source = files(
  'lumen-common/display_profiles.vala',
)

# AccountsService client (avatar/real-name read + last-session write). Shared by
# lumen-lockscreen (reads) and lumen-session (writes). Kept separate from
# lumen_common_sources for the same reason as display_profiles_source: a
# consumer pulls in only what it needs.
accounts_source = files(
  'lumen-common/accounts.vala',
)

# Shared GLib.Subprocess spawn helper (run_capture / spawn_detached). Used by
# lumen-panel and lumen-osdctl. Kept separate so consumers pull only what they need.
proc_source = files(
  'lumen-common/proc.vala',
)

# Shared DBus CLI helper (name_has_owner "is the daemon running?" check). Used by
# lumen-osdctl and lumen-lockctl.
dbus_cli_source = files(
  'lumen-common/dbus_cli.vala',
)

# Tray-applet catalog (id + label, default order). Single source of truth for
# the set of known tray applets, compiled into BOTH lumen-panel (default order +
# known-id set) and lumen-settings (reorder list rows). Separate file for the
# same reason as display_profiles_source: a consumer pulls in only what it needs.
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
  'lumen-panel/src/ini.vala',
  'lumen-panel/src/panel_config.vala',
  'lumen-panel/src/utils.vala',
  'lumen-panel/src/wl/toplevels.vala',
  'lumen-panel/src/widgets/tray_button.vala',
  'lumen-panel/src/widgets/tray.vala',
  'lumen-panel/src/widgets/tray_registry.vala',
  'lumen-panel/src/widgets/signal_bars.vala',
  'lumen-panel/src/widgets/progress_bar.vala',
  'lumen-panel/src/widgets/text_field.vala',
  'lumen-panel/src/widgets/chip.vala',
  'lumen-panel/src/widgets/segmented_control.vala',
  'lumen-panel/src/components/clock/clock.vala',
  'lumen-panel/src/components/system/logind_service.vala',
  'lumen-panel/src/components/exit/exit.vala',
  'lumen-panel/src/components/exit/exitpage.vala',
  'lumen-panel/src/components/app.vala',
  'lumen-panel/src/components/apppopup.vala',
  'lumen-panel/src/components/panel.vala',
  'lumen-panel/src/components/sni/sni_watcher.vala',
  'lumen-panel/src/components/sni/sni_item.vala',
  'lumen-panel/src/components/sni/sni_menu.vala',
  'lumen-panel/src/components/sni/systray.vala',
  'lumen-panel/src/components/battery/battery.vala',
  'lumen-panel/src/components/battery/battery_service.vala',
  'lumen-panel/src/components/battery/batterypage.vala',
  'lumen-panel/src/components/battery/power_profile.vala',
  'lumen-panel/src/components/battery/power_profile_service.vala',
  'lumen-panel/src/components/sound/pactl.vala',
  'lumen-panel/src/components/sound/sound_service.vala',
  'lumen-panel/src/components/sound/sound.vala',
  'lumen-panel/src/components/sound/soundpage.vala',
  'lumen-panel/src/components/wifi/nmcli.vala',
  'lumen-panel/src/components/wifi/wifi_service.vala',
  'lumen-panel/src/components/wifi/wifi.vala',
  'lumen-panel/src/components/wifi/wifirow.vala',
  'lumen-panel/src/components/wifi/wifipage.vala',
  'lumen-panel/src/components/bluetooth/btctl.vala',
  'lumen-panel/src/components/bluetooth/bluetooth_service.vala',
  'lumen-panel/src/components/bluetooth/bluetooth.vala',
  'lumen-panel/src/components/bluetooth/bluetoothrow.vala',
  'lumen-panel/src/components/bluetooth/bluetoothpage.vala',
)

executable('lumen-panel',
  panel_sources + panel_peek_sources + panel_resources + lumen_common_sources + proc_source + tray_catalog_source,
  vala_args: panel_vala_args,
  dependencies: panel_deps,
  link_args: ['-Wl,--no-as-needed'],
  install: true,
)

install_data(
  'default-theme.json',
  install_dir: get_option('datadir') / 'lumen-panel',
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
  'lumen-notifications/src/self_test.vala',
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

# --- lumen-desktop ---
# Independent dep set: no drawkit, no wlhooks, no GLES.
# Reuses gtk4_dep and gtk4_layer_shell_dep from lumen-osd block above.
# UnixSocketAddress for the Wayfire IPC client lives in gio-unix-2.0.
gio_unix_dep = dependency('gio-unix-2.0')
desktop_deps = [
  # Same link-order rule as lumen-panel: gtk4-layer-shell must come before
  # gtk4/wayland-client/wlhooks for layer-shell init to actually take effect.
  gtk4_layer_shell_dep,
  gtk4_dep,
  gtk4_wayland_dep,
  wayland_dep,
  wlhooks_dep,
  glib_dep,
  gio_dep,
  gee_dep,
  gio_unix_dep,
  m_dep,
]

desktop_vala_args = [
  '--vapidir=' + vapi_dir,
  '--pkg=gtk4',
  '--pkg=gtk4-layer-shell-0',
  '--pkg=gtk4-wayland',
  '--pkg=gee-0.8',
  '--pkg=glib-2.0',
  '--pkg=gio-2.0',
  '--pkg=gio-unix-2.0',
  '--pkg=libwlhooks',
]

desktop_sources = files(
  'lumen-common/wayfire_ipc.vala',
  'lumen-desktop/src/main.vala',
  'lumen-desktop/src/window.vala',
  'lumen-desktop/src/appentry.vala',
  'lumen-desktop/src/searchdb.vala',
  'lumen-desktop/src/curtain_ipc.vala',
  'lumen-desktop/src/wl/toplevels.vala',
  'lumen-desktop/src/components/apptile.vala',
  'lumen-desktop/src/components/pagedgrid.vala',
  'lumen-desktop/src/components/searchresults.vala',
  'lumen-desktop/src/components/pagedots.vala',
  'lumen-desktop/src/utils/aliasarray.vala',
)

executable('lumen-desktop',
  desktop_sources,
  vala_args: desktop_vala_args,
  dependencies: desktop_deps,
  link_args: ['-Wl,--no-as-needed'],
  install: true,
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
  'lumen-osdctl/src/display.vala',
  'lumen-osdctl/src/dbus_proxy.vala',
)

executable('lumen-osdctl',
  osdctl_sources + proc_source + dbus_cli_source,
  vala_args: osdctl_vala_args,
  dependencies: osdctl_deps,
  install: true,
)

# --- lumen-session (headless display-profile restore daemon; no GTK) ---
# Owns its own Wayland connection and re-applies remembered monitor layouts on
# hotplug. Reuses the shared display-profile store (display_profiles_source,
# defined above) — the same format lumen-settings writes on "Keep".
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
  session_sources + display_profiles_source + accounts_source,
  vala_args: session_vala_args,
  dependencies: session_deps,
  install: true,
)

# --- lumen-settings (drop-in fragment) ---
subdir('lumen-settings')

# --- lumen-lockscreen + lumen-lockctl (ext-session-lock-v1 lock screen) ---
# Gated behind `with_lockscreen` (auto). The lock SURFACE is created by
# gtk4-session-lock (sister lib to gtk4-layer-shell — see vapi/gtk4-session-lock-0.vapi);
# auth is PAM via the in-tree pam_auth.c helper. Idle auto-lock is delegated to
# an external idle daemon (swayidle → `lumen-lockctl lock`), so wlhooks is
# untouched. When either dep is missing and the feature is 'auto', the whole
# component is silently skipped and the rest of the tree still builds.
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
    # gtk4-wayland + wayland + wlhooks: idle auto-lock binds ext-idle-notify-v1
    # on GTK's wl_display (IdleWatcher), same link set as lumen-panel.
    gtk4_wayland_dep,
    wayland_dep,
    wlhooks_dep,
    glib_dep,
    gio_dep,
    # logind.vala (lumen_common) uses UnixFDList for the sleep delay-inhibitor.
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
    '--pkg=lockscreen_crash',
  ]

  # Bake the resolved install datadir into the binary so the packaged default
  # theme is found regardless of prefix (e.g. /usr vs /usr/local). Utils reads
  # LUMEN_DATADIR; see lumen-lockscreen/src/utils.vala.
  lockscreen_c_args = [
    '-DLUMEN_DATADIR="' + (get_option('prefix') / get_option('datadir')) + '"',
  ]

  lockscreen_sources = files(
    'lumen-common/wayfire_ipc.vala',
    'lumen-lockscreen/src/main.vala',
    'lumen-lockscreen/src/diaglog.vala',
    'lumen-lockscreen/src/crash_handler.c',
    'lumen-lockscreen/src/manager.vala',
    'lumen-lockscreen/src/window.vala',
    'lumen-lockscreen/src/theme.vala',
    'lumen-lockscreen/src/utils.vala',
    'lumen-lockscreen/src/dbus.vala',
    'lumen-lockscreen/src/auth.vala',
    'lumen-lockscreen/src/idle.vala',
    'lumen-lockscreen/src/self_test.vala',
    'lumen-lockscreen/src/widgets/background.vala',
    'lumen-lockscreen/src/widgets/blurred_wallpaper.vala',
    'lumen-lockscreen/src/widgets/clock.vala',
    'lumen-lockscreen/src/widgets/avatar.vala',
    'lumen-lockscreen/src/widgets/password.vala',
    'lumen-lockscreen/src/widgets/power_menu.vala',
    'lumen-lockscreen/src/pam_auth.c',
  )

  executable('lumen-lockscreen',
    lockscreen_sources + lockscreen_resources + lumen_common_sources + accounts_source,
    vala_args: lockscreen_vala_args,
    c_args: lockscreen_c_args,
    dependencies: lockscreen_deps,
    include_directories: include_directories('lumen-lockscreen/src'),
    # -rdynamic exports the dynamic symbol table so backtrace_symbols_fd() in
    # crash_handler.c prints function names, not bare addresses.
    link_args: ['-Wl,--no-as-needed', '-rdynamic'],
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

  install_data(
    'lumen-lockscreen/default-lockscreen-theme.json',
    install_dir: get_option('datadir') / 'lumen-lockscreen',
  )

  # PAM service file — see SESSION_GLUE.md §2. Always /etc/pam.d (not prefixed).
  install_data(
    'lumen-lockscreen/data/pam.d/lumen-lockscreen',
    install_dir: '/etc/pam.d',
  )

  message('lumen-lockscreen: enabled')
else
  message('lumen-lockscreen: disabled (need gtk4-session-lock-0 + pam)')
endif

# --- session / XDG portal glue ---
# lumenshell-session.target binds graphical-session.target so
# xdg-desktop-portal can start under Wayfire; the *-portals.conf routes portal
# backends (Settings->gtk, ScreenCast/Screenshot->wlr). See nautilus-portal-bug.md.
# systemd user units are arch-independent — always /usr/lib/systemd/user.
install_data(
  'data/systemd/lumenshell-session.target',
  install_dir: get_option('prefix') / 'lib' / 'systemd' / 'user',
)
install_data(
  'data/xdg-desktop-portal/lumenshell-portals.conf',
  install_dir: get_option('datadir') / 'xdg-desktop-portal',
)

# Display-manager session glue. These files live under lumen-lockscreen/data/
# (where they were first drafted) but are session-level config, owned and
# installed here so a system install is greeter-ready:
#   * wayland-sessions/lumenshell.desktop — the session a Wayland-aware login
#     manager (GDM/SDDM/greetd/…) lists; its Exec= runs start-lumenshell.
#   * start-lumenshell — the session launcher (sets XDG_*; execs wayfire).
# The Wayfire [autostart] block lives directly in the user's ~/.config/wayfire.ini.
install_data(
  'lumen-lockscreen/data/wayland-sessions/lumenshell.desktop',
  install_dir: get_option('datadir') / 'wayland-sessions',
)
install_data(
  'lumen-lockscreen/data/bin/start-lumenshell',
  install_dir: get_option('bindir'),
  install_mode: 'rwxr-xr-x',
)

# --- wayfire-plugins/* (C++ Wayfire plugins) ---
# All Wayfire plugins live under wayfire-plugins/ and are standalone
# C++ shared modules (no link with the rest of the tree). Each is gated
# so users without Wayfire dev headers can disable any of them.
if get_option('with_desktop_peek') \
   or get_option('with_curtain_peek') \
   or get_option('with_slide_peek') \
   or get_option('with_panel_push') \
   or get_option('with_startup_zoom')
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

# --- dev environment (replaces the old hand-written env.sh) -----------------
# `meson devenv -C build` (or `meson devenv -C build ./lumen-panel`) runs the
# uninstalled build-tree binaries with these set, so resource/theme lookups
# resolve into the source tree instead of /usr/share. meson devenv already puts
# the built executables on PATH; these vars are the LUMEN_* overrides the
# binaries read (see lumen-panel/src/utils.vala and each theme.vala). The
# GSK_RENDERER pin mirrors start-lumenshell so dev runs match the real session.
devenv = environment()
devenv.set('LUMEN_RES_DIR', meson.project_source_root() / 'lumen-panel' / 'src' / 'res' + '/')
devenv.set('LUMEN_THEME_FILE', meson.project_source_root() / 'default-theme.json')
devenv.set('LUMEN_OSD_THEME_FILE', meson.project_source_root() / 'lumen-osd' / 'default-theme.json')
devenv.set('LUMEN_NOTIFICATIONS_THEME_FILE', meson.project_source_root() / 'lumen-notifications' / 'default-notifications-theme.json')
devenv.set('LUMEN_LOCKSCREEN_THEME_FILE', meson.project_source_root() / 'lumen-lockscreen' / 'default-lockscreen-theme.json')
devenv.set('GSK_RENDERER', 'ngl')
meson.add_devenv(devenv)
