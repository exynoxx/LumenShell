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
Bottom panel
<img width="1920" height="1080" alt="20251229_19h31m16s_grim" src="https://github.com/user-attachments/assets/79427174-5150-4ea8-8304-a39ef679c654" />
  
Kickoff
<img width="1920" height="1080" alt="20251229_19h31m35s_grim" src="https://github.com/user-attachments/assets/31268306-9153-4358-aa86-85810d480bc1" />

### License
GNU General Public License v3.0
