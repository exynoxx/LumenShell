# LumenShell — Agent Context

Wayland desktop shell for Wayfire. Five GTK4 + `gtk4-layer-shell` Vala binaries built from one Meson tree at `/home/nicholas/Dokumenter/git/LumenShell/meson.build`. Build: `meson setup build && ninja -C build` (only warnings expected).

```
lumen-panel  ──spawns──▶  kickoff (Kickoff/)
     │
     │ wlhooks (foreign-toplevel + xdg-activation on GDK's wl_display)
     ▼
 running windows (any Wayland client)

 host keys / sysfs ──▶ lumen-osdctl ──DBus──▶ lumen-osd
                                       org.lumenshell.OSD1

 any app ──DBus──▶ lumen-notifications
                  org.freedesktop.Notifications
```

All five are independent processes. No IPC between panel/kickoff/osd/notifications beyond DBus and process spawn.

## Repo-wide invariants

- Build order in `meson.build`: `gtk4_layer_shell_dep` MUST precede `gtk4_dep` / `wayland_dep` in panel link line — otherwise `gtk_layer_init_for_window` silently no-ops. See https://github.com/wmww/gtk4-layer-shell/blob/main/linking.md.
- `wlhooks` legacy EGL/GLES paths exist on disk (`junkyard/libdrawkit/`, `wlhooks/DEPRECATED.md`) but are not reached by the GTK4 port. Do not modify existing wlhooks function signatures — additive only.
- Vala `Object` is ambiguous when `using Json;`: always spell `GLib.Object`.
- For `Gtk.EventControllerKey` on a window, `((Gtk.Widget) win).add_controller(...)` to disambiguate from `ShortcutManager.add_controller`.
- SVG `stroke="currentColor"` is NOT honored under GTK4 CSS unless loaded as a symbolic icon. Hard-code `stroke="#ffffff"` instead (precedent in `lumen-panel/src/res/sound-{max,mute}.svg`).
- `env.sh` populates dev-time `LUMEN_*` env vars; sourcing it lets `./build/<bin>` find theme/resource files without installing.

---

## lumen-panel

GTK4 + layer-shell bottom-of-screen panel. Left half: app entries (launcher + per-app-id buttons for running windows). Right half: floating rounded tray (WiFi, Battery, Sound, Clock, Exit) that expands upward to show a paged content area. right half called "tray area"

### Env vars (all read in `utils.vala`)

| Var | Default |
|---|---|
| `LUMEN_THEME_FILE` | `/usr/share/lumen-panel/default-theme.json` |
| `LUMEN_KICKOFF_BIN` | `kickoff` (PATH) |
| `LUMEN_RES_DIR`    | `/usr/share/lumen-panel/res/` |

### Files

- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/main.vala` — `Adw.Application`; layer-shell init; ESC handler (CAPTURE phase so child entries can't swallow it); `update_input_region()` clips the input region to the 60 px bottom strip + tray bbox when expanded. Tray auto-collapse uses `notify["contains-pointer"]` on the **window** (not the tray) with a 120 ms debounce, because the window only grows by adding input region — a pointer inside before expansion stays inside throughout. Recomputes input region on `default-height`, `map`, and revealer property changes.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/panel.vala` — `AppBar`. Loads pinned apps from `~/.config/lumen-panel/pinned-apps.txt`. Indexes entries in `entries_by_app_id` and `entries_by_window` (O(1) lookup on window close). Launcher entry has `app_id = "--"`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/app.vala` — `AppEntry`. Click semantics: launcher spawns `LUMEN_KICKOFF_BIN`; entry with windows cycles `ToplevelStore.activate` through `window_ids`; pinned entry with no windows runs `launch_cmd` (parsed from `.desktop` Exec, `%U/%u/%F/%f/%i/%c/%k` stripped). `is_active()` checks if any window owns the focused toplevel. Active-window underline (5 px) drawn in `snapshot()` with hard-coded RGBA — `@app_active_underline` doesn't resolve in code paths.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/apppopup.vala` — `AppPopupMenu` (right-click, non-launcher only). Pin/Unpin / New window (dimmed if `launch_cmd == ""`) / Close windows (dimmed if no windows). `set_position(TOP)`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/widgets/tray.vala` — `TrayBar`. Layout `[icon_row, revealer]` inside vertical box with `valign = END` — revealer expands and pushes icon_row up, matching the original DrawKit behavior where icons sit at the top of the expanded rect. `overflow = HIDDEN` in code so slide animations don't bleed past the rounded silhouette. Page transitions: `SLIDE_LEFT_RIGHT`, 240 ms. Reveal: `SLIDE_DOWN`, 280 ms. Active icon gets `.active` CSS class.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/widgets/tray_button.vala` — `Gtk.Button` subclass for tray icons.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/widgets/signal_bars.vala` — 4-bar WiFi snapshot widget.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/widgets/progress_bar.vala` — `LumenProgressBar` snapshot widget (battery page).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/widgets/text_field.vala` — `LumenTextField`; wraps `Gtk.Text` in a custom container with focus halo (WiFi password input).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/widgets/chip.vala` — `LumenChip` rounded badge.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/wl/toplevels.vala` — `ToplevelStore` singleton. Calls `WLHooks.init_toplevel_with_display(gdk_wl_display)` once, after `Gdk.Display` is available (inside `activate`). Uses wlhooks symbols: `register_on_window_{new,rm,focus}`, `toplevel_{activate,close,minimize}_by_id`. `on_focus` clears `activated` on all siblings.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/theme.vala` — Loads JSON via `LUMEN_THEME_FILE`, prepends `@define-color` block to embedded `style.css`, installs `CssProvider` on default `Gdk.Display`. `seed_defaults()` hardcodes fallback palette.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/utils.vala` — Desktop file lookup (exact, then case-insensitive scan of XDG dirs), icon theme search (user `~/.icons`, `XDG_DATA_DIRS/icons`, `/usr/share/pixmaps`), `sanitize_exec()` (strips `%U %u %F %f %i %c %k`).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/ini.vala` — `get_key_value`, `read_lines`, `write_lines` for pinned-apps persistence.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/style.css` — Single CSS source compiled into the binary via GResource at `/dev/lumen/panel/style.css` (see `resources.gresource.xml`). Classes: `.lumen-panel`, `.tray-bar`, `.tray-icons`, `.tray-pages`, `.tray-icon`, `.app-entry`, `.clock`, states `.active` / `.launching` / `.hover`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/battery/` — `battery.vala` (tray icon), `battery_service.vala` (sysfs poll, pre-warms in ctor), `batterypage.vala` (fully custom-drawn — no `Gtk.LevelBar` — single widget with Pango-rendered title/pct/status/progress/2x2 stat grid).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/wifi/` — `wifi.vala`, `wifi_service.vala` (nmcli background scan, pre-warmed), `nmcli.vala` (shells out), `wifirow.vala` (custom snapshot row), `wifipage.vala` (custom-drawn page using `LumenChip` / `LumenTextField` / `LumenButton`).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/sound/` — `sound.vala`, `sound_service.vala` (pactl poll at 1.5 s, pre-warmed), `pactl.vala`, `soundpage.vala` (**still uses `Gtk.Scale` + `Gtk.ListBox`** — not yet converted to custom widgets; visual mismatch acceptable for now).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-panel/src/components/clock/clock.vala`, `exit/exit.vala` — leaf tray icons (no page).

### Quirks

- `Gtk.EventControllerMotion.leave` on TrayBar fires during the reveal animation as layout shifts under the cursor → collapses immediately on click. Use `notify["contains-pointer"]` on the **window** instead.
- `Pango.attr_size_new(...)` doesn't exist in the vapi; use `Pango.AttrSize.new_absolute(size_pt * Pango.SCALE)`.
- `Gtk.Widget.size_allocate(Allocation, baseline)` is bound as `size_allocate(int width, int height, int baseline)` in Vala. To offset a child: `child.allocate(w, h, baseline, new Gsk.Transform().translate({x, y}))`.
- **Nested-wayfire dev caveat:** if Wayfire (and thus lumen-panel) is launched as a window inside an existing desktop session, mouse events break the moment that host window is resized — and the user will almost certainly resize it. The input region computed by `update_input_region()` is keyed to the output size at map time and doesn't track host-window resizes. Symptoms: clicks land outside the visible panel, or stop landing on the tray. Restart lumen-panel after any resize, or test on a real Wayfire session.

### Plays with

- Spawns Kickoff (`Utils.KICKOFF_BIN`) on launcher click; no further communication.
- Reads window list via wlhooks subproject on the same `wl_display` GTK owns.
- Does NOT talk to lumen-osd or lumen-notifications.

---

## Kickoff

Full-screen overlay app launcher. Spawned by lumen-panel on launcher click.

### Files

- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/main.vala` — `Gtk.Application` entry; `activate` → `KickoffWindow`.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/window.vala` — `KickoffWindow`. Layer-shell OVERLAY, `exclusive_zone = -1` so it covers lumen-panel, `KeyboardMode.EXCLUSIVE`. Inline `KICKOFF_CSS` (no GResource): `.kickoff-root`, `.search-row`, `.kickoff-search`, `.app-tile`, `.page-dots`, `.page-dot.active`. CSS provider must be installed once-per-process (`css_installed` static flag) since repeated windows would stack providers. Search entry locked to fixed 320 px width so it doesn't shift the centered row as the user types. Keys: ESC closes; Left/Right page-nav (only when `!search_db.active`); Alt+1/2/3 launches result 0/1/2; Ctrl+BackSpace clears query; digits otherwise fall through to the entry (so queries like "qt6ct" work). `on_search_activate` re-syncs the query before launching because `Gtk.SearchEntry.search_changed` debounces ~100 ms.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/appentry.vala` — Wraps `GLib.AppInfo`; `short_name` = first 20 chars + ellipsis.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/searchdb.vala` — Two-pass match: prefix on lowercase name, then fuzzy regex `.*c1.*c2.*...`. Exposes `active`, `filtered`, `size`.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/components/pagedgrid.vala` — 6×4 paginated grid. `PAGE_MARGIN_X=200`, `PAGE_MARGIN_Y=130`. Slide: ease-out-expo, 700 ms. Initial zoom-in: 10× → 1× around screen center on `map`, ease-out-expo, 700 ms. Allocation uses `Gsk.Transform.translate()` so pointer picking lands on the visible tile. Tick callback does `queue_allocate`, not `queue_draw`, because the slide moves via allocation.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/components/searchresults.vala` — Fixed 6×4 result grid; opacity 0 + insensitive until first `update()`.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/components/apptile.vala` — Single tile (96 px icon, 11 pt label). `bind(entry)` short-circuits when entry unchanged (icon-theme lookup is expensive).
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/components/pagedots.vala` — Dot indicator row.
- `/home/nicholas/Dokumenter/git/LumenShell/Kickoff/src/utils/aliasarray.vala` — Index-aliasing array used by `SearchDb` so results can be iterated stably.

### Quirks

- `body_stack` (grid ↔ results) uses `StackTransitionType.NONE` — a crossfade leaves the grid faintly visible behind results and reads as a layout glitch.
- `.kickoff-search`: the default `Gtk.SearchEntry` chrome (inner `> text`, `> image`, focus ring) each render with their own rounding; if not overridden they stack as multiple anti-aliased edges → "blurry corner". Override with `border: none; outline: none; box-shadow: none` on `.kickoff-search`, `:focus`, `:focus-within`, and on `> text` / `> image`.

### Plays with

- Spawned by lumen-panel. No DBus or IPC back. `AppEntry.launch()` exits the process via `launched` signal → `close()`.

---

## lumen-osd

DBus-driven OSD pill (volume, brightness, mic, caps-lock, custom). Daemonized; window is realized hidden, shown on each DBus call, auto-hidden after timeout.

### Env vars

| Var | Default |
|---|---|
| `LUMEN_OSD_THEME_FILE` | `/usr/share/lumen-osd/default-theme.json` |

### DBus surface

- Bus name: `org.lumenshell.OSD`
- Object path: `/org/lumenshell/OSD`
- Interface: `org.lumenshell.OSD1` (note the trailing `1`)
- Methods: `show(kind: s, value: d, text: s, opts: a{sv})`, `hide()`
- `kind` values: `volume`, `mic`, `brightness`, `kbd-brightness`, `caps-lock`, `custom`
- `opts` keys: `muted` (bool), `timeout-ms` (int, default `Theme.timeout_ms` = 1500), `icon` (string override)

### Files

- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/main.vala` — `OsdApp` (`Gtk.Application`). Window is `present()`-ed then `set_visible(false)` so it's realized but hidden. `hold()` keeps app alive with no visible window. `--test` activates `OsdSelfTest`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/dbus.vala` — `OsdService`. Implements `show`/`hide`. Variant type-checks `opts` strictly with fallbacks. Hide timer armed via `Timeout.add`, cancelled/re-armed each call.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/window.vala` — `OsdWindow` (`Gtk.Window`). Layer-shell namespace `lumen-osd`, layer OVERLAY, `KeyboardMode.NONE`. Position enum: `top-center` / `bottom-right` / `bottom-left` / `bottom-center` (default). All anchors reset before applying position.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/pill.vala` — `Pill` and `ProgressTrack`. Rounded background drawn via `Gsk.RoundedRect`. **`corner_radius = -1` means pill (height/2)**. Fill cap has minimum width = track height so rounded cap is visible at tiny fractions. Icon 22 px; track min 80 / natural 200 px wide, 6 px tall.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/presenter.vala` — Maps (kind, value, opts) → chip vs slider + icon. Volume/mic thresholds 0.34 / 0.67. `caps-lock` is always chip; `custom` is chip iff `text != ""` and `value <= 0`. Default slider text `"%d%%"`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/state_watcher.vala` — Polls sysfs every 200 ms (sysfs writes don't reliably emit inotify). Discovers `/sys/class/leds/*::kbd_backlight/brightness`, `/sys/class/backlight/*/brightness`, `/sys/class/leds/*::capslock`. First tick is a prime — only thereafter does change detection fire. Calls `OsdService.show()` internally on change.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/theme.vala` — Static class. JSON keys `osd.position`, `osd.background`, `osd.text`, `osd.progress.{track,fill}`, `osd.margin`, `osd.width`, `osd.height`, `osd.corner-radius`, `osd.timeout-ms`, `osd.padding-{x,y}`, `osd.content-spacing`. Hex parser supports 3/4/6/8 char forms.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/utils.vala` — Just exposes `THEME_FILE` from env.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osd/src/self_test.vala` — `--test`: cycles 18 sample frames (volume×4, mic×4, brightness×3, kbd-light×3, caps-lock×2, custom×2) at 900 ms each, logs `[lumen-osd] --test [NN/18] ...` to stderr, quits.

### Plays with

- Talked to by `lumen-osdctl`. Self-watches sysfs state independently of any controller.

---

## lumen-osdctl

CLI that signals lumen-osd. Does NOT spawn the daemon — if it's not running, prints `lumen-osd daemon is not running` and exits.

### CLI

- `--output-volume raise|lower|mute-toggle [--step N]` (default step 5)
- `--input-volume raise|lower|mute-toggle [--step N]`
- `--brightness raise|lower [--step N]`
- `--kbd-brightness raise|lower [--step N]`
- `--caps-lock`
- `--custom <text> [--value 0..1] [--icon NAME]`

### Files

- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osdctl/src/main.vala` — Parses args, checks `NameHasOwner("org.lumenshell.OSD")`, calls `show()` with 1500 ms timeout.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osdctl/src/backends.vala` — Shells out to `pactl` (uses `env LC_ALL=C` so regex sees English; parses `\d+%` and `contains("yes")` on lowercased mute output), `brightnessctl -m` (machine-readable: `name,class,current,pct,max`; kbd device arg `'*::kbd_backlight'`), and reads `/sys/class/leds/*::capslock/brightness` for caps-lock. Values clamped to `[0, 1]`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-osdctl/src/dbus_proxy.vala` — Interface definition for `org.lumenshell.OSD1`.

### Plays with

- DBus client to lumen-osd. No other interactions.

---

## lumen-notifications

`org.freedesktop.Notifications` server. Top-right banner stack, click-to-dismiss, slide/fade animations, "Clear all" when threshold exceeded.

### Env vars

| Var | Default |
|---|---|
| `LUMEN_NOTIFICATIONS_THEME_FILE` | `/usr/share/lumen-notifications/default-notifications-theme.json` |

### DBus surface

- Bus name: `org.freedesktop.Notifications` (overridable via `--bus-name`)
- Object path: `/org/freedesktop/Notifications` (overridable via `--bus-path`)
- Methods: `Notify`, `CloseNotification`, `GetCapabilities` → `["body", "body-markup", "actions", "icon-static"]`, `GetServerInformation` → (`lumen-notifications`, `LumenShell`, `0.1`, `1.2`).
- Signals: `NotificationClosed(id, reason)`, `ActionInvoked(id, key)`.
- Hints read: `urgency` (byte 0..2), `image-path` / `image_path`.

### Files

- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/main.vala` — `NotifApp` (NON_UNIQUE; `activated` flag guards single init). Owns the bus name. `--test` flag triggers `NotifSelfTest`. Quits if `GtkLayerShell.is_supported()` returns false.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/dbus_service.vala` — Bridges DBus to `NotificationManager`. `Notify` returns uint32 id.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/notification.vala` — Data holder. `Urgency` enum LOW/NORMAL/CRITICAL.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/notification_manager.vala` — Lifecycle. `expire_timeout == 0` → never expire, `< 0` → Theme default (5000 ms), `> 0` → use value. `replaces_id` updates in place when set and known. Close-reason constants `REASON_{EXPIRED,DISMISSED,CLOSED,UNDEFINED}`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/layer_window.vala` — Layer-shell window, namespace `lumen-notifications`, layer TOP, `KeyboardMode.NONE`, anchored TOP+RIGHT only so it sizes naturally and grows downward (compositor clips bottom).
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/stack.vala` — `BannerStack`. `by_id` map holds only **active** (non-leaving) banners — removed immediately on dismiss to prevent double-fire in cascades. `cascade_dismiss()` walks top-to-bottom firing `close_requested(id)` staggered by `Theme.cascade_ms` (80 ms). "Clear all" visible iff `active_count > clear_threshold`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/banner.vala` — `Banner` widget. Icon resolution order: `image_path` → `app_icon` → absolute path → `file://` URI → icon theme. Actions are `[key, label, key, label, ...]` pairs; `"default"` key is the whole-card click. Leave animation captures `full_natural_h` before shrinking for smooth collapse; opacity uses `ease_out_cubic`; slide offset `leave_progress * (Theme.width + Theme.slide_px * 2)`. Buttons disabled once leave starts. `DismissStyle` enum: `SLIDE_RIGHT` / `FADE`.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/theme.vala` — JSON keys: `dismiss.style` (string), color keys like `banner.background` (hex), int keys `banner.{radius,padding,spacing,width,gap,margin.top,margin.right}`, `action.radius`, `clear-all.radius`, `animation.{fade-out-ms,slide-px}`, `expire.default-ms`, `dismiss.cascade-ms`, `clear-all.threshold`. Hex parser: 3/6/8 digit.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/utils.vala` — `THEME_FILE` property.
- `/home/nicholas/Dokumenter/git/LumenShell/lumen-notifications/src/self_test.vala` — `--test` pushes a sample notification with actions.

### Plays with

- DBus server for any app. No interaction with panel/osd/kickoff.

---

## wlhooks (subproject)

`/home/nicholas/Dokumenter/git/LumenShell/wlhooks/` and `/home/nicholas/Dokumenter/git/LumenShell/vapi/libwlhooks.vapi`.

Used by lumen-panel only. Additive surface introduced for the GTK4 port — do NOT modify existing wlhooks function signatures. The additive entry points:

- `WLHooks.init_toplevel_with_display(Wl.Display)` — binds foreign-toplevel + xdg-activation on GTK's existing wl_display (no second connection). Sets `minimal_mode` internally.
- `WLHooks.destroy_toplevel()` — tears down only the toplevel/activation surface; does NOT call `wl_display_disconnect` (GDK owns the display).
- `seat_set_minimal_mode(bool)` in `wlhooks/protocols/seat.{c,h}` — suppresses pointer/keyboard attachment in the seat capability listener.

The legacy EGL/layer-shell/seat code paths still exist on disk but are gated by `if (!minimal_mode)` in `seat.c` and not reached when `init_toplevel_with_display` is the entry point.
