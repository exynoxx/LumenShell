### Work in progress!!

# Introduction
Lumen is an early-ChromeOS lookalike Wayland shell featuring Wayfire as compositor, **lumen-panel** and application launcher (Kickoff) for navigation. lumen-panel is built on GTK4 + `gtk4-layer-shell` + GSK; Kickoff and the OSD/notification surfaces share the same stack. All components are implemented in Vala.

### WLHooks
A small Wayland client library that exposes the foreign-toplevel /
xdg-activation surface lumen-panel needs (so the panel can list and
raise running windows). It binds these protocols on the wl_display
GTK already owns — no second connection. See `wlhooks/DEPRECATED.md`
for the legacy EGL/layer-shell/seat code paths that the GTK4 port no
longer reaches.

### lumen-panel environment

lumen-panel reads two environment variables at startup:

| Variable | Description | Default |
|---|---|---|
| `LUMEN_THEME_FILE` | Path to the theme JSON | `/usr/share/lumen-panel/default-theme.json` |
| `LUMEN_KICKOFF_BIN` | Path to the Kickoff binary | `kickoff` (on PATH) |

A helper script is provided to populate these for local development:

```bash
source env.sh
./build/lumen-panel
```

# Show case
<table align="center">
  <tr>
    <td colspan="2" align="center">
      <img src="docs/shots/shot-1779036345.png" width="700"><br>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/shots/shot-1779035985.png" width="340"><br>
      <sub>status strip</sub>
    </td>
    <td align="center">
      <img src="docs/shots/shot-1779036456.png" width="340"><br>
      <sub>osd</sub>
    </td>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <img src="docs/shots/f3.gif" width="700"><br>
    </td>
  </tr>
</table>

### License
GNU General Public License v3.0
