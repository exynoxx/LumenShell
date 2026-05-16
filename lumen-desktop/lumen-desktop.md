# Plan: lumen-desktop

## Context

LumenShell currently ships `Kickoff` — a full-screen overlay app launcher spawned by `lumen-panel` on launcher click. `lumen-desktop` is a sibling executable that takes Kickoff's visual layout (paginated app grid + search bar at top) and turns it into an **always-visible app drawer** on the `BACKGROUND` layer. It replaces the conventional "files on desktop" metaphor: normal app windows render on top of the tile grid naturally; closing them reveals the grid again. There is no overlay dim, no ESC-to-hide, no zoom-in intro — the drawer is part of the desktop, not a transient overlay.

Per user direction, this is a **fresh copy** of the Kickoff sources, not a shared meson target. Future changes to either Kickoff or lumen-desktop will need to be applied to both.

---

## Windowing

One layer-shell surface, `Gtk.Application` ID `dev.lumen.desktop`:

- Namespace `lumen-desktop`.
- Layer `BACKGROUND` — normal windows render on top automatically per compositor input semantics.
- Anchored on all four edges (covers full output).
- `exclusive_zone = 0` — does NOT consume zone (windows ignore it when sizing). Distinct from Kickoff's `-1` (which forces full-output coverage by ignoring others' exclusive zones).
- `KeyboardMode.NONE` — must never grab focus from foreground apps.

---

## Sources (fresh copy under `lumen-desktop/src/`)

Files copied from Kickoff and adapted:

- `lumen-desktop/src/main.vala` — entry point. `Gtk.Application` `dev.lumen.desktop`; `activate` → constructs `DesktopWindow` and `present()`s it once. No `hold()`-style daemon pattern (the window is always present).
- `lumen-desktop/src/window.vala` — `DesktopWindow extends Gtk.ApplicationWindow`. Adapted from `Kickoff/src/window.vala` with these changes:
  - Layer `BACKGROUND` (not `OVERLAY`).
  - `KeyboardMode.NONE` (not `EXCLUSIVE`).
  - `exclusive_zone = 0` (not `-1`).
  - **Remove** `close_request` interception and `hide_window()` lifecycle — the window is always present, not hidden between uses.
  - **Remove** ESC handler (no hide).
  - **Keep** the search bar at the top and the Alt+1/2/3 and Ctrl+Backspace shortcuts when search is active — but the key controller stays on the window with no CAPTURE-phase override; if focus isn't ours, keys don't reach us anyway.
  - **Remove** zoom-in intro (no `reset_intro()` call, no `ZOOM_FROM`, no `on_zoom_tick`) — intro animation replays on every map would be obnoxious for an always-visible surface.
  - Root CSS class `.lumen-desktop-root` with transparent background (compositor wallpaper shows through). Tile and search styling otherwise identical to Kickoff.
- `lumen-desktop/src/appentry.vala` — copy of `Kickoff/src/appentry.vala`.
- `lumen-desktop/src/searchdb.vala` — copy of `Kickoff/src/searchdb.vala`.
- `lumen-desktop/src/components/apptile.vala` — copy of `Kickoff/src/components/apptile.vala`.
- `lumen-desktop/src/components/pagedgrid.vala` — copy of `Kickoff/src/components/pagedgrid.vala`, with the zoom-in animation code stripped (constants `ZOOM_DURATION_S`, `ZOOM_FROM`, fields `zoom_factor` / `zoom_start_us` / `zoom_tick_id` / `zoom_started`, methods `reset_intro()` / `on_zoom_tick()`, and the snapshot-time transform block). Slide-pagination remains.
- `lumen-desktop/src/components/searchresults.vala` — copy of `Kickoff/src/components/searchresults.vala`.
- `lumen-desktop/src/components/pagedots.vala` — copy of `Kickoff/src/components/pagedots.vala`.
- `lumen-desktop/src/utils/aliasarray.vala` — copy of `Kickoff/src/utils/aliasarray.vala`.

---

## App launching behaviour

`AppEntry.launch()` in Kickoff exits the window via the `launched` signal connected to `hide_window()`. In `DesktopWindow`, connect `launched` to a **no-op** — the desktop never hides itself; the launched app appears as a normal window on top of the BACKGROUND layer.

After launch, also clear the search query and reset the grid to page 0 so the drawer doesn't leave a transient filter state behind (mirrors how Kickoff resets in `show_with_intro()`).

---

## CSS

Inline `DESKTOP_CSS` analogous to `KICKOFF_CSS` (`Kickoff/src/window.vala:3–79`). Key differences from Kickoff:

```css
window.lumen-desktop-root {
    background: transparent;
    color: white;
}
```

Tile (`.app-tile`), search row (`.search-row`), search entry (`.kickoff-search` → rename to `.desktop-search`), page-dots styling: same as Kickoff. Override the `.kickoff-search` chrome quirks (multiple stacked rounding edges; see AGENTS.md:100) by setting `border: none; outline: none; box-shadow: none` on the search class, `:focus`, `:focus-within`, `> text`, `> image`.

The static `css_installed` flag pattern from `Kickoff/src/window.vala:217–227` carries over (CssProvider attaches to the global Gdk.Display; install only once per process).

---

## meson.build changes

Append after the existing `kickoff` block:

```meson
# --- lumen-desktop ---
desktop_deps = kickoff_deps
desktop_vala_args = kickoff_vala_args

desktop_sources = files(
  'lumen-desktop/src/main.vala',
  'lumen-desktop/src/window.vala',
  'lumen-desktop/src/appentry.vala',
  'lumen-desktop/src/searchdb.vala',
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
  install: true,
)
```

---

## env.sh additions

None required — lumen-desktop has no theme JSON or external resource directory in this first cut (palette is inline CSS). If a theme JSON is added later, follow the lumen-osd pattern (`LUMEN_DESKTOP_THEME_FILE`).

---

## Critical files

**Modified**
- `/home/nicholas/Dokumenter/git/LumenShell/meson.build` — add `lumen-desktop` executable block.
- `/home/nicholas/Dokumenter/git/LumenShell/AGENTS.md` — add a `lumen-desktop` section following the existing template.

**New**
- `lumen-desktop/src/main.vala`
- `lumen-desktop/src/window.vala`
- `lumen-desktop/src/appentry.vala` (copy)
- `lumen-desktop/src/searchdb.vala` (copy)
- `lumen-desktop/src/components/apptile.vala` (copy)
- `lumen-desktop/src/components/pagedgrid.vala` (copy, zoom-in stripped)
- `lumen-desktop/src/components/searchresults.vala` (copy)
- `lumen-desktop/src/components/pagedots.vala` (copy)
- `lumen-desktop/src/utils/aliasarray.vala` (copy)

---

## Verification

1. `meson setup build && ninja -C build` — only warnings expected.
2. `./build/lumen-desktop &` inside Wayfire.
3. Confirm end-to-end:
   - On startup, app tiles appear immediately, paginated 6×4 across the full output, with the search bar at the top.
   - Opening a normal app (e.g. via `lumen-dock` or a terminal) → the app's window appears on top of the tile grid; tiles remain visible behind/around it. Closing the app re-exposes the tiles.
   - Clicking the desktop never raises it above normal windows (BACKGROUND layer guarantee).
   - Typing in the search bar filters tiles in place; Alt+1/2/3 launches result N (when search is active).
   - Ctrl+Backspace clears the query.
   - Launching an app from the drawer does NOT hide the desktop; search clears and grid returns to page 0.
   - No ESC behavior — pressing ESC while focused inside the search bar clears the entry only if `Gtk.SearchEntry` default consumes it; otherwise it does nothing (desirable).
   - No zoom-in intro animation at startup.
