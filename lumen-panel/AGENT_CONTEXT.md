# lumen-panel — Agent Context

## Stack
- **Language:** Vala, compiled with `valac` (single-pass, no incremental build)
- **Renderer:** DrawKit — custom C/OpenGL ES2 library (`libdrawkit/`)
- **Wayland:** WLHooks — custom layer-shell + input C library (`wlhooks/`)
- **Build:** `make` → single `valac` invocation, all `.vala` files at once
- **Global state:** `redraw` (bool), `animations` (AnimationManager) — accessible from any file without import

---

## Cross-Project Architecture (repo-level)

This repository contains multiple cooperating projects:

- **`lumen-panel/`**
  - Bottom layer-shell panel process.
  - Uses WLHooks for Wayland + EGL surface lifecycle.
  - Uses DrawKit for all rendering.

- **`Kickoff/`**
  - App launcher process (separate executable).
  - Also uses WLHooks + DrawKit (same rendering/input foundation, different UI).

- **`wlhooks/`**
  - C library that owns Wayland protocol wiring and EGL setup.
  - Exposes Vala bindings via `vapi/libwlhooks.vapi`.

- **`libdrawkit/`**
  - C GLES2 renderer used by panel and launcher.
  - Exposes Vala bindings via `vapi/libdrawkit.vapi`.

- **`vapi/`**
  - Binding layer that lets Vala call into both C libraries directly.

### How the executables interact

- `lumen-panel` launches `Kickoff/main` from the launcher icon click path in `src/components/app.vala`.
- They are **separate processes** with separate event loops and separate WLHooks state, but the same architectural pattern.
- Both depend on `libdrawkit.a` and `libwlhooks.a` at link time.

### Build/dependency direction

`wlhooks` + `libdrawkit` → VAPI bindings → `lumen-panel` / `Kickoff`

Panel Makefile links static libs from:
- `../libdrawkit/build/libdrawkit.a`
- `../wlhooks/build/libwlhooks.a`

---

## Geometry Constants (`src/components/panel.vala`)
```
HEIGHT           = 300   // total layer-shell surface height
EXCLUSIVE_HEIGHT = 60    // reserved bar height at bottom
TRAY_HEIGHT      = 48    // EXCLUSIVE_HEIGHT - 12
TRAY_Y           = 246   // HEIGHT - TRAY_HEIGHT - MARGIN_TOP  (top of icon row at rest)
EXPAND_FULL      = 246   // == TRAY_Y; max expanded_height value
```
Panel is anchored **bottom**. Y=0 is screen-top, Y=300 is screen-bottom.

---

## DrawKit API (`vapi/libdrawkit.vapi` → `libdrawkit/`)

### Coordinate conventions
- **`draw_rect(x, y, w, h, color)`** — x/y = top-left corner
- **`draw_rect_rounded(x, y, w, h, radius, color)`** — x/y = top-left
- **`draw_circle(cx, cy, r, color)`** — cx/cy = centre
- **`draw_texture(tex, x, y, w, h)`** — x/y = top-left
- **`draw_text(text, x, y, size, color)`** — x = **horizontal centre**, y = **baseline**
  - To draw with left-edge + visual-top: use helpers `pdt()` / `pdt_center()` in `itraypage.vala`
  - Ascender offset: `baseline = visual_top + size * 0.82`
  - Text width: `ctx.width_of(text, size)` → pixels; halve for centre offset

### Stencil (`backend.c` confirmed)
```
stencil_push()   → glColorMask(FALSE) + glStencilFunc(GL_ALWAYS)
                   draw_rect() call after this writes ONLY to stencil, invisible to screen
stencil_apply()  → glColorMask(TRUE)  + glStencilFunc(GL_EQUAL)
                   subsequent draws clipped to stencil shape
stencil_pop()    → glDisable(GL_STENCIL_TEST)
```
**No DrawKit modifications needed.** The mask rect is inherently invisible.

### Color tinting textures
`ctx.set_tex_color(color)` multiplies subsequent `draw_texture()` calls. Reset to `{1,1,1,1}` after use.

### DrawKit backend assumptions
- DrawKit does **not** create or own Wayland/EGL objects.
- DrawKit assumes a valid current GLES2 context already exists.
- `begin_frame()` performs `glViewport + glClear`; `end_frame()` performs `glFlush`.
- Buffer presentation is delegated to caller via `WLHooks.swap_buffers()`.

---

## Animation (`src/animation.vala`)
```vala
// Mutates *x in-place every frame via pointer arithmetic
Transition1D(int id, int* x, int end_value, double duration_seconds)
animations.add(transition)   // replaces any existing transition with same id
```
- Easing: **easeOutExpo** (`1 - 2^(-10k)`)
- Global `AnimationManager animations` — `animations.update(dt)` called each frame
- Adding a transition with an existing id **cancels** the previous one

---

## File Map

### `src/components/panel.vala`
- Global geometry constants
- `Panel` class: creates `DrawKit.Context`, `Tray`, `WLHooks.init_layer_shell()`
- Dispatches: `on_window_new/rm`, `on_key_down`, `on_mouse_*`, `render()`

### `src/components/tray.vala`
- **Owns all expansion state:** `expanded_height` (anim id 1), `page_slide_x` (anim id 2), `active_page_idx`
- `layout_children()`: called every render frame; `icon_row_y = TRAY_Y - expanded_height` — icons glide up as tray expands
- `content_top()` = `TRAY_Y - expanded_height + TRAY_HEIGHT` — top of page content area (below icon row)
- `content_height()` = `expanded_height - TRAY_HEIGHT`
- **Render order:** background rounded-rect → stencil_push/apply over content area → separator line → pages loop → stencil_pop → icons on top
- Page loop: `px = this.x + p * this.width + page_slide_x` — two pages partially visible during slide
- Stencil rect is drawn at `(this.x, ct, this.width, ch)` — **content area only, not icon row**
- `toggle_page(p)`: same index → collapse; new index → deactivate old, start expand anim if `expanded_height==0`, start slide anim to `-p * width`, activate new
- `collapse()` on mouse-leave of bounding box `[x .. x+width] × [icon_row_y .. TRAY_Y+TRAY_HEIGHT]`

### `src/components/trays/itray.vala`
Interfaces:
- `ITray` — `get_width()`, `set_position(x,y)`, `render(ctx)`
- `IClickable` — `mouse_down()`, `mouse_up()`
- `IHoverable` — `mouse_motion(mx,my)`; static `is_hover(x,y,w,h,mx,my)`
- `IUpdateable` — `update()`, `get_status()`
- `IHasPage : GLib.Object` — `get_page() → ITrayPage`, `is_icon_hovered() → bool`
  - **Must extend `GLib.Object`** for runtime interface cast to work

### `src/components/trays/itraypage.vala`
- `ITrayPage : GLib.Object` interface — `get_title`, `on_activate`, `on_deactivate`, `render(ctx,x,y,w,h)`, `mouse_down/up/motion`
- Free helpers:
  ```vala
  pdt(ctx, text, left_x, visual_top_y, size, color)        // left-aligned
  pdt_center(ctx, text, centre_x, visual_top_y, size, color) // centred
  ```

### `src/components/trays/iconandtext.vala`
- Base class `IconAndText : Object, ITray, IHoverable`
- Holds: `width`, `x`, `y`, `text`, `last_mx/my`, `icon: HoverableIcon`
- No expansion logic — Tray manages all expansion

### `src/components/trays/hoverableicon.vala`
- `ICON_SIZE = 32`, `HOVER_RADIUS = 24`, width = `HOVER_RADIUS*2 = 48`
- `set_position(x, y)`: stores `this.y = y + MARGIN_TOP` where `MARGIN_TOP = (TRAY_HEIGHT - ICON_SIZE)/2 = 8`
- Icon images: SVG files in `src/res/*.svg`, rasterized via `DrawKit.image_from_svg(path, 32, 32)`
- `hovered: bool` — set in `mouse_motion()`; triggers `redraw = true` on change

### `src/components/trays/wifi.vala`
- `WifiTray : IconAndText, IUpdateable, IHasPage`
- `update()`: runs `nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device`, parses connected SSID
- Icon: `"wifi"` (green tint) or `"nowifi"` (grey tint)
- Tint applied via `ctx.set_tex_color()` before `icon.render()`, reset after

### `src/components/trays/battery.vala`
- `BatteryTray : IconAndText, IUpdateable, IHasPage`
- Reads `/sys/class/power_supply/BAT0/{status,charge_full,charge_now,voltage_now,current_now}`
- Icon variants: `"battery-high"`, `"battery-mid"`, `"battery-low"`, `"battery-charging"`, `"battery-nobattery"`

### `src/components/trays/wifipage.vala`
- `WifiPage : GLib.Object, ITrayPage`
- `on_activate()`: spawns background thread → `nmcli dev wifi list` → parses nets → sets `redraw = true`
- `on_deactivate()`: `WLHooks.register_on_key_down(null)` (1 Vala warning, works at C level)
- Keyboard captured with `WLHooks.register_on_key_down(cb)` during password entry
- Layout constants: `PAD=14`, `HEADER_H=44`, `ROW_H=36`, `PASS_H=54`, `MAX_NETS=8`
- `draw_signal_bars()`: 4 vertical bars, filled count = `signal/25` clamped to 4

### `src/components/trays/batterypage.vala`
- `BatteryPage : GLib.Object, ITrayPage`
- Renders: large colour-coded percentage, status label, charge bar, 2×2 stats grid
- No keyboard / no background thread

---

## WLHooks (`vapi/libwlhooks.vapi`)
```vala
WLHooks.register_on_key_down(SeatKeyDown? cb)
// SeatKeyDown = delegate void (uint32 key, uint32 sym, uint32 mods)
// Pass null to unregister. Parameter is non-nullable in vapi → 1 warning, harmless.
```
Fix: mark parameter nullable in vapi: `SeatKeyDown? cb`

### WLHooks EGL + layer-shell ownership (important)

In `wlhooks/main.c`:
- `wlhooks_init()` connects display and initializes protocol modules.
- `init_layer_shell(...)` creates layer-shell `wl_surface` then calls `egl_init(...)`.

In `wlhooks/egl.c`:
- `eglGetDisplay` + `eglInitialize`
- chooses EGL config
- creates `wl_egl_window`
- creates EGL window surface + GLES2 context
- calls `eglMakeCurrent(...)`

This means:
- **WLHooks owns EGL display/surface/context lifecycle**.
- It makes that context current before Vala rendering begins.
- **DrawKit then renders into that same current context**, so EGL state implicitly couples WLHooks and DrawKit.

Practical model:
1. WLHooks creates layer-shell surface + EGL context and makes it current.
2. Vala creates `DrawKit.Context` and issues draw calls.
3. DrawKit writes GL commands into the current EGL context.
4. WLHooks swaps buffers (`eglSwapBuffers`) to present.

So: WLHooks = window/context/platform owner; DrawKit = GPU drawing engine using that context.

---

## Build Command
```
valac --vapidir=../vapi \
  --pkg=libdrawkit --pkg=libwlhooks --pkg=glesv2 --pkg=wayland-client \
  --pkg=glib-2.0 --pkg=gio-2.0 --pkg=gee-0.8 --pkg=egl \
  -X -O2 \
  -X -I../libdrawkit  -X ../libdrawkit/build/libdrawkit.a \
  -X -I../wlhooks     -X ../wlhooks/build/libwlhooks.a \
  -X -lwayland-egl -X -lwayland-client -X -lEGL -X -lGLESv2 \
  -X -lm -X -lfreetype -X -lxkbcommon \
  -o main \
  src/*.vala src/components/*.vala src/components/trays/*.vala
```

`Kickoff` follows the same pattern (Vala app + WLHooks + DrawKit + swap loop), with its own `Processor`/input flow.

---

## Runtime loop contract (panel)

- `WLHooks.init()` bootstraps Wayland state.
- `Panel` constructor calls `WLHooks.init_layer_shell(...)` before rendering.
- Main loop:
  - `display_dispatch_blocking()` pumps events.
  - if `redraw || animations.has_active`:
    - update animations
    - render via DrawKit
    - `WLHooks.swap_buffers()`

This contract is shared conceptually by Kickoff.

---

## Known Gotchas
| Issue | Cause | Fix |
|---|---|---|
| `missing class prerequisite` on interface cast | Interface lacks `GLib.Object` prereq | Add `: GLib.Object` to interface |
| Comma-grouped field declarations | Vala parser rejects `int a, b;` at class scope | Declare each field separately |
| Cast `(SomeDelegate?) null` → undeclared C type | Vala emits `SomeDelegateName` in generated C | Use plain `null` |
| `draw_text` y is baseline not top | DrawKit font API | Use `pdt()` / `pdt_center()` helpers; add `size * 0.82` |
| Stencil rect must match content area exactly | Wrong y = icon_row_y clips wrong region during animation | Use `content_top()` not `icon_row_y` |
