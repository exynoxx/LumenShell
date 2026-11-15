# lumen-background — plan

Status: **plan only, no source yet.** This file is the whole tree until Phase 1 starts.

## 1. Purpose, scope, non-goals

`lumen-background` draws the desktop wallpaper, one surface per output. It replaces
wf-shell's `wf-background` for one reason: the user wants to choose **which part of
an oversized image is shown**. In the settings Wallpaper page, they drag a
screen-shaped rectangle over a miniature of the whole picture.

wf-background has no position option. `[background]` offers only `image`,
`cycle_timeout`, `fade_duration`, `randomize` and `fill_mode`. Earlier research ruled
out the alternatives:

- **Other daemons:** swaybg (the only one packaged for Fedora 44) has no position;
  wpaperd is 1-axis; oguri is a 9-way anchor and archived; the rest are unusable.
- **Pre-cropped PNGs** break the slideshow and per-monitor aspect; **a wf-shell patch**
  is a downstream burden; **a Wayfire plugin** means in-compositor decode and ABI rebuilds.

A small GTK client is the cheapest option that the repo already knows how to build.

**In scope:**

- one image, or a folder slideshow with shuffle and a cross-fade;
- fill modes cover, contain and stretch;
- in cover mode, a 2D focus plus zoom;
- live reload when `wallpaper.ini` changes;
- reading wf-shell.ini once as a migration fallback.

**Non-goals:**

- video or animated wallpapers;
- a different wallpaper per workspace or per output (every output shows the same
  image, cropped to its own aspect);
- a right-click desktop menu, or any other input;
- solid-colour or gradient backgrounds, tiling;
- IPC or DBus. The config file is the only interface.

## 2. Architecture

```
lumen-settings Wallpaper page ──writes──▶ ~/.config/lumen-shell/wallpaper.ini
                                                   │ FileMonitor on the DIRECTORY
                                                   ▼
lumen-background (Gtk.Application, id org.lumenshell.Background)
   WallpaperState ── decode thread ──▶ Gdk.MemoryTexture (shared by all outputs)
   one BackgroundWindow per Gdk.Monitor ── BackgroundView (snapshot-drawn)
lumen-lockscreen ──reads image + focus──▶ same wallpaper.ini
```

- **Application.** `Gtk.Application`, `hold()`, with no libadwaita and no Gee. It quits
  if `GtkLayerShell.is_supported()` is false, as lumen-notifications does.
- **Windows.** A `GLib.HashTable<Gdk.Monitor, BackgroundWindow>` is reconciled from
  `display.get_monitors().items_changed`. This is the `OsdWindowGroup.reconcile()`
  pattern (`lumen-osd/src/window_group.vala`) minus the persistent primary: destroy a
  window whose monitor has gone, create one for each new monitor. A hotplug also
  re-checks the decode size (§5).
- **Layer-shell setup** (from `lumen-desktop/src/window.vala`, with these differences):
  - `init_for_window`, `set_namespace("lumen-background")`, `set_monitor(mon)`;
  - `Layer.BACKGROUND`, all four anchors;
  - `set_exclusive_zone(-1)`, so the wallpaper extends under the panel's exclusive zone;
  - `KeyboardMode.NONE`;
  - `decorated = false`; window background `#000` (one-rule `CssProvider`).
- **Input region.** Set an **empty** input region on map:
  `surface.set_input_region(new Cairo.Region())`. Nothing is clickable here. Clicks on
  bare desktop then reach no client, the same as with no wallpaper.
- **`BackgroundView : Gtk.Widget`.** It has no children. `snapshot()` computes the
  view rect from the shared math (§4) for its own width and height, then calls
  `append_scaled_texture(tex, Gsk.ScalingFilter.TRILINEAR, rect)` inside
  `push_clip(bounds)`. During a fade it wraps that in `push_cross_fade` (§6).
- **`WallpaperState`** is a singleton that owns the config, the current and next
  textures, and the slideshow timer. It emits `changed`, and every view calls
  `queue_draw()` on it.

**Peek plugins: no changes needed.** I grepped `wayfire-plugins/*/src/*.cpp`. No plugin
looks for wf-background by app_id; they work on the
`output->node_for_layer(scene::layer::BACKGROUND)` nodes:

| Plugin | What it does to BACKGROUND |
|---|---|
| curtain-peek | Hides the layer (`set_live_layers_hidden`). |
| slide-peek | Captures without BACKGROUND, so the wallpaper stays still. |
| zoom-peek | Snapshots the front of BACKGROUND. |
| panel-push | Its `collect_views_from_output({BACKGROUND, …})` slides the wallpaper too. |
| startup-zoom | Treats it like any other mapped view, as with wf-background today. |

The last two behave as they do today with wf-background. That is inherited behaviour,
not new behaviour. Any client that maps on BACKGROUND behaves identically.

## 3. Config — `wallpaper.ini [wallpaper]`

The path comes from `LumenCommon.Paths.wallpaper_ini()` (the file already exists).
lumen-settings is the **only writer**. lumen-background and lumen-lockscreen only read
it. Because the daemon never writes, the directory monitor can never trigger itself.

```ini
[wallpaper]
image=/home/u/Pictures/Wallpapers/a.jpg   # always a FILE (lock screen relies on it)
fill-mode=cover                           # cover | contain | stretch
focus-x=0.5                               # 0..1, fraction of horizontal slack
focus-y=0.5                               # 0..1, fraction of vertical slack
zoom=1.0                                  # >= 1 (UI caps at 4)
slideshow=false
slideshow-folder=/home/u/Pictures/Wallpapers
slideshow-interval=150                    # seconds
slideshow-shuffle=false
fade-ms=1000
gallery-folders=/home/u/Pictures;/usr/share/backgrounds;   # existing, page-only
```

**Deviations from the brief, with reasons:**

- **`slideshow-folder`, not `folder`.** The page already writes `slideshow-folder`
  (`wallpaper_page.vala:241`), so the user's file already has it.
- **`slideshow-interval` and `slideshow-shuffle`.** Prefixed for the same reason, so
  the keys sort together.
- **A new explicit `slideshow` boolean.** Today "slideshow on" is encoded as
  "wf-shell.ini `image` is a directory". That encoding disappears, and `image` stays a
  file because the lock screen needs a file.
- **`fill-mode` values are lumen names.** wf-shell's names are mapped once during
  migration.

**Unknown keys are ignored.** The user's live file carries a stale `mode=tile`. It is
ignored and never rewritten.

**Locale-independent floats.** `GLib.KeyFile.get_double` / `set_double` use
`g_ascii_strtod` / `g_ascii_dtostr`, so values come out with `.` even under da_DK.
- The daemon reads `focus-*` and `zoom` with `get_double`. A missing key or a parse
  error falls back to the default, and values are clamped (focus to [0,1], zoom to
  [1,8]).
- Settings writes them through the existing `IniRows.put()`, formatting with
  `double.format(buf, "%.4f")`, which is what `fmt_double` already does. Move
  `fmt_double` and `parse_double` from `input_common.vala` into the shared math file
  (§4) so the two sides cannot diverge.

**Live reload.**
- Settings saves through KeyFile, which uses `g_file_set_contents` (write a temp file,
  then `rename()`). The inode changes, so a monitor on the file itself goes deaf after
  the first save.
- Instead, monitor `Paths.config_dir()` with `File.monitor_directory(WATCH_MOVES)`.
  Accept any event whose `file` or `other_file` basename is `wallpaper.ini`.
- Debounce for 200 ms (`Timeout.add` with re-arm), then reload.
- On reload, diff against the old config:
  - only focus, zoom or fill changed: redraw;
  - path changed, or the needed decode size grew (§5): re-decode;
  - slideshow keys changed: restart the timer.
- If `Paths.config_dir()` is missing, create it with `Paths.ensure_dir()` first.

**Migration from wf-shell.ini.**
- **Daemon:** while `wallpaper.ini` lacks the `fill-mode` key (the marker for "never
  migrated"), read `Paths.wf_shell_ini() [background]` as a read-only fallback.
- **Settings:** the first time the Wallpaper page builds and finds no `fill-mode`, it
  writes the translated keys once. After that, both sides ignore wf-shell.ini.

| wf-shell `[background]` | wallpaper.ini |
|---|---|
| `image` = file | `image` (only if wallpaper.ini has none) |
| `image` = directory | `slideshow=true`, `slideshow-folder=<dir>` |
| `fill_mode` `fill_and_crop` / `preserve_aspect` / `stretch` | `fill-mode` `cover` / `contain` / `stretch` |
| `cycle_timeout` (s) | `slideshow-interval` |
| `randomize` | `slideshow-shuffle` |
| `fade_duration` (ms) | `fade-ms` |

## 4. Drawing math

There is one UI-free file, `lumen-common/wallpaper_crop.vala`, as a new source group
`wallpaper_crop_source`. Three binaries compile it: the daemon, settings (for the
miniature's inverse mapping) and the test. Lockscreen also compiles it if §7 is
adopted. There is no second copy.

Symbols:

| Symbol | Meaning |
|---|---|
| `W×H` | output size |
| `iw×ih` | image size; texture pixels are fine, since only ratios matter |
| `fx, fy` | focus |
| `z` | zoom |

**cover** (`ViewRect cover(W,H,iw,ih,fx,fy,z)`, in image coordinates):

```
s    = max(W/iw, H/ih) · z         # image px → output px
vw   = W / s ;  vh = H / s         # visible window, image px (vw ≤ iw, vh ≤ ih)
left = fx · (iw − vw)
top  = fy · (ih − vh)
dest = (−left·s, −top·s, iw·s, ih·s)   # what append_scaled_texture gets, clipped to W×H
```

**Inverse** (for the miniature). Given a rect origin `left`, compute
`fx = slack > ε ? clamp(left / slack, 0, 1) : 0.5`, where `slack = iw − vw`. The same
applies to `fy`. Zero slack on an axis means that axis is pinned: the drag does nothing
there, and there is no division by zero.

**contain:** `s = min(W/iw, H/ih)`, centred, with black letterbox bars (hard-coded; the window
background). Focus and zoom are **ignored**. There is no slack to distribute, and
"zoomed contain" would just be cover.

**stretch:** `dest = (0, 0, W, H)`. Focus and zoom are ignored.

**Why a slack fraction instead of a centre point.** Suppose the focus were a point
`(cx, cy)` in the image. On a monitor with a different aspect ratio, the window
centred there often runs off the image edge and has to be clamped.
- With clamping, the point the user picked is no longer centred, and the clamping
  differs per output. A 21:9 monitor and a 16:10 monitor then disagree in ways the
  miniature never showed.
- A slack fraction is valid on every output by construction, so it needs no clamping.
  `fx = 0` means "flush left" everywhere, `1` means "flush right" everywhere, and `0.5`
  means centred. This matches how a user describes the intent ("show the left part").
- What it gives up: on an output with a different aspect, the same subject is not
  pixel-identically centred. That is acceptable, because the user positions against
  the first monitor (§8) and the other outputs keep the proportional intent.

## 5. Texture memory

- **Decode once and share.** There is one `Gdk.MemoryTexture` for all outputs.
  Textures are immutable and thread-safe to hand across, and every `BackgroundView`
  draws the same object.
- **Decode off the main thread.** Use `new Thread<void*>`, then `Idle.add` the result.
  This is the same idiom as `WallpaperPage.load_scaled`, which converts with
  `to_texture()` into `MemoryFormat.R8G8B8` (or `R8G8B8A8` with alpha) without the
  deprecated `Texture.for_pixbuf`.
- **Decode at a reduced size, computed correctly for cover.**
  `from_file_at_scale(w, h, true)` fits the image *inside* the box. For cover, that
  under-decodes one axis, so:
  1. `Gdk.Pixbuf.get_file_info(path, out iw, out ih)` reads the header only.
  2. Over all outputs, take device pixels: `Wd = geometry.width · monitor.scale`. Use
     `get_scale()`, which is fractional on GTK ≥ 4.14.
  3. `need = max over outputs of max(Wd/iw, Hd/ih) · z`, capped at 1.0 (never decode
     larger than native).
  4. Decode at `ceil(iw·need) × ceil(ih·need)`, with `preserve_aspect = true`.
  5. For contain and stretch, use `z = 1`.

  Example: a 6000×4000 JPEG on a 2560×1440 output at zoom 1 decodes at 2560×1707,
  about 13 MB as RGB8. At native size it would be 72 MB.
- **Re-decode** when a hotplug or a zoom change raises `need` above the decoded scale.
  Never re-decode just to shrink.
- **At most two textures alive:** current, and next during a fade. Drop `prev` the
  moment the fade completes. While idle, the slideshow pre-decodes nothing. It decodes
  the next image when the timer fires, and starts the fade once the decode lands.
- **Formats are glycin-backed on this box.** Fedora 44 ships gdk-pixbuf 2.44.4 with
  an empty `loaders/` dir plus `glycin-loaders` 2.1.5 (`glycin-image-rs`, `-heif`,
  `-jxl`, `-svg`), so jpeg/png/webp/avif/heif/jxl come from glycin, not per-format
  pixbuf modules. An unreadable file: one warning, keep the previous texture, and in a
  slideshow skip to the next file (the gallery already skips silently).
- **Verify in Phase 1 (glycin semantics, not assumed):**
  - whether EXIF orientation is already applied on load. If it is not, call
    `apply_embedded_orientation()` and swap `iw`/`ih` for orientations 5–8;
  - whether `get_file_info` reports pre- or post-rotation size;
  - whether `from_file_at_scale` lowers *peak* decode memory or only the kept size.

## 6. Slideshow

- **Folder scan.** Non-recursive, the same filter as the page's `collect_images`
  (`image/*` by fast-content-type, not hidden), sorted by name. Rescan when the list
  wraps, so new files appear without a restart.
- **Timer.** `Timeout.add_seconds(slideshow-interval)`, restarted on reload.
- **Shuffle.** Fisher–Yates the list once per pass with `GLib.Random.int_range`, so
  nothing repeats until every image has shown. If the new pass would start with the
  image just shown, swap it with the second entry.
- **Start position.** If `image` is inside the folder, start there. Otherwise start at
  the first file.
- **Cross-fade.**
  1. Once the next texture decodes, record `fade_start = frame_clock time`.
  2. Each view adds a tick callback that calls `queue_draw` until `t ≥ fade-ms`.
  3. Snapshot: `push_cross_fade(p)`, draw prev, `pop()`, draw next, `pop()`, with
     `p = t/fade-ms` eased (ease-in-out cubic).
  4. `fade-ms = 0` means a hard cut.
  5. A config reload that changes `image` mid-fade starts a new fade from whatever is
     current.
- **Where focus applies.** `focus-x/y` and `zoom` belong to **the file named by
  `image`**. When the slide being drawn is not `image`, it is drawn with cover at
  `fx = fy = 0.5`, `z = 1`.

**Why focus is stored per one image, not per image.** The alternative is a map from
each image to its focus.
- `GLib.KeyFile` key names cannot reliably hold arbitrary paths (`=`, `[`, `]`, and
  leading or trailing spaces). That would need a separate JSON file with a `Paths`
  getter, and garbage collection for deleted images.
- Nobody has asked to tune every slide.

Single-focus storage is three keys with one rule. The settings page resets
`focus-x=0.5`, `focus-y=0.5`, `zoom=1` (`remove_key`) whenever `image` changes, so a
focus can never apply to the wrong picture. Upgrade path: a
`wallpaper-focus.json` map keyed by path. Add it if someone wants a per-slide focus.

## 7. Lockscreen interplay

`BlurredWallpaper.resolve_path()` keeps reading `wallpaper.ini image`, which is always
a real file. Drop its wf-shell.ini fallback in Phase 4.

**Recommendation: honour the focus.** Without it, locking visibly jumps from the user's
chosen crop to a centred crop of the same picture. The cost is small:

- `LockBackdrop` currently draws a `Gtk.Picture` with `ContentFit.COVER`. Replace that
  with an `append_scaled_texture` of the shared `cover()` rect.
- Read `focus-*` and `zoom` alongside `image` (KeyFile `get_double`).
- Add `wallpaper_crop_source` to the lockscreen target.

The blur crops `blur_radius` px off each edge. That changes `iw×ih` by under 1 %, which
does not matter under a blur, so do not compensate. In a slideshow, the lock screen
shows `image` (the picked one) with its focus, not the current slide. That is
consistent and needs no extra state.

## 8. Settings side

### `CropMiniature : Gtk.Widget` (new file `lumen-settings/src/widgets/crop_miniature.vala`)

- **Inputs.** A preview texture (the existing ≤1280 px `load_scaled`), the real `iw×ih`
  from `Pixbuf.get_file_info`, the output aspect, `fx`, `fy`, `z`, and `cover_mode`.
- **Measure.** Natural width 480, height from the image aspect, capped at 320.
- **Snapshot.**
  1. Contain-fit the whole image, scale `p = min(w/iw, h/ih)`, centred, rounded clip.
  2. In cover mode, compute `cover(W_ref, H_ref, iw, ih, fx, fy, z)` and map it to
     widget coordinates with `p`.
  3. Dim the outside with **4 rects** (above, below, left, right of the window) using
     `append_color(rgba(0,0,0,0.55))`.
  4. Draw the window with `append_border` at 2 px, white.
  5. Outside cover mode, draw no rect and no dimming.
- **Reference aspect** `W_ref:H_ref` is the first `Gdk.Monitor`'s geometry, the same
  source as the page's existing `monitor_ratio()`. Rect size is the cover window at that
  aspect divided by zoom.
- **`GestureDrag`.**
  - On `drag_begin`: if the press is outside the rect, first centre the rect on the
    pointer (through the inverse). Then record `left0`, `top0`.
  - On `drag_update(dx, dy)`: `left = left0 + dx/p` and `fx = inverse(left)`, so the
    rect moves exactly with the pointer until it hits an edge. Redraw only.
  - On `drag_end`: emit `focus_changed(fx, fy)`. The page writes `focus-x`/`focus-y`
    **only here**, so the desktop updates once per drag rather than once per motion
    event.
- **Zoom.**
  - An optional `Gtk.Scale` from 1 to 4 under the miniature.
  - `EventControllerScroll` on the miniature: `z *= 1.1^(−dy)`, clamped.
  - Both recompute `fx`/`fy` so the rect **centre** stays put, then emit
    `zoom_changed(z)`.
  - The page debounces the zoom write by 300 ms, because scroll and scale have no
    "end" event.
- **"Will upscale" hint.** For each monitor, compute the visible source pixels as
  `vw` in real `iw` px against that output's device width `Wd`. If `vw < Wd`, show the
  subtitle "Upscaled ×1.6 on DP-2", where 1.6 is `Wd/vw`. This uses the real image
  size, never the preview texture's.

### `wallpaper_page.vala` changes

- **Remove the `wf` `IniRows` entirely.** Every write goes to `wp` (`wallpaper.ini`),
  and the header comment changes to name lumen-background.
- **Preview.** The `AspectFrame` and `Gtk.Picture` preview become the `CropMiniature`.
  The live desktop is the "how it looks" preview now. It updates on drag end.
- **Fill.** `combo_row("fill-mode", …, { "cover", "contain", "stretch" }, "cover")`.
  The miniature's `cover_mode` follows it.
- **`apply_image`.** Writes `image`, removes `focus-x`, `focus-y` and `zoom`, turns the
  slideshow off, and resets the miniature.
- **Slideshow switch.** Writes `slideshow=true|false`. If it still moves `image` to the
  folder's first file, that path resets focus and zoom too (one helper, `set_image()`,
  used by both). Picking a folder writes `slideshow-folder`.
- **`IniRows.remove(key)`.** A three-line addition in `input_common.vala`, because
  `IniRows` exposes only `get_str`/`put` today.
- **Interval, shuffle, fade.** `wp.int_row("slideshow-interval", …)`,
  `wp.bool_row("slideshow-shuffle", …)`, and a new `wp.int_row("fade-ms", 0, 5000, …)`.
- **Migration.** Runs on build when `fill-mode` is absent (§3).
- **`restart_target()`** stays `null`, which is what it already is today. The daemon
  live-reloads.
- **wf-background warning.** At build, read `Paths.wayfire_ini()` through `IniStore` and
  scan `[autostart]` values for `wf-background` or `swaybg`. If any are found, show a
  warning row at the top: "Another wallpaper program is autostarted; it will cover
  LumenShell's wallpaper". It has a **Remove** button that `remove_key`s that autostart
  entry and runs `Proc.spawn_detached({"pkill", "-x", "wf-background"})`. If
  `lumen-background` itself is missing from `[autostart]`, the same row says so instead.
  This is cheap: `IniStore` and `Proc` are already compiled into settings.

## 9. Build & packaging

- **Option.** `with_background` (boolean, default `true`) in `meson_options.txt`. It
  has no optional dependencies, so a boolean, not a feature. It exists so a user can
  stay on wf-background with zero LumenShell wallpaper code.
- **Target.** Copy the lumen-desktop block (`meson.build` ~line 345), unparked:

  ```meson
  background_deps = [gtk4_layer_shell_dep, gtk4_dep, glib_dep, gio_dep, m_dep]  # layer-shell FIRST
  executable('lumen-background',
    files('lumen-background/src/main.vala', 'lumen-background/src/window.vala',
          'lumen-background/src/view.vala', 'lumen-background/src/state.vala')
      + paths_source + wallpaper_crop_source,
    vala_args: ['--vapidir=' + vapi_dir, '--pkg=gtk4', '--pkg=gtk4-layer-shell-0',
                '--pkg=glib-2.0', '--pkg=gio-2.0', '--pkg=gdk-pixbuf-2.0'],
    c_args: lumen_datadir_c_args,          # paths.vala's extern LUMEN_DATADIR
    dependencies: background_deps,
    link_args: ['-Wl,--no-as-needed'],     # else gtk_layer_init_for_window no-ops
    install: true)
  ```

  Add `wallpaper_crop_source` to lumen-settings' sources (in `lumen-settings/meson.build`)
  and, under §7, to lumen-lockscreen.
- **Autostart.** Add this line to `lumen-lockscreen/data/wayfire/lumenshell.ini.d/autostart.ini`,
  which is installed to `<datadir>/lumenshell/wayfire.ini.d` by `meson.build:685`:

  ```ini
  # Desktop wallpaper (replaces wf-shell's wf-background — remove `background=wf-background`).
  background    = systemd-cat -t lumen-background lumen-background
  ```

  This replaces the commented `# background = swaybg …` example. It reuses the key
  name `background` on purpose: a user who merges the snippet by hand edits the
  existing `background=wf-background` line in place. After a blind `cat >>`, the result
  depends on how Wayfire treats a duplicate `[autostart]` key, so verify that (§11, checklist item 8)
  and rely on the settings warning row rather than on the merge.
- **The user's own `~/.config/wayfire.ini` still has `background=wf-background`**
  (line 28 today). It must go. Otherwise two opaque clients are stacked on BACKGROUND,
  and which one wins depends on map order, which is unpredictable: the comment in
  `lumen-desktop/src/window.vala` notes that wf-background "tends to map after us". The
  settings warning row (§8) handles it from the UI side.

## 10. Phases

| # | Phase | Files | Effort |
|---|---|---|---|
| 1 | **Daemon MVP**: single image, fill modes, focus and zoom, per-monitor and hotplug, empty input region, dir-monitor reload, wf-shell fallback | `lumen-background/src/{main,window,view,state}.vala`, `lumen-common/wallpaper_crop.vala`, `meson.build`, `meson_options.txt`, `tests/wallpaper_crop.vala` | ~350 lines, 1 day |
| 2 | **Slideshow and fade**: scan, timer, shuffle, `push_cross_fade`, two-texture cap | `state.vala`, `view.vala` | ~150 lines, ½ day |
| 3 | **Settings miniature**: `CropMiniature`, zoom scale and scroll, upscale hint, page rewired to wallpaper.ini keys (the `wf` rows and every wf-shell.ini write go here), `IniRows.remove`, one-time migration, wf-background warning row | `lumen-settings/src/widgets/crop_miniature.vala`, `pages/wallpaper_page.vala`, `pages/input_common.vala`, `lumen-settings/meson.build` | ~300 lines, 1 day |
| 4 | **Cleanup**: drop the lockscreen's wf-shell.ini fallback, lockscreen honours focus (§7), autostart.ini line, CLAUDE.md section | `blurred_wallpaper.vala`, `background.vala`, `autostart.ini`, `CLAUDE.md` | ~60 lines, ½ day |

Install after every phase. For Phase 1, test with
`meson devenv -C build ./lumen-background` after `pkill wf-background`.

**CLAUDE.md section to add in Phase 4.** Also add it to the architecture diagram, the
build-targets count and option table, and the `paths_source` consumer list.

> ## lumen-background
>
> Desktop wallpaper: one `BACKGROUND`-layer surface per `Gdk.Monitor`. Anchored on all
> four edges with `exclusive_zone -1`, `KeyboardMode.NONE`, and an empty input region.
> Reconciled on hotplug like lumen-osd. It replaces wf-shell's wf-background, so remove
> `background=wf-background` from `wayfire.ini` or the two stack unpredictably. It reads
> `Paths.wallpaper_ini() [wallpaper]` (`image`, `fill-mode`, `focus-x/y`, `zoom`,
> `slideshow*`, `fade-ms`) and live-reloads through a debounced `FileMonitor` on the
> config **directory**, because KeyFile saves by atomic rename. It never writes config:
> lumen-settings is the only writer. Focus and zoom are a **fraction of slack** for
> `cover` only, and belong to the `image` file alone (other slides are centred). The
> math lives in `lumen-common/wallpaper_crop.vala` (`wallpaper_crop_source`: background,
> settings, lockscreen, `tests/wallpaper_crop.vala`). There is one shared, off-thread,
> reduced-size `Gdk.MemoryTexture`, sized to the largest output × zoom and capped at
> native; at most two are alive during a fade. The peek plugins need nothing: they act
> on the BACKGROUND layer node, not on a client.

## 11. Risks, open questions, test plan

**Risks and open questions**

- **Map order versus wf-background.** If the user forgets to remove it, the result is
  a coin flip. The settings warning row is the mitigation.
- **Startup flash.** The surface maps black until the first decode lands, about
  100–300 ms for a large JPEG. Options: skip `present()` until the first texture is
  ready (one line; preferred), or accept it.
- **Fractional scaling.** Check that `append_scaled_texture` with TRILINEAR stays sharp
  at 1.25 and 1.5. The decode already uses device pixels.
- **Big outputs × zoom 4** can still decode native 50 MP images (~150 MB RGB8, briefly
  two of them). The upscale hint does not cover memory. Cap `need·iw` at 16384 if this
  turns out to matter.
- **EXIF orientation** must agree between the daemon and the lockscreen
  (`Texture.from_filename`), both on glycin. Verify with a rotated phone JPEG.

**Real Wayfire session checklist**

1. Remove `background=wf-background`, add the autostart line, and log in again. The
   wallpaper shows on every output, extends under the panel, and nothing flickers.
2. Hotplug an external monitor: a window appears with the correct crop for its aspect.
   Unplug: no leaked window, and `journalctl --user -t lumen-background` is clean.
3. In settings, drag the rect to the far left and release: the desktop updates once,
   flush left. Try a 21:9 or portrait output too.
4. Zoom with the scroll wheel to 3×: the desktop zooms after 300 ms; the upscale hint
   appears for a small image.
5. Switch fill mode to contain and to stretch: the rect disappears and the desktop
   letterboxes or stretches.
6. Turn on the slideshow at 10 s with shuffle and a fade: cross-fades are smooth and
   two-texture memory is visible in `smem`/`top`. The focused `image` keeps its crop;
   other slides are centred.
7. Run each peek plugin in turn (curtain, slide, zoom), Win+D, panel-push, and
   startup-zoom at login: they behave exactly as with wf-background. Click bare
   desktop while peeked (the empty input region is new behaviour).
8. Append the autostart snippet blindly (`cat >>`) to a copy of `wayfire.ini` that
   still has `background=wf-background`, and check which duplicate key Wayfire runs.
9. Lock (Win+L): the blurred backdrop shows the same crop as the desktop (§7).
10. Run under `LC_ALL=da_DK.UTF-8`: `wallpaper.ini` has `focus-x=0.2500`, never
   `0,2500`.
11. Hand-edit `wallpaper.ini` with an editor that saves in place (no rename): the
    reload still fires, because the directory monitor sees `CHANGED`.

**Core assert test: `tests/wallpaper_crop.vala`.** Meson test `wallpaper-crop`, built
like `search-core` with `wallpaper_crop_source` and `glib_dep` only. It is one `main()`
of asserts:

- `cover(1920,1080, 3840,1080, 0,_,1)` gives `left == 0`; `fx = 1` gives
  `left == iw − vw`; `fx = 0.5` is centred.
- An image of exactly the output aspect has zero slack: `left == top == 0` for any
  `fx`, and the inverse returns 0.5 with no NaN.
- `z = 2` halves `vw` and `vh`.
- `inverse(cover(...).left) == fx` round-trips to within 1e-9 for a few values.
- `contain` and `stretch` ignore `fx`, `fy` and `z`.
- `fmt_double(0.25)` gives `"0.2500"` after `Intl.setlocale(ALL, "da_DK.UTF-8")` (skip
  if the locale is missing), and `parse_double("0.25")` returns 0.25 under the same
  locale.
- The decode-size helper: with `need` capped at 1, a small image is never upscaled at
  decode.
