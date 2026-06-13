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
  'lumen-osd/src/utils.vala',
  'lumen-osd/src/theme.vala',
  'lumen-osd/src/pill.vala',
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

panel_peek_sources = []
if get_option('with_panel_peek')
  panel_vala_args += ['--define=PANEL_PEEK']
  panel_peek_sources = files('lumen-panel/src/peek_ipc.vala')
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
  panel_sources + panel_peek_sources + panel_resources + lumen_common_sources,
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
  osdctl_sources,
  vala_args: osdctl_vala_args,
  dependencies: osdctl_deps,
  install: true,
)

# --- lumen-settings (drop-in fragment) ---
subdir('lumen-settings')

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

# --- wayfire-plugins/* (C++ Wayfire plugins) ---
# All Wayfire plugins live under wayfire-plugins/ and are standalone
# C++ shared modules (no link with the rest of the tree). Each is gated
# so users without Wayfire dev headers can disable any of them.
if get_option('with_desktop_peek') \
   or get_option('with_curtain_peek') \
   or get_option('with_slide_peek') \
   or get_option('with_startup_zoom') \
   or get_option('with_default_focus')
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

if get_option('with_startup_zoom')
  subdir('wayfire-plugins/startup-zoom')
endif

if get_option('with_default_focus')
  subdir('wayfire-plugins/default-focus')
endif
