# Lumen Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every piece of LumenShell UI a Vala extension, loaded at startup by a minimal core, so a user can write e.g. a completely different tray in one folder without touching Lumen sources. Compositor effects stay native Wayfire plugins (`wayfire-plugins/*`) and are out of scope.

**Architecture:** Core = `liblumen-ext` (shared library: extension API, slot registry, services) + `lumen-shell` (one host process that compiles, loads and enables extensions at startup) + `lumen-lockscreen` + `lumen-session`. Extensions are Vala `.so` modules loaded once with GModule; user extensions are compiled with `valac` at startup and cached by content hash.

**Tech Stack:** Vala 0.56, GLib/GIO/GModule 2.88, GTK 4.22, gtk4-layer-shell 1.2, json-glib 1.10, gee-0.8, Meson 1.11.

**Spec:** This plan's *Design* section (decisions agreed in conversation 2026-11-14). Decisions: extensions are Vala, loaded on start (no hot reload); compositor effects are not extensions (they stay native Wayfire plugins); `lumen-lockscreen` stays a separate core binary; no runtime cost vs. today.

## Global Constraints

- Efficiency: no per-frame work in the host.
- No interpreter or scripting runtime anywhere. Extensions are native `.so`.
- User extensions compile at startup only when their cache key changed; an unchanged extension costs one `stat` + one `dlopen`.
- Extensions are never unloaded (`Module.make_resident()`); no hot reload.
- Config filenames only via `LumenCommon.Paths` getters (CLAUDE.md L119). Config root stays `~/.config/lumen-shell/`.
- `gtk4_layer_shell_dep` before gtk4/wayland deps + `-Wl,--no-as-needed` on every target that creates layer surfaces, including `liblumen-ext` and the host (CLAUDE.md L107).
- Targets compiling `paths_source` add `lumen_datadir_c_args` (CLAUDE.md L103).
- `GLib.Object` when `using Json;` (CLAUDE.md L111).
- Wayfire IPC framing: `[u32 LE length][JSON]`, request `{"method": "...", "data": {...}}` (CLAUDE.md L114).
- Tests follow `tests/display_identity.vala`: plain `int main()` + `assert()`, declared with meson `test()`, run with `meson test -C build`.
- `junkyard/` untouched. Existing wlhooks signatures untouched (CLAUDE.md L110).
- Commit subjects: imperative, optional component prefix (`liblumen-ext: add manifest parser`).
- After each task: `meson compile -C build && meson test -C build`.

## Review Focus

1. **Two extensions define the same GType name** (both have `class Wedge`): expected — the second fails to load with a clear error, the first keeps working, the host does not abort. Pinned in Task 6 (`test_duplicate_type_rejected`).
2. **A user extension fails to compile or crashes during `enable()`** at login: expected — the rest of the shell comes up; the error is logged and shown in Settings → Extensions. Crash loop → safe mode (bundled only). Pinned in Tasks 5, 7.

---

## Design

### Process & file layout

```
liblumen-ext/            shared_library('lumen-ext-1') — namespace Lumen
  api.vala               API_VERSION, Extension, Context
  manifest.vala          Manifest, ParamDef
  ext_config.vala        ExtensionConfig (extensions.json)
  registry.vala          Registry (slots)
  compiler.vala          Compiler (valac + cache)
  loader.vala            Loader (GModule)
  slots/*.vala           slot interfaces (TrayApplet, CcModule, TrayPresenter, ...)
  services/              lumen-common services moved here over time
lumen-shell/src/main.vala   host executable (dev.lumen.shell)
extensions/<id>/            bundled extensions, built by meson as shared_module
~/.config/lumen-shell/extensions/<id>/   user extensions (compiled at startup)
~/.config/lumen-shell/extensions.json    enabled set, slot choices, param values
$XDG_CACHE_HOME/lumen-shell/extensions/<id>-<key>.so
```

`liblumen-ext` is the one deliberate exception to "lumen-common is source-level only" (CLAUDE.md L58): host and extensions must share one copy of every GType. Update CLAUDE.md in Task 1.

### Extension contract

```
<id>/manifest.json
{ "id": "tray-wedge", "name": "Wedge tray", "version": "1", "api": 1,
  "provides": ["tray.presenter"], "after": [],
  "packages": ["gtk4"],                       // extra valac --pkg, user extensions only
  "params": { "height": { "type": "int", "default": 320, "min": 100, "max": 800, "label": "Height" } } }
<id>/*.vala      must define: public Lumen.Extension lumen_extension_new ()
<id>/*           optional data files, read via ctx.file("x.svg")
```

Classes in an extension must live in a namespace named after the id (`namespace TrayWedge`) — GType names are process-global.

### Slots

`Lumen.Registry` holds `slot id → ordered list of (extension id, GLib.Object)`. A slot is declared with cardinality `ONE` (active impl chosen in `extensions.json` `"slots": {"tray.presenter": "tray-classic"}`, default = first by load order) or `MANY` (order from `extensions.json`, then load order). Slot interfaces live in `liblumen-ext/slots/` so producers and consumers share one type.

---

## Phase 1 — Core library

### Task 1: `liblumen-ext` skeleton, install, test harness

**Files:**
- Create: `liblumen-ext/api.vala`, `liblumen-ext/meson.build`, `tests/ext/api_version.vala`
- Modify: `meson.build` (add `subdir('liblumen-ext')` after the lumen-common source groups ~L180), `meson_options.txt` (`option('with_extensions', type: 'boolean', value: true)`), `CLAUDE.md` (L58/L84/L126: document liblumen-ext exception; add "Extensions" section with the contract above)

**Interfaces:**
- Produces: meson vars `lumen_ext_lib`, `lumen_ext_dep` (declare_dependency with link_with + the generated vapi dir); installed `liblumen-ext-1.so.1`, `lumen-ext-1.h`, `lumen-ext-1.vapi` + `lumen-ext-1.deps` (to `datadir/vala/vapi`), `lumen-ext-1.pc` (via `import('pkgconfig')`). `namespace Lumen { public const int API_VERSION = 1; }`.

- [ ] **Step 1: Write `tests/ext/api_version.vala`:** `int main() { assert(Lumen.API_VERSION == 1); return 0; }` and declare `test('ext-api-version', executable(..., dependencies: [lumen_ext_dep, glib_dep]))`.
- [ ] **Step 2:** `meson test -C build ext-api-version` → FAIL (dependency undefined).
- [ ] **Step 3:** `shared_library('lumen-ext-1', sources, vala_header: 'lumen-ext-1.h', vala_vapi: 'lumen-ext-1.vapi', vala_gir: none, version: '1.0.0', dependencies: [gtk4_layer_shell_dep, gtk4_dep, glib_dep, gio_dep, gmodule_dep, json_dep, gee_dep], link_args: ['-Wl,--no-as-needed'], install: true, install_dir: [true, true, get_option('datadir')/'vala/vapi'])`. `.deps` lists `gtk4 gtk4-layer-shell-0 gio-2.0 gmodule-2.0 json-glib-1.0 gee-0.8`.
- [ ] **Step 4:** test PASS; `meson install --destdir $PWD/build/stage -C build` and confirm `pkg-config --with-path build/stage/usr/local/lib64/pkgconfig --modversion lumen-ext-1` prints `1.0`.
- [ ] **Step 5:** Commit `liblumen-ext: add shared library skeleton and install vapi/pc`.

### Task 2: Manifest and extensions.json

**Files:**
- Create: `liblumen-ext/manifest.vala`, `liblumen-ext/ext_config.vala`, `tests/ext/manifest.vala`, `tests/ext/ext_config.vala`
- Modify: `lumen-common/paths.vala` (add getters), `liblumen-ext/meson.build` (compile `paths_source` with `lumen_datadir_c_args`)

**Interfaces:**
- Produces:
  - `Paths.extensions_dir() → config_dir()+"/extensions"`, `Paths.extensions_json() → config_dir()+"/extensions.json"`, `Paths.extension_cache_dir() → user_cache_dir+"/lumen-shell/extensions"`, `Paths.system_extensions_dir() → LUMEN_LIBDIR+"/lumen-shell/extensions"` (new `extern const string LUMEN_LIBDIR`, same pattern as `LUMEN_DATADIR`).
  - `public enum Lumen.ParamType { BOOL, INT, DOUBLE, STRING, ENUM, COLOR }`
  - `public class Lumen.ParamDef { string key; ParamType type; Json.Node default_value; double min; double max; string[] choices; string label; }`
  - `public class Lumen.Manifest { string id; string name; string version; int api; string[] provides; string[] after; string[] packages; Gee.List<ParamDef> params; string dir; static Manifest parse(Json.Object o, string dir) throws Lumen.ManifestError; }`
  - `public errordomain Lumen.ManifestError { MISSING_FIELD, BAD_ID, BAD_TYPE, API_MISMATCH }`
  - `public class Lumen.ExtensionConfig { static ExtensionConfig load(string path); bool is_enabled(string id, bool default_on); string? active_for(string slot); string[] order_for(string slot); Json.Node? param(string ext_id, string key); }` — missing/broken file = all defaults.

- [ ] **Step 1: Tests.** `test_parse_minimal` (id/name/version/api only → provides empty, params empty); `test_reject_bad_id` (`"Tray Wedge"` → `BAD_ID`; ids match `^[a-z][a-z0-9-]*$`); `test_api_mismatch` (`"api": 2` → `API_MISMATCH`); `test_param_defaults` (int param with min/max round-trips); `test_config_missing_file` (`load("/nonexistent")` → `is_enabled("x", true) == true`, `active_for("tray.presenter") == null`); `test_config_slots` (`{"slots":{"tray.presenter":"tray-wedge"},"disabled":["clock"]}` → `active_for == "tray-wedge"`, `is_enabled("clock", true) == false`).
- [ ] **Step 2:** run → FAIL.
- [ ] **Step 3:** implement with json-glib (`Json.Parser.load_from_file`), pattern of `PanelConfig.parse()` (`lumen-panel/src/panel_config.vala:61-73`).
- [ ] **Step 4:** run → PASS.
- [ ] **Step 5:** Commit `liblumen-ext: add manifest and extensions.json parsing`.

### Task 3: Slot registry

**Files:** Create `liblumen-ext/registry.vala`, `tests/ext/registry.vala`

**Interfaces:**
- Produces:
  - `public enum Lumen.Cardinality { ONE, MANY }`
  - `public class Lumen.Registry : GLib.Object { void declare(string slot, Cardinality c); void provide(string slot, string ext_id, GLib.Object impl); void withdraw(string ext_id); GLib.Object? active(string slot); Gee.List<GLib.Object> all(string slot); signal void changed(string slot); }`
  - Constructed with an `ExtensionConfig` for `active_for` / `order_for`.

- [ ] **Step 1: Tests.** `test_one_uses_config_choice` (two providers, config picks second → `active()` is second); `test_one_defaults_to_first`; `test_many_respects_order` (config order `["b","a"]` + unlisted `c` → `[b,a,c]`); `test_withdraw_emits_changed`; `test_undeclared_slot_provide_is_rejected` (returns without crash, `all()` empty, warning logged).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: add slot registry`.

### Task 4: Extension base and Context

**Files:** Create `liblumen-ext/extension.vala`, `tests/ext/context.vala`

**Interfaces:**
- Consumes: `Manifest`, `Registry`, `ExtensionConfig`.
- Produces:
  - `public abstract class Lumen.Extension : GLib.Object { public abstract void enable(Context ctx) throws Error; public virtual void disable() {} }`
  - `public class Lumen.Context : GLib.Object { string id; string dir; Manifest manifest; Registry registry; Gtk.Application app; string file(string rel) throws Error /* reads dir/rel */; int param_int(string key); double param_double(string key); bool param_bool(string key); string param_string(string key); void provide(string slot, GLib.Object impl) /* registry.provide(slot, id, impl) */; void own(GLib.Object o); void own_handler(GLib.Object src, ulong handler_id); void own_source(uint source_id); void release() /* disconnects handlers, removes sources, drops owned refs, registry.withdraw(id) */ }`
  - Param resolution: `extensions.json` value → manifest default; clamp to min/max.

- [ ] **Step 1: Tests.** `test_param_falls_back_to_default`; `test_param_clamped` (config 99, max 16 → 16); `test_release_disconnects` (own_handler on a test object signal; after `release()`, emitting doesn't run the handler); `test_release_withdraws_slots`; `test_file_reads_relative` (temp dir).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: add Extension base and Context`.

### Task 5: Compiler (valac + cache)

**Files:** Create `liblumen-ext/compiler.vala`, `tests/ext/compiler.vala`, `tests/ext/fixtures/hello/{manifest.json,hello.vala}`

**Interfaces:**
- Produces:
  - `public class Lumen.Compiler : GLib.Object { Compiler(string cache_dir, string vapidir, string pkg_config_path); string cache_key(Manifest m) throws Error; string so_path(Manifest m) throws Error; async string build(Manifest m, Cancellable? c) throws Lumen.CompileError /* returns .so path */; }`
  - `public errordomain Lumen.CompileError { VALAC_MISSING, FAILED }` — `FAILED` message = valac stderr (trimmed to 4 KiB).
  - `cache_key` = SHA-256 over: sorted relative paths + contents of every `*.vala`/`*.vapi` in `m.dir`, `manifest.json`, `API_VERSION`, liblumen-ext `version`, `valac --version` output (captured once per process). First 16 hex chars.
  - `build`: if `so_path` exists → return it. Else run `valac --vapidir=<vapidir> --pkg=lumen-ext-1 [--pkg=X for X in m.packages] -X -shared -X -fPIC -X -O2 -X -w -o <tmp> <sources>` with `PKG_CONFIG_PATH` set, in a temp dir; atomic rename to `so_path`; delete other `<id>-*.so`.
  - Host passes `vapidir`/`pkg_config_path` from compile-time constants `LUMEN_EXT_VAPIDIR` / `LUMEN_EXT_PCDIR` (meson `c_args`), overridable by env `LUMEN_EXT_VAPIDIR`/`LUMEN_EXT_PCDIR` (set in `meson.add_devenv()` to the build tree).

- [ ] **Step 1: Tests.** `test_key_stable` (same dir twice → same key); `test_key_changes_on_edit` (copy fixture to temp, append a comment → different key); `test_build_hello` (builds fixture, file exists, `Module.open` + `symbol("lumen_extension_new")` succeeds); `test_build_cached` (second build doesn't spawn valac: mtime unchanged); `test_build_error_message` (fixture with syntax error → `FAILED` containing `error:`). Declare with `env: {'LUMEN_EXT_VAPIDIR': <build vapi dir>, 'LUMEN_EXT_PCDIR': <meson-uninstalled dir>}` (`meson` writes `lumen-ext-1-uninstalled.pc` via `pkgconfig.generate(..., uninstalled_variables)`).
- [ ] **Step 2:** FAIL. **Step 3:** implement with `GLib.Subprocess` + `communicate_utf8_async`. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: compile user extensions with valac and cache by content hash`.

### Task 6: Loader

**Files:** Create `liblumen-ext/loader.vala`, `tests/ext/loader.vala`, fixtures `tests/ext/fixtures/{dupe_a,dupe_b,throws}/`

**Interfaces:**
- Consumes: `Manifest`, `Compiler`, `Extension`.
- Produces:
  - `public class Lumen.Discovered { Manifest manifest; bool bundled; string? so_path /* bundled: prebuilt */; }`
  - `public class Lumen.Loader : GLib.Object { static Gee.List<Discovered> discover(string[] dirs) /* later dirs override earlier by id; skips invalid manifests with warning */; Extension? load(string so_path) throws Lumen.LoadError; }`
  - `public errordomain Lumen.LoadError { OPEN, NO_ENTRY, TYPE_CLASH }`
  - `load`: `Module.open(path, BIND_LAZY | BIND_LOCAL)`; `symbol("lumen_extension_new")`; before calling, read the optional exported `const char* lumen_extension_types[]` (NULL-terminated, emitted by a 1-line convention in the template: `public const string[] lumen_extension_types = {"TrayWedgeExtension", ...}`) and if any `Type.from_name()` already exists → `TYPE_CLASH` without calling into the module; then `make_resident()`.
  - Topological enable order by `after` (cycle → those extensions skipped with error).
  - Bundled extensions ship `<system_extensions_dir>/<id>/{manifest.json, lib<id>.so, data files}`; user dir = `<extensions_dir>/<id>/` with sources.

- [ ] **Step 1: Tests.** `test_discover_user_overrides_system`; `test_load_fixture` (returns non-null `Extension`); `test_duplicate_type_rejected` (load dupe_a OK, dupe_b → `TYPE_CLASH`, process alive); `test_missing_entry` → `NO_ENTRY`; `test_order_after` (`b.after=[a]` → a before b); `test_cycle_skipped`. Fixtures built by meson `shared_module` against `lumen_ext_dep`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: load extension modules via GModule`.

## Phase 2 — Host and settings

### Task 7: `lumen-shell` host

**Files:**
- Create: `lumen-shell/src/main.vala`, `lumen-shell/src/safe_mode.vala`, `lumen-shell/meson.build`, `data/systemd/lumen-shell.service`, `tests/ext/safe_mode.vala`
- Modify: root `meson.build` (subdir, unit install next to existing units ~L612), `start-lumenshell` / session unit wiring (same mechanism that starts lumen-panel today)

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces:
  - `Gtk.Application("dev.lumen.shell")`. `startup`: `ExtensionConfig.load` → `Registry` declares built-in slots (`tray.presenter` ONE, `tray.applet` MANY, `cc.module` MANY, `panel` ONE, plus later phases) → `Loader.discover([system_extensions_dir, extensions_dir])` → user extensions: `Compiler.build` all in parallel (`async` + counter) → load in `after` order → `enable(ctx)` each inside try/catch (`Error` → `ctx.release()`, logged, recorded in `$XDG_RUNTIME_DIR/lumen-shell/status.json` as `{"<id>":{"state":"failed","error":"..."}}`).
  - `SafeMode`: `public class SafeMode { static bool should_enter(string state_path, int64 now_s) ; static void record_start(string state_path, int64 now_s); static void record_clean(string state_path); }` — 3 starts within 60 s without `record_clean` (called 10 s after successful startup) → safe mode = load bundled extensions only + notify via existing notification D-Bus.
  - systemd user unit `Restart=on-failure`.
- [ ] **Step 1: Tests** `tests/ext/safe_mode.vala`: `test_three_quick_starts_enter`, `test_clean_resets`, `test_old_starts_ignored` (starts 120 s ago don't count).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; manual: install, log in, `journalctl --user -u lumen-shell` shows `loaded 0 extensions`, no errors.
- [ ] **Step 5:** Commit `lumen-shell: add extension host`.

### Task 8: Settings → Extensions page

**Files:** Create `lumen-settings/src/pages/extensions_page.vala`; modify `lumen-settings/src/main.vala:54-71` (register in "LumenShell"), `lumen-settings/src/wayfire/plugin_page.vala` (extract `build_row` into a static helper usable with a `ParamDef`→`OptionDef` adapter)

**Interfaces:**
- Consumes: `Loader.discover`, `Manifest`, `ExtensionConfig`, status.json from Task 7.
- Produces: page id `"extensions"`; one `Adw.ExpanderRow` per extension (switch = enabled, subtitle = failed error if any, children = param rows); writes `extensions.json` atomically; `restart_target()` = `"lumen-shell"`.
- [ ] **Step 1: Test** `tests/ext/param_rows.vala`: adapter maps each `ParamType` to the matching `OptionType` (BOOL→BOOL, INT→INT with min/max, ENUM→INT+choices, COLOR→COLOR).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; manual: toggle an extension, restart host, state persists.
- [ ] **Step 5:** Commit `lumen-settings: add Extensions page`.

## Phase 3 — Panel and tray as extensions (acceptance: new tray)

### Task 9: Move panel services into liblumen-ext; panel becomes an extension

**Files:**
- Move: lumen-common sources the panel uses (`logind`, `wifi_service`/`nmcli`, `bluetooth_service`/`btctl`, `sound_*`, `proc`, `dbus_cli`, `radio_state`, `tray_applets`) into `liblumen-ext/services/` (keep `LumenCommon` namespace; other apps keep compiling them from source until they become extensions — meson source groups point at the new path). Panel-only services (`BatteryService`, `PowerProfile`, `BrightnessService`, `SniWatcher`) → `liblumen-ext/services/` too, exposed as `Lumen.Services.get().battery` etc. (lazily constructed singletons — no service starts unless an extension asks for it).
- Move: `lumen-panel/src/**` → `extensions/panel/src/**`; `App` (`main.vala`) becomes `Panel.PanelExtension : Lumen.Extension`; `Gtk.Application` comes from `ctx.app`; resources compiled into the module (`gnome.compile_resources` linked into the shared_module).
- Create: `liblumen-ext/slots/{tray_applet,cc_module}.vala` — `Lumen.TrayApplet` = old `ITrayApplet` (`tray.vala:3-5`), `Lumen.CcModule` = old `IControlModule` (`control_module.vala:1-6`) plus `public abstract int home_row { get; }` and `public abstract bool home_paired { get; }` so `build_home()` can lay out unknown modules. Built-in applets (systray, wifi, bluetooth, battery, sound, clock, exit) register with `ctx.provide("tray.applet", …)` / `("cc.module", …)`.
- Remove the `LumenTray.CATALOG` gate: `PanelConfig.tray_enabled_order()` uses `registry.all("tray.applet")` ids; lumen-settings panel page reads the catalog from discovered manifests' `provides`.
- Delete: `lumen-panel` executable target and its unit; `PanelService` D-Bus moves into the panel extension unchanged (`org.lumenshell.Panel1`).

- [ ] **Step 1: Test** `tests/ext/tray_order.vala`: given registry with applets `[wifi, clock, myext]` and config `tray.order=[clock]`, `tray.disabled=[wifi]` → `[clock, myext]` (unknown ids are no longer dropped).
- [ ] **Step 2:** FAIL. **Step 3:** move + adapt. **Step 4:** PASS; manual: panel looks and behaves identically (multi-monitor, hidden/push modes, tray, control center, SNI, D-Bus ToggleTray).
- [ ] **Step 5:** Commit `panel: run lumen-panel as a bundled extension`.

### Task 10: Tray presenter slot + `tray-classic`

**Files:**
- Create: `liblumen-ext/slots/tray_presenter.vala`, `extensions/tray-classic/…` (moved `widgets/tray.vala`, `tray_reveal.vala`, `components/control_center/**`)
- Modify: `extensions/panel/src/panel_window.vala:55-92,149-188,214-259`, `extensions/panel/src/main.vala` (make_tray)

**Interfaces:**
- Produces:
```vala
public interface Lumen.TrayPresenter : GLib.Object {
    // Called once per panel window that hosts a tray. Return a widget to place in the panel strip, or null
    // if this presenter lives entirely in its own surfaces.
    public abstract Gtk.Widget? attach(Lumen.TrayModel model, Gtk.Window panel_window);
    public abstract void detach(Gtk.Window panel_window);
    public abstract void toggle();
    public abstract void collapse();
    public abstract bool expanded { get; }
    // Input rects in panel_window surface coordinates that must stay clickable while expanded/animating.
    public abstract Cairo.RectangleInt[] input_rects(Gtk.Window panel_window);
    public signal void expanded_changed();
}
public class Lumen.TrayModel : GLib.Object {
    public Gee.List<Lumen.TrayApplet> applets;   // ordered, filtered by config
    public Gee.List<Lumen.CcModule> modules;
    public signal void changed();
}
```
- Panel: `make_tray()` → `registry.active("tray.presenter")`; `update_input_region()` unions strip rect + `presenter.input_rects()` instead of computing the tray rect itself; ToggleTray → `presenter.toggle()`; push mode keeps using `PeekIpc` (panel-push stays a native plugin).
- `tray-classic` = current TrayBar/TrayReveal/ControlCenter unchanged in look; constants (`BOX_RADIUS`, `WIDTH/HEIGHT`, `DURATION_US`) become manifest params with today's values as defaults.
- [ ] **Step 1:** Manual parity checklist `docs/extensions/parity-tray.md` (expand/collapse, detail pages, Escape, input passes through outside tray, multi-monitor `tray_all_monitors`), run on current build.
- [ ] **Step 2–4:** implement; checklist matches.
- [ ] **Step 5:** Commit `extensions: split tray presentation into tray-classic presenter`.

### Task 11: `tray-wedge` example — user-compiled, own surface

**Files:**
- Create: `data/examples/extensions/tray-wedge/{manifest.json, wedge.vala, wedge.svg}`, `docs/extensions/README.md` (authoring guide: contract, slots, params, build errors, safe mode), `liblumen-ext/shape.vala`
- Modify: root `meson.build` (install examples to `datadir/lumenshell/examples/extensions`)

**Interfaces:**
- Produces: `public class Lumen.ShapedSurface : Gtk.Window { ShapedSurface(Gtk.Application app, string ns, Lumen.Edge anchor, int w, int h, string svg_path); Gtk.Widget child; void reveal(int ms); void dismiss(int ms); signal void pointer_left(); }` — clips with `Gsk.Path.parse` + `push_fill` (precedent: lumen-desktop `FolderShape`/`WidgetShape`); input region = path rasterised into 4 px-tall horizontal bands with `Gsk.Path.in_fill`, recomputed on size change only.
- Wedge: `attach()` returns null (no strip widget); `toggle()` (tray click / ToggleTray) → `ShapedSurface.reveal`, `pointer_left` → `dismiss`; content = `TrayModel.modules` home tiles laid out in the inscribed rectangle.
- [ ] **Step 1: Test** `tests/ext/shape_bands.vala`: triangle `M0 320 L320 0 L640 320 Z`, band 4 px → region contains (320,300), excludes (10,10), band count == 80.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; manual acceptance: copy example to `~/.config/lumen-shell/extensions/`, set `slots.tray.presenter = "tray-wedge"`, restart host → compiles once (second restart: no valac in `journalctl`), ToggleTray shows the triangle tray; tiles work; no Lumen source changed.
- [ ] **Step 5:** Commit `extensions: add tray-wedge example and authoring guide`.

---

## Phase 4 (TL;DR) — remaining apps become extensions

Same recipe as Task 9 for each: move `src/**` to `extensions/<id>/`, `App` → `Lumen.Extension`, shared `ctx.app`, layer-shell windows unchanged, delete the executable + unit, move the lumen-common sources it uses into `liblumen-ext/services/`.

| App | Becomes | Notes |
|---|---|---|
| lumen-drawer | `drawer` extension | Reveal stays with the native peek plugins (`lumen-peek/*` IPC unchanged). Shares `ToplevelStore` with panel (dedupe the two `toplevels.vala`). |
| lumen-osd | `osd` | Brightness/volume watchers become shared services (one poller instead of two). `lumen-osdctl` CLI stays, talks D-Bus. |
| lumen-notifications | `notifications` | Owns `org.freedesktop.Notifications`; slot `notification.presenter` (ONE) so the popup look is replaceable like the tray. |
| lumen-corner | `hot-corner` | Its ring widget is a `ShapedSurface`. |
| lumen-desktop | `desktop` | `FolderShape` moves into `Lumen.ShapedSurface`. |
| lumen-polkit-agent | `polkit` | Same process is fine (polkit auth goes via the agent's own helper, not our buffer); keep the dialog behind slot `auth.dialog`. |
| lumen-settings | stays an app | Reads manifests; per-extension settings pages via optional `Lumen.SettingsProvider` slot. |
| **Core (stays)** | `lumen-shell`, `liblumen-ext`, `wayfire-plugins/*`, `lumen-session`, `lumen-lockscreen`, `lumen-lockctl`, `lumen-osdctl` | Lockscreen stays separate so no extension shares a process with the password buffer. |

End state: one GTK process for all shell UI (≈ one GTK/GL context instead of seven).
