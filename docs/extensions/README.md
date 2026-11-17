# Writing LumenShell extensions

An extension is a folder of Vala sources that lumen-panel compiles with `valac`
and loads at startup. Fastest way in: copy the example and edit it.

```sh
mkdir -p ~/.config/lumen-shell/extensions
cp -r /usr/share/lumenshell/examples/extensions/tray-wedge ~/.config/lumen-shell/extensions/
echo '{ "slots": { "tray.presenter": "tray-wedge" } }' > ~/.config/lumen-shell/extensions.json
pkill -x lumen-panel; setsid -f lumen-panel
```

## Folder layout

```
~/.config/lumen-shell/extensions/<id>/
  manifest.json
  *.vala            # every .vala in the folder is compiled
  anything-else     # data files, reached with ctx.path("…")
```

The folder name is not significant; the manifest `id` is.

## manifest.json

```json
{
  "id": "tray-wedge",
  "name": "Wedge tray",
  "version": "1",
  "api": 1,
  "provides": ["tray.presenter"],
  "packages": [],
  "params": {
    "height": { "type": "int", "default": 320, "min": 150, "max": 800, "label": "Height" }
  }
}
```

| Field | |
|---|---|
| `id` | Required. `^[a-z][a-z0-9-]*$`. |
| `name`, `version` | Required strings. |
| `api` | Required. Must equal the host's `Lumen.API_VERSION` (currently `1`), or the extension is skipped. |
| `provides` | Slot ids the extension fills (see below). |
| `packages` | Extra `valac --pkg` names, beyond `lumen-ext-1` (which brings gtk4, gio, json-glib, cairo). |
| `params` | User-tunable values. `type` is `bool`, `int`, `double`, `string`, `enum` (with `choices`) or `color`. `min`/`max` clamp numbers; `label` is what Settings shows. |

## Entry point and the namespace rule

Each extension defines one global function:

```vala
public Lumen.Extension lumen_extension_new () {
    return new TrayWedge.Extension ();
}
```

**Every type must live in the namespace derived from the id**: `tray-wedge` →
`namespace TrayWedge`, `my-clock` → `namespace MyClock`. The compiler rejects
anything else. All extensions share one process, so two extensions each
declaring a global `class Tray` would register the same GType name and the
second would fail to load; the per-id namespace makes that impossible.

`Lumen.Extension` has one method, `enable (Lumen.Context ctx)`, called once.
Extensions are never unloaded. If `enable` throws, everything it provided is
withdrawn and the error is reported.

## Slots

`ctx.provide (slot, object)` puts an object into a slot.

| Slot | Cardinality | Object |
|---|---|---|
| `Lumen.SLOT_TRAY_PRESENTER` (`tray.presenter`) | ONE active | `Lumen.TrayPresenter` — `create (model, panel_window)` returns a `Lumen.Tray` for each panel that hosts a tray. |
| `Lumen.SLOT_TRAY_APPLET` (`tray.applet`) | MANY | `Lumen.TrayAppletFactory` — `create ()` returns a `Lumen.TrayApplet` (an icon in the tray row; also implement `Lumen.CcModule` to get a Control Center tile). |

An applet's id is the extension id, so an extension provides at most one
applet. It appears in `panel.json` `tray.order` / `tray.disabled` under that id.

A `Lumen.Tray`:

- `strip_widget ()` — placed at the end of the panel strip, or null.
- `toggle ()` — tray click and the `ToggleTray` DBus hotkey. `collapse ()` — Escape / auto-hide.
- `expanded`, `animating`, `expanded_changed` — the panel uses these for its input region and auto-hide.
- `input_rects (panel_window, region)` — union in whatever must stay clickable on the panel surface. A tray drawn in its own surface adds nothing, and is not collapsed when the pointer leaves the panel: it handles its own dismissal.

`Lumen.ShapedSurface` is a ready-made own surface: a layer-shell window clipped
to an SVG path (`M0 320 L320 0 L640 320 Z`), with a matching input region,
`reveal (ms)` / `dismiss (ms)` fades, `set_margin`, `set_output`, `background`,
and a `pointer_left` signal. The example uses it.

## Choosing a presenter

The panel's own tray is the presenter `tray-classic`. Pick another in
`~/.config/lumen-shell/extensions.json`:

```json
{
  "slots":    { "tray.presenter": "tray-wedge" },
  "params":   { "tray-wedge": { "height": 400 } },
  "disabled": []
}
```

If the chosen provider is missing or fails, the first available one is used.

## Params and data files

`ctx.param_int ("height")`, `param_double`, `param_bool`, `param_string` return
the value from `extensions.json` `params.<id>`, falling back to the manifest
default when absent or of the wrong type; numbers are clamped to `min`/`max`.

`ctx.path ("icon.svg")` is the absolute path of a file shipped in the
extension's folder.

## Build, cache, errors

Extensions are compiled at panel startup, and only when a source file, the
manifest, the extension API or `valac` changed; otherwise the cached `.so` in
`~/.cache/lumen-shell/extensions/` is loaded directly. Edit, then restart
lumen-panel.

Compile and load errors go to `journalctl --user -t lumen-panel` and are shown
in Settings → Extensions.

To compile by hand while iterating:

```sh
valac --library=x -X -shared -X -fPIC -X -w --pkg=lumen-ext-1 -o /tmp/x.so *.vala
```

## Crash guard

An extension that crashes the panel during `enable` is skipped for the rest of
the session. `LUMEN_SAFE_MODE=1 lumen-panel` skips all user extensions.
