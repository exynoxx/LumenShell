project('wlhooks', 'c',
  version : '1.0'
)

fs = import('fs')

# --- Find dependencies using pkg-config ---
wayland_client_dep = dependency('wayland-client', required: true)
glib_dep           = dependency('glib-2.0', required: true)

wayland_scanner = find_program(
  dependency('wayland-scanner', native: true).get_variable('wayland_scanner'))
wl_protocols_dir = dependency('wayland-protocols').get_variable('pkgdatadir')

# wlr protocols are vendored: wlr-protocols isn't packaged everywhere.
protocol_xmls = [
  'protocols/xml/wlr-foreign-toplevel-management-unstable-v1.xml',
  'protocols/xml/wlr-output-management-unstable-v1.xml',
  wl_protocols_dir / 'staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml',
  wl_protocols_dir / 'staging/ext-idle-notify/ext-idle-notify-v1.xml',
  wl_protocols_dir / 'unstable/idle-inhibit/idle-inhibit-unstable-v1.xml',
]

protocol_headers = []
protocol_code = []
foreach xml : protocol_xmls
  name = fs.stem(xml)
  protocol_headers += custom_target(name + '-client-header',
    input: xml,
    output: name + '-client-protocol.h',
    command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'])
  protocol_code += custom_target(name + '-code',
    input: xml,
    output: name + '-protocol.c',
    command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'])
endforeach

# --- Source and header files ---
sources = [
  'main.c',
  'registry.c',
  'protocols/seat.c',
  'protocols/toplevel.c',
  'protocols/window_list.c',
  'protocols/wlr_toplevel.c',
  'protocols/ext_toplevel.c',
  'protocols/output.c',
  'protocols/output_management.c',
  'protocols/idle_notify.c',
  'protocols/idle_inhibit.c',
] + protocol_headers + protocol_code

wayland_unstable = static_library(
  'wlhooks',
  sources,
  dependencies: [wayland_client_dep, glib_dep],
  include_directories: include_directories('.')
)

# protocol_headers in sources: consumers include wlhooks.h, which pulls in a
# generated header, so they must be built first.
wlhooks_dep = declare_dependency(
  link_with: wayland_unstable,
  sources: protocol_headers,
  include_directories: include_directories('.'),
  dependencies: [wayland_client_dep, glib_dep],
)
