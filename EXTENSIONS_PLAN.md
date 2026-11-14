# Lumen Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every piece of LumenShell UI and every compositor effect a single-language (Vala + GLSL) extension, loaded at startup by a minimal core, so a user can write e.g. a new drawer reveal effect or a completely different tray in one folder without touching Lumen sources.

**Architecture:** Core = `liblumen-ext` (shared library: extension API, slot registry, services, Wayfire connection, effect client) + `lumen-shell` (one host process that compiles, loads and enables extensions at startup) + `lumen-fx` (one generic Wayfire plugin that executes a fixed set of effect commands on the compositor clock) + `lumen-lockscreen` + `lumen-session`. Extensions are Vala `.so` modules loaded once with GModule; user extensions are compiled with `valac` at startup and cached by content hash. Compositor work is expressed as declarative commands (shader + mesh + snapshot/blur textures + view transforms + layer visibility + hot-zones + tweens); no per-frame IPC.

**Tech Stack:** Vala 0.56, GLib/GIO/GModule 2.88, GTK 4.22, gtk4-layer-shell 1.2, json-glib 1.10, gee-0.8, Meson 1.11, Wayfire 0.10.1 (C++17, GLES via `OpenGL::program_t`), wlroots-0.19, GLSL ES 1.00.

**Spec:** This plan's *Design* section (decisions agreed in conversation 2026-11-14). Decisions: extensions are Vala, loaded on start (no hot reload); compositor reach = fixed `lumen-fx` command set, extended in lumen-fx when a new need appears (no C++ in extensions, no Vala bindings to Wayfire); `lumen-lockscreen` stays a separate core binary; no runtime cost vs. today.

## Global Constraints

- Efficiency: no per-frame IPC, no per-frame work in the host. An effect's per-frame cost must equal the native plugin it replaces (same shader, same draw calls). IPC happens only on start/stop/retarget of an animation.
- No interpreter or scripting runtime anywhere. Extensions are native `.so`.
- User extensions compile at startup only when their cache key changed; an unchanged extension costs one `stat` + one `dlopen`.
- Extensions are never unloaded (`Module.make_resident()`); no hot reload.
- Config filenames only via `LumenCommon.Paths` getters (CLAUDE.md L119). Config root stays `~/.config/lumen-shell/`.
- `gtk4_layer_shell_dep` before gtk4/wayland deps + `-Wl,--no-as-needed` on every target that creates layer surfaces, including `liblumen-ext` and the host (CLAUDE.md L107).
- Targets compiling `paths_source` add `lumen_datadir_c_args` (CLAUDE.md L103).
- `GLib.Object` when `using Json;` (CLAUDE.md L111).
- Wayfire IPC framing: `[u32 LE length][JSON]`, request `{"method": "...", "data": {...}}` (CLAUDE.md L114).
- Shaders: GLSL ES `#version 100`, same as `wayfire-plugins/curtain-peek/src/curtain-peek.cpp:105-187`.
- Tests follow `tests/display_identity.vala`: plain `int main()` + `assert()`, declared with meson `test()`, run with `meson test -C build`.
- `junkyard/` untouched. Existing wlhooks signatures untouched (CLAUDE.md L110).
- Commit subjects: imperative, optional component prefix (`liblumen-ext: add manifest parser`).
- After each task: `meson compile -C build && meson test -C build`.

## Review Focus

1. **Two extensions define the same GType name** (both have `class Wedge`): expected — the second fails to load with a clear error, the first keeps working, the host does not abort. Pinned in Task 6 (`test_duplicate_type_rejected`).
2. **A user extension fails to compile or crashes during `enable()`** at login: expected — the rest of the shell comes up; the error is logged and shown in Settings → Extensions. Crash loop → safe mode (bundled only). Pinned in Tasks 5, 13.
3. **The host dies while an effect is mid-animation (drawer half-open, screen pushed up 300 px)**: expected — lumen-fx destroys every object owned by that IPC client and restores views/layers. Pinned in Task 8 (`disconnect_restores_state`).
4. **Shader compile error in a user effect**: expected — `node/create` replies with the GLSL info log, nothing is drawn, the drawer still opens (instant fallback). Pinned in Task 11.
5. **Monitor hotplug while effects/zones exist**: expected — objects bound to a removed output are destroyed and an `output-removed` event is sent; zones with `output: "all"` re-attach to new outputs. Pinned in Tasks 9, 11.

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
  wf_connection.vala     WayfireConnection (persistent, async, events)
  fx.vala                Fx, Zone, ViewGroup, Node (lumen-fx client)
  slots/*.vala           slot interfaces (TrayApplet, CcModule, TrayPresenter, DrawerReveal, ...)
  services/              lumen-common services moved here over time
lumen-shell/src/main.vala   host executable (dev.lumen.shell)
wayfire-plugins/lumen-fx/   generic effect plugin
extensions/<id>/            bundled extensions, built by meson as shared_module
~/.config/lumen-shell/extensions/<id>/   user extensions (compiled at startup)
~/.config/lumen-shell/extensions.json    enabled set, slot choices, param values
$XDG_CACHE_HOME/lumen-shell/extensions/<id>-<key>.so
```

`liblumen-ext` is the one deliberate exception to "lumen-common is source-level only" (CLAUDE.md L58): host and extensions must share one copy of every GType. Update CLAUDE.md in Task 1.

### Extension contract

```
<id>/manifest.json
{ "id": "curtain", "name": "Curtain", "version": "1", "api": 1,
  "provides": ["drawer.reveal"], "after": [],
  "packages": ["gtk4"],                       // extra valac --pkg, user extensions only
  "params": { "folds": { "type": "int", "default": 6, "min": 1, "max": 16, "label": "Folds" } } }
<id>/*.vala      must define: public Lumen.Extension lumen_extension_new ()
<id>/*.glsl      optional, read via ctx.file("x.glsl")
```

Classes in an extension must live in a namespace named after the id (`namespace Curtain`) — GType names are process-global.

### lumen-fx command set (all methods take `client_interface_t*`; every object is owned by the calling client and destroyed on disconnect)

| Method | Data | Reply / events |
|---|---|---|
| `lumen-fx/hello` | `{}` | `{"api":1,"outputs":[{name,x,y,w,h,scale}],"active":name}` |
| `lumen-fx/watch` | `{}` | subscribes client to events |
| `lumen-fx/verb/claim` | `{"name":"lumen-peek/toggle"}` | registers that IPC method; calls arrive as event `{"event":"verb","name","data"}` |
| `lumen-fx/zone/create` | `{"id","output":"<name>"\|"all","edge":"top\|bottom\|left\|right","size":px,"delay_ms"}` | events `zone-enter`/`zone-leave` `{"id","output"}` |
| `lumen-fx/views/create` | `{"id","match":{"app_id"?,"except_app_id"?,"layers":[...]},"follow_new":bool}` | view group |
| `lumen-fx/views/set` | `{"id","props":{"tx","ty","sx","sy","alpha"},"visible"?:bool,"focus"?:bool}` | |
| `lumen-fx/views/animate` | `{"id","to":{props},"duration_ms","curve":"linear\|circle\|sigmoid"}` | event `anim-done {"id"}` |
| `lumen-fx/layers/set` | `{"output","layers":[...],"visible":bool}` | restored on destroy/disconnect |
| `lumen-fx/node/create` | `{"id","output","above_layer":"overlay\|top\|...","vert"?,"frag","mesh":{"nu","nv"}?,"textures":{"<sampler>":{"snapshot":{"layers":[...]},"blur"?:levels}},"uniforms":{name: float\|[f,f]\|[f,f,f]\|[f,f,f,f]}}` | `{"ok":true}` or `{"error":"<GLSL log>"}` |
| `lumen-fx/node/set` | `{"id","uniforms":{...}}` | |
| `lumen-fx/node/animate` | `{"id","to":{uniforms},"duration_ms","curve"}` | event `anim-done {"id"}` |
| `lumen-fx/destroy` | `{"id"}` | any object kind; restores what it changed |

Built-in shader inputs: attribute `grid` (vec2 0..1, mesh vertex), uniform `matrix` (output projection), `u_resolution` (vec2). Without `vert`, a default vertex shader maps `grid` to the output rect and passes `v_uv`. Animations tween on the per-output `OUTPUT_EFFECT_PRE` hook; the hook is removed when no animation is running (zero idle cost).

### Slots

`Lumen.Registry` holds `slot id → ordered list of (extension id, GLib.Object)`. A slot is declared with cardinality `ONE` (active impl chosen in `extensions.json` `"slots": {"drawer.reveal": "curtain"}`, default = first by load order) or `MANY` (order from `extensions.json`, then load order). Slot interfaces live in `liblumen-ext/slots/` so producers and consumers share one type.

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

- [ ] **Step 1: Tests.** `test_parse_minimal` (id/name/version/api only → provides empty, params empty); `test_reject_bad_id` (`"Curtain Peek"` → `BAD_ID`; ids match `^[a-z][a-z0-9-]*$`); `test_api_mismatch` (`"api": 2` → `API_MISMATCH`); `test_param_defaults` (int param with min/max round-trips); `test_config_missing_file` (`load("/nonexistent")` → `is_enabled("x", true) == true`, `active_for("drawer.reveal") == null`); `test_config_slots` (`{"slots":{"drawer.reveal":"slide"},"disabled":["curtain"]}` → `active_for == "slide"`, `is_enabled("curtain", true) == false`).
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
  - `load`: `Module.open(path, BIND_LAZY | BIND_LOCAL)`; `symbol("lumen_extension_new")`; before calling, read the optional exported `const char* lumen_extension_types[]` (NULL-terminated, emitted by a 1-line convention in the template: `public const string[] lumen_extension_types = {"CurtainExtension", ...}`) and if any `Type.from_name()` already exists → `TYPE_CLASH` without calling into the module; then `make_resident()`.
  - Topological enable order by `after` (cycle → those extensions skipped with error).
  - Bundled extensions ship `<system_extensions_dir>/<id>/{manifest.json, lib<id>.so, *.glsl}`; user dir = `<extensions_dir>/<id>/` with sources.

- [ ] **Step 1: Tests.** `test_discover_user_overrides_system`; `test_load_fixture` (returns non-null `Extension`); `test_duplicate_type_rejected` (load dupe_a OK, dupe_b → `TYPE_CLASH`, process alive); `test_missing_entry` → `NO_ENTRY`; `test_order_after` (`b.after=[a]` → a before b); `test_cycle_skipped`. Fixtures built by meson `shared_module` against `lumen_ext_dep`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: load extension modules via GModule`.

## Phase 2 — Compositor

### Task 7: Persistent Wayfire connection

**Files:** Create `liblumen-ext/wf_connection.vala`, `tests/ext/wf_connection.vala`

**Interfaces:**
- Produces: `public class Lumen.WayfireConnection : GLib.Object { static WayfireConnection? open_default() /* socket path = LumenCommon.WayfireIpc.socket_path() */; WayfireConnection.for_stream(IOStream s) /* tests */; async Json.Object call(string method, Json.Object data, Cancellable? c = null) throws Lumen.IpcError; void call_noreply(string method, Json.Object data); signal void event(string name, Json.Object data); signal void closed(); }`
- `public errordomain Lumen.IpcError { CLOSED, TIMEOUT, REMOTE }` — reply containing `"error"` → `REMOTE`; no reply in 2000 ms → `TIMEOUT` (fixes the "wedged compositor freezes GTK thread" ROADMAP item for new code).
- Demux: one async read loop; a message with an `"event"` key → `event` signal; otherwise resolves the oldest pending call (Wayfire replies in order).

- [ ] **Step 1: Tests** over a `SocketConnection` pair from `socketpair` (fake server in-test): `test_call_roundtrip`; `test_event_interleaved` (server sends event then reply → both delivered, call gets reply); `test_remote_error`; `test_timeout` (server silent → `TIMEOUT` within 2.5 s); `test_closed_fails_pending`.
- [ ] **Step 2:** FAIL. **Step 3:** implement framing per CLAUDE.md L114. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: add persistent async Wayfire IPC connection`.

### Task 8: `lumen-fx` plugin skeleton — ownership, hello, watch, verbs

**Files:**
- Create: `wayfire-plugins/lumen-fx/{meson.build, metadata/wayfire-lumen-fx.xml, src/lumen-fx.cpp, src/objects.hpp}`, `tests/fx/run.sh`, `tests/fx/fx_client.vala`, `tests/fx/wayfire-test.ini`
- Modify: root `meson.build:642-680` (option `with_lumen_fx`, default true), `meson_options.txt`

**Interfaces:**
- Produces:
  - Plugin `wayfire-lumen-fx`, a `wf::plugin_interface_t` (global, not per-output) holding `std::map<client_interface_t*, std::map<std::string, std::unique_ptr<fx_object_t>>>`.
  - `struct fx_object_t { virtual ~fx_object_t() = default; /* destructor restores everything it changed */ };`
  - Methods registered with `method_callback_full` (`/usr/include/wayfire/plugins/ipc/ipc-method-repository.hpp:53,68`): `hello`, `watch`, `verb/claim`, `destroy`. Connect `client_disconnected_signal` (:39) → erase that client's map (destructors restore state) and unregister its claimed verbs.
  - `verb/claim` → `{"error":"taken"}` if `ipc_repo` already has the method.
  - Event helper `void emit(client_interface_t*, std::string name, wf::json_t data)` → `send_json({"event": name, ...data})`.
- Integration harness `tests/fx/run.sh`: starts `WLR_BACKENDS=headless WLR_RENDERER=gles2 wayfire -c tests/fx/wayfire-test.ini` with `[core] plugin_path_prefix=<build>/wayfire-plugins` and plugins `ipc lumen-fx`, waits for socket, runs the given test client, kills wayfire. Registered as `test('fx-<name>', run.sh, args: [client], suite: 'fx')`; skipped (exit 77) if `wayfire` missing or EGL unavailable.

- [ ] **Step 1: Tests** in `fx_client.vala` mode `skeleton`: `hello` returns `api == 1` and ≥1 output; `verb/claim lumen-peek/toggle` OK, then a *second* connection calling `lumen-peek/toggle` makes the first receive event `verb`; second claim of same name → `REMOTE taken`; **`disconnect_restores_state`**: client A claims verb, closes; client B can now claim it.
- [ ] **Step 2:** `meson test -C build --suite fx` → FAIL.
- [ ] **Step 3:** implement; JSON via `wf::json_t` (`/usr/include/wayfire/nonstd/json.hpp`).
- [ ] **Step 4:** PASS.
- [ ] **Step 5:** Commit `lumen-fx: add generic effect plugin skeleton with client-owned objects`.

### Task 9: Hot-zones

**Files:** Modify `wayfire-plugins/lumen-fx/src/lumen-fx.cpp`; create `wayfire-plugins/lumen-fx/src/zone.hpp`; test mode `zones` in `tests/fx/fx_client.vala`

**Interfaces:**
- Produces: `zone/create` per Design table. Implemented on `wf::post_input_event_signal<wlr_pointer_motion_event>` (`signal-definitions.hpp:167`) reading cursor position; edge rect = output layout geometry inset by `size`; enter fires after cursor stays `delay_ms` (wf::wl_timer), leave fires immediately. One shared motion connection for all zones, connected only while ≥1 zone exists. Output removal destroys zones bound to that output and emits `output-removed {"output"}`; `"all"` zones attach to new outputs on `output-added`.

- [ ] **Step 1: Tests:** create bottom zone; warp pointer via `wlr` headless input is unavailable → test uses the plugin's debug method `lumen-fx/debug/pointer {"x","y"}` (compiled only with `-DLUMEN_FX_DEBUG`, set for the test build) → expect `zone-enter` after delay, `zone-leave` on exit; destroy zone → no more events.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `lumen-fx: add edge hot-zones`.

### Task 10: View groups and layer visibility

**Files:** Create `wayfire-plugins/lumen-fx/src/views.hpp`, `src/anim.hpp`, `tests/fx/anim_test.cpp`, `tests/fx/dummy_window.vala`; modify `lumen-fx.cpp`; test mode `views`

**Interfaces:**
- Produces:
  - `anim.hpp` (header-only, pure): `float lumen_fx::ease(std::string_view curve, float t)` (`linear`, `circle`, `sigmoid` — same formulas as `/usr/include/wayfire/util/duration.hpp:11-24`, reuse `wf::animation::smoothing` directly if linkable); `struct tween_t { std::vector<float> from, to; int64_t start_us, dur_us; std::string curve; std::vector<float> at(int64_t now_us) const; bool done(int64_t now_us) const; }`.
  - `views/create|set|animate` per Design. Each matched view gets a `wf::scene::view_2d_transformer_t` named `lumen-fx-<client>-<id>` (pattern: `panel-push.cpp:206-236`, `slide-peek.cpp` begin/end_transform_update). `follow_new` hooks view-mapped like `panel-push.cpp:102`. `visible` → `wf::scene::set_node_enabled(view->get_root_node(), v)`; `focus` → same call as `slide-peek.cpp:410`. Per-view unmap drops tracking. Destructor removes transformers and re-enables nodes.
  - `layers/set` → `set_node_enabled(output->node_for_layer(L), v)`; destructor restores original state.
  - Animations: one `OUTPUT_EFFECT_PRE` hook per output with live tweens, added on first tween, removed when last finishes; emits `anim-done`.
- [ ] **Step 1: Tests.** `anim_test.cpp` (meson `test('fx-anim', executable(...))`, no wayfire needed): `ease("linear",0.5)==0.5`; `ease("circle",0)==0 && ease("circle",1)==1`; `tween.at(start+dur/2)` for linear `[0]→[10]` == `[5]`; `done()` true at end. Integration mode `views`: run the test toplevel `tests/fx/dummy_window.vala` (GTK window with app_id `fx-dummy`); create group matching it, `views/set ty=100`, query `window-rules/view-info` is not geometry of transform → assert via `lumen-fx/debug/view-transform {"app_id"}` returning current translation; animate → `anim-done` arrives within duration+200 ms; disconnect → transform removed.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `lumen-fx: add view groups, layer visibility and compositor-clock tweens`.

### Task 11: Effect nodes — shaders, mesh, snapshot, blur

**Files:** Create `wayfire-plugins/lumen-fx/src/node.hpp`; modify `lumen-fx.cpp`; test mode `nodes`

**Interfaces:**
- Produces: `node/create|set|animate` per Design.
  - Snapshot: for `{"snapshot":{"layers":[...]}}` disable every non-listed layer on that output, run the capture exactly as `slide-peek.cpp:487-518` (`auxilliary_buffer_t`, `gen_render_instances`, `render_pass_t::run`), restore. Captured once at create; `node/set {"recapture": true}` re-captures.
  - Blur: `"blur": levels` (1..8) builds the blit pyramid from `zoom-peek.cpp:484-524` once at create, bound as that sampler.
  - Program: `OpenGL::program_t::compile(vert, frag)` inside `wf::gles::run_in_context_if_gles`; on failure reply `{"error": <info log>}` and create nothing (capture `glGetShaderInfoLog`; `program_t::compile` aborts on error in some builds → compile manually with `glCreateShader`/`glCompileShader` first to validate, then hand sources to `program_t`).
  - Render: scene node inserted with `wf::scene::add_front(output->node_for_layer(above_layer), node)`; render instance uses `data.pass->custom_gles_subpass` exactly like `curtain-peek.cpp:259-361`: projection `render_target_orthographic_projection`, texture units 0..n via `set_active_texture` + `glActiveTexture`/`uniform1i`, `attrib_pointer("grid",...)` over the grid from `curtain_build_grid(nu,nv)` (`curtain-peek.cpp:190-206`; default 1×1 quad), scissor per damage box, `glDrawArrays`.
  - Uniform types: float, vec2/3/4 from JSON number/array length. `u_resolution` set automatically.
  - Damage: `damage_whole()` only on frames where a tween is live or after `node/set`; zero cost while static.
  - Non-GLES renderer: `node/create` replies `{"error":"no-gles"}`.
- [ ] **Step 1: Tests (mode `nodes`):** bad GLSL → `REMOTE` containing `ERROR`; valid frag (`gl_FragColor = vec4(u_c,1.0)`) with uniform `u_c` → OK; `node/animate` → `anim-done`; snapshot with `layers:["workspace"]` → OK; output removal (headless `wlr` output destroy via debug `lumen-fx/debug/remove-output`) → `output-removed` event and node gone (`destroy` → `{"error":"unknown id"}`).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `lumen-fx: add shader effect nodes with snapshot and blur textures`.

### Task 12: Vala effect client `Lumen.Fx`

**Files:** Create `liblumen-ext/fx.vala`, `tests/fx/fx_api.vala` (integration mode via run.sh); modify `liblumen-ext/extension.vala` (add `public Fx fx` to `Context`)

**Interfaces:**
- Consumes: `WayfireConnection` (Task 7), command set (Tasks 8–11).
- Produces (all ids auto-generated `"<ext id>/<n>"`; every object is registered with `ctx.own()` so `Context.release()` sends `destroy`):
  - `public class Lumen.Fx : GLib.Object { Fx(WayfireConnection c, string owner_id); Gee.List<OutputInfo> outputs; string active_output; async void claim_verb(string name) throws Error; signal void verb(string name, Json.Object data); async Zone zone(string output, Edge edge, int size, int delay_ms) throws Error; async ViewGroup views(ViewMatch m, bool follow_new = true) throws Error; async void set_layers(string output, string[] layers, bool visible) throws Error; async Node node(NodeSpec spec) throws Error /* throws IpcError.REMOTE with GLSL log */; }`
  - `public class Lumen.Zone : GLib.Object { signal void entered(string output); signal void left(string output); }`
  - `public struct Lumen.ViewProps { double tx; double ty; double sx; double sy; double alpha; }` (defaults sx=sy=alpha=1)
  - `public class Lumen.ViewGroup : GLib.Object { void set(ViewProps p); void set_visible(bool v); void focus(); void animate(ViewProps to, int ms, string curve = "circle"); signal void done(); }`
  - `public class Lumen.NodeSpec { string output; string above_layer = "overlay"; string? vert; string frag; int nu = 1; int nv = 1; HashTable<string, TextureSpec> textures; HashTable<string, float[]> uniforms; }`, `public class Lumen.TextureSpec { string[] snapshot_layers; int blur = 0; }`
  - `public class Lumen.Node : GLib.Object { void set(string uniform, float[] v); void animate(HashTable<string, float[]> to, int ms, string curve = "circle"); void recapture(); signal void done(); }`
  - `public enum Lumen.Edge { TOP, BOTTOM, LEFT, RIGHT }`
  - Host creates one `WayfireConnection`, one `watch`, and one `Fx` per extension sharing it (events routed by id prefix).
- [ ] **Step 1: Test** (`fx_api.vala`, run.sh mode): build a NodeSpec with the solid-colour shader, animate, await `done`; ViewGroup on `fx-dummy`; Context.release() → server reports no objects (`lumen-fx/debug/count` == 0).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** Commit `liblumen-ext: add Lumen.Fx effect client`.

## Phase 3 — Host and settings

### Task 13: `lumen-shell` host

**Files:**
- Create: `lumen-shell/src/main.vala`, `lumen-shell/src/safe_mode.vala`, `lumen-shell/meson.build`, `data/systemd/lumen-shell.service`, `tests/ext/safe_mode.vala`
- Modify: root `meson.build` (subdir, unit install next to existing units ~L612), `start-lumenshell` / session unit wiring (same mechanism that starts lumen-panel today)

**Interfaces:**
- Consumes: Tasks 2–7, 12.
- Produces:
  - `Gtk.Application("dev.lumen.shell")`. `startup`: `ExtensionConfig.load` → `Registry` declares built-in slots (`drawer.reveal` ONE, `tray.presenter` ONE, `tray.applet` MANY, `cc.module` MANY, `panel` ONE, plus later phases) → `Loader.discover([system_extensions_dir, extensions_dir])` → user extensions: `Compiler.build` all in parallel (`async` + counter) → load in `after` order → `enable(ctx)` each inside try/catch (`Error` → `ctx.release()`, logged, recorded in `$XDG_RUNTIME_DIR/lumen-shell/status.json` as `{"<id>":{"state":"failed","error":"..."}}`).
  - Drawer verbs (until the drawer itself is an extension, Phase 6): host calls `fx.claim_verb("lumen-peek/toggle"|"start"|"stop")` and routes to `registry.active("drawer.reveal") as DrawerReveal` (Task 15 interface).
  - `SafeMode`: `public class SafeMode { static bool should_enter(string state_path, int64 now_s) ; static void record_start(string state_path, int64 now_s); static void record_clean(string state_path); }` — 3 starts within 60 s without `record_clean` (called 10 s after successful startup) → safe mode = load bundled extensions only + notify via existing notification D-Bus.
  - systemd user unit `Restart=on-failure`.
- [ ] **Step 1: Tests** `tests/ext/safe_mode.vala`: `test_three_quick_starts_enter`, `test_clean_resets`, `test_old_starts_ignored` (starts 120 s ago don't count).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; manual: install, log in, `journalctl --user -u lumen-shell` shows `loaded 0 extensions`, no errors.
- [ ] **Step 5:** Commit `lumen-shell: add extension host`.

### Task 14: Settings → Extensions page

**Files:** Create `lumen-settings/src/pages/extensions_page.vala`; modify `lumen-settings/src/main.vala:54-71` (register in "LumenShell"), `lumen-settings/src/wayfire/plugin_page.vala` (extract `build_row` into a static helper usable with a `ParamDef`→`OptionDef` adapter), `lumen-settings/src/pages/drawer_page.vala:15-57`

**Interfaces:**
- Consumes: `Loader.discover`, `Manifest`, `ExtensionConfig`, status.json from Task 13.
- Produces: page id `"extensions"`; one `Adw.ExpanderRow` per extension (switch = enabled, subtitle = failed error if any, children = param rows); writes `extensions.json` atomically; `restart_target()` = `"lumen-shell"`. Drawer page "Reveal style" lists manifests whose `provides` contains `drawer.reveal` and writes `slots.drawer.reveal`.
- [ ] **Step 1: Test** `tests/ext/param_rows.vala`: adapter maps each `ParamType` to the matching `OptionType` (BOOL→BOOL, INT→INT with min/max, ENUM→INT+choices, COLOR→COLOR).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; manual: toggle an extension, restart host, state persists.
- [ ] **Step 5:** Commit `lumen-settings: add Extensions page and slot-driven reveal style`.

## Phase 4 — Effects as extensions (acceptance: curtain peek)

### Task 15: `curtain` extension

**Files:**
- Create: `liblumen-ext/slots/drawer_reveal.vala`, `extensions/curtain/{manifest.json, curtain.vala, curtain.vert, curtain.frag, meson.build}`, `extensions/meson.build`, `docs/extensions/parity-curtain.md`
- Modify: root `meson.build` (`subdir('extensions')`; each bundled extension = `shared_module('<id>', ..., dependencies: lumen_ext_dep, install_dir: libdir/'lumen-shell/extensions/<id>')` + `install_data(manifest, glsl)`)

**Interfaces:**
- Produces: `public interface Lumen.DrawerReveal : GLib.Object { public abstract void open(); public abstract void close(); public abstract bool is_open { get; } }`
- Extension behaviour (mirrors `curtain-peek.cpp` state machine IDLE/OPENING/OPEN/CLOSING):
  - open: `fx.node({output: active, above_layer: "overlay", vert, frag, nu: 64, nv: 24, textures: {"tex": {snapshot_layers: [bottom, workspace, top]}}, uniforms: constants})` → `views({app_id: drawer_app_id}).set_visible(true)` + `focus()` → `set_layers(active, ["workspace","top"], false)` → `node.animate({"u_p": [1]}, duration, curve)`.
  - close: `node.animate({"u_p":[0]})`, on `done` → destroy node, restore layers, hide drawer.
  - Params: `drawer-app-id` (default `lumen-drawer`), `widget-app-id`, `duration-ms` (default from `wayfire-curtain-peek.xml`), `curve`, plus every user-tunable option in that XML.
  - **Shader port rule:** every uniform that `curtain-peek.cpp` computes per frame from progress becomes a GLSL expression of `u_p`; values that don't depend on progress become set-once uniforms. If a per-frame CPU value cannot be expressed in GLSL ES 1.00, stop and report (it means the command set needs a new primitive).
- [ ] **Step 1:** Write `docs/extensions/parity-curtain.md`: manual checklist — open/close timing equal (record both with `wf-recorder`, compare frame counts ±1), fold count/shading identical at p=0.25/0.5/0.75 (screenshots with `grim`), Escape and app-launch close the drawer, `lumen-drawer` restart while open recovers, GPU time per frame within 5% (`WAYFIRE_DEBUG` render timing or `intel_gpu_top`/`radeontop` sample).
- [ ] **Step 2:** Run checklist against the old `wayfire-curtain-peek`, record results.
- [ ] **Step 3:** Implement extension; disable `wayfire-curtain-peek` in `[core] plugins`, enable `wayfire-lumen-fx`.
- [ ] **Step 4:** Run checklist against the extension → all items match.
- [ ] **Step 5:** Commit `extensions: port curtain peek to a lumen-fx extension`.

### Task 16: slide, zoom, desktop-peek, panel-push ports; delete old plugins

**Files:**
- Create: `extensions/{slide,zoom,desktop-peek,panel-push}/…`, `docs/extensions/parity-<id>.md`
- Delete: `wayfire-plugins/{curtain,slide,zoom,desktop}-peek/`, `wayfire-plugins/panel-push/`, their `meson_options.txt` lines and root `meson.build` blocks, `lumen-panel/src/peek_ipc.vala` push functions (panel-push becomes an extension the panel slot calls, see Task 18)
- Modify: default `wayfire.ini.d` snippet to load `wayfire-lumen-fx` only

**Interfaces:**
- Slide = snapshot node with default vertex shader + `u_offset` animated, drawer `ViewGroup` `ty` animated in the same call (same duration/curve → in sync on the compositor clock).
- Zoom = node with `tex` (sharp) + `blurred` (`blur: levels`) and `u_p`; drawer `ViewGroup` `sx/sy/alpha`.
- Panel-push = `ViewGroup({except_app_id: "lumen-panel", layers: [background,bottom,workspace,top]}, follow_new: true)` animated to `ty = ±px`; no 400 px clamp (param max = output height). Provides `Lumen.ScreenPush` (`push(int px, int ms)`, `restore(int ms)`) in slot `screen.push` (ONE) — in `liblumen-ext/slots/screen_push.vala`.
- Desktop-peek: read `wayfire-plugins/desktop-peek/src/*.cpp` first; port with the same rule as Task 15 (stop and report if a primitive is missing).
- [ ] **Step 1:** Parity checklists (same format as Task 15) for each, run on old plugins.
- [ ] **Step 2–4:** Implement each port, rerun checklists → match. `git grep -n "lumen-peek\|panel-push" -- ':!junkyard'` shows only the host router, extensions and docs.
- [ ] **Step 5:** Commit per extension, then `wayfire-plugins: remove per-effect plugins superseded by lumen-fx`.

## Phase 5 — Panel and tray as extensions (acceptance: new tray)

### Task 17: Move panel services into liblumen-ext; panel becomes an extension

**Files:**
- Move: lumen-common sources the panel uses (`logind`, `wifi_service`/`nmcli`, `bluetooth_service`/`btctl`, `sound_*`, `proc`, `dbus_cli`, `radio_state`, `tray_applets`) into `liblumen-ext/services/` (keep `LumenCommon` namespace; other apps keep compiling them from source until they become extensions — meson source groups point at the new path). Panel-only services (`BatteryService`, `PowerProfile`, `BrightnessService`, `SniWatcher`) → `liblumen-ext/services/` too, exposed as `Lumen.Services.get().battery` etc. (lazily constructed singletons — no service starts unless an extension asks for it).
- Move: `lumen-panel/src/**` → `extensions/panel/src/**`; `App` (`main.vala`) becomes `Panel.PanelExtension : Lumen.Extension`; `Gtk.Application` comes from `ctx.app`; resources compiled into the module (`gnome.compile_resources` linked into the shared_module).
- Create: `liblumen-ext/slots/{tray_applet,cc_module}.vala` — `Lumen.TrayApplet` = old `ITrayApplet` (`tray.vala:3-5`), `Lumen.CcModule` = old `IControlModule` (`control_module.vala:1-6`) plus `public abstract int home_row { get; }` and `public abstract bool home_paired { get; }` so `build_home()` can lay out unknown modules. Built-in applets (systray, wifi, bluetooth, battery, sound, clock, exit) register with `ctx.provide("tray.applet", …)` / `("cc.module", …)`.
- Remove the `LumenTray.CATALOG` gate: `PanelConfig.tray_enabled_order()` uses `registry.all("tray.applet")` ids; lumen-settings panel page reads the catalog from discovered manifests' `provides`.
- Delete: `lumen-panel` executable target and its unit; `PanelService` D-Bus moves into the panel extension unchanged (`org.lumenshell.Panel1`).

- [ ] **Step 1: Test** `tests/ext/tray_order.vala`: given registry with applets `[wifi, clock, myext]` and config `tray.order=[clock]`, `tray.disabled=[wifi]` → `[clock, myext]` (unknown ids are no longer dropped).
- [ ] **Step 2:** FAIL. **Step 3:** move + adapt. **Step 4:** PASS; manual: panel looks and behaves identically (multi-monitor, hidden/push modes, tray, control center, SNI, D-Bus ToggleTray).
- [ ] **Step 5:** Commit `panel: run lumen-panel as a bundled extension`.

### Task 18: Tray presenter slot + `tray-classic`

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
- Panel: `make_tray()` → `registry.active("tray.presenter")`; `update_input_region()` unions strip rect + `presenter.input_rects()` instead of computing the tray rect itself; ToggleTray → `presenter.toggle()`; push mode calls `registry.active("screen.push")`.
- `tray-classic` = current TrayBar/TrayReveal/ControlCenter unchanged in look; constants (`BOX_RADIUS`, `WIDTH/HEIGHT`, `DURATION_US`) become manifest params with today's values as defaults.
- [ ] **Step 1:** Manual parity checklist `docs/extensions/parity-tray.md` (expand/collapse, detail pages, Escape, input passes through outside tray, multi-monitor `tray_all_monitors`), run on current build.
- [ ] **Step 2–4:** implement; checklist matches.
- [ ] **Step 5:** Commit `extensions: split tray presentation into tray-classic presenter`.

### Task 19: `tray-wedge` example — user-compiled, own surface, compositor push

**Files:**
- Create: `data/examples/extensions/tray-wedge/{manifest.json, wedge.vala, wedge.frag}`, `docs/extensions/README.md` (authoring guide: contract, slots, Fx API, params, build errors, safe mode), `liblumen-ext/shape.vala`
- Modify: root `meson.build` (install examples to `datadir/lumenshell/examples/extensions`)

**Interfaces:**
- Produces: `public class Lumen.ShapedSurface : Gtk.Window { ShapedSurface(Gtk.Application app, string ns, Lumen.Edge anchor, int w, int h, string svg_path); Gtk.Widget child; void reveal(int ms); void dismiss(int ms); signal void pointer_left(); }` — clips with `Gsk.Path.parse` + `push_fill` (precedent: lumen-desktop `FolderShape`/`WidgetShape`); input region = path rasterised into 4 px-tall horizontal bands with `Gsk.Path.in_fill`, recomputed on size change only.
- Wedge: `attach()` returns null (no strip widget); `ctx.fx.zone(all, BOTTOM, 4, 150)` → on enter: `screen.push` 320 px + `ShapedSurface.reveal` + optional `wedge.frag` node; content = `TrayModel.modules` home tiles laid out in the inscribed rectangle.
- [ ] **Step 1: Test** `tests/ext/shape_bands.vala`: triangle `M0 320 L320 0 L640 320 Z`, band 4 px → region contains (320,300), excludes (10,10), band count == 80.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS; manual acceptance: copy example to `~/.config/lumen-shell/extensions/`, set `slots.tray.presenter = "tray-wedge"`, restart host → compiles once (second restart: no valac in `journalctl`), bottom-edge approach slides screen up and shows the triangle tray; tiles work; no Lumen source changed.
- [ ] **Step 5:** Commit `extensions: add tray-wedge example and authoring guide`.

---

## Phase 6 (TL;DR) — remaining apps become extensions

Same recipe as Task 17 for each: move `src/**` to `extensions/<id>/`, `App` → `Lumen.Extension`, shared `ctx.app`, layer-shell windows unchanged, delete the executable + unit, move the lumen-common sources it uses into `liblumen-ext/services/`.

| App | Becomes | Notes |
|---|---|---|
| lumen-drawer | `drawer` extension | Host's `lumen-peek/*` router moves here; drawer calls `registry.active("drawer.reveal")` directly instead of IPC to itself. Shares `ToplevelStore` with panel (dedupe the two `toplevels.vala`). |
| lumen-osd | `osd` | Brightness/volume watchers become shared services (one poller instead of two). `lumen-osdctl` CLI stays, talks D-Bus. |
| lumen-notifications | `notifications` | Owns `org.freedesktop.Notifications`; slot `notification.presenter` (ONE) so the popup look is replaceable like the tray. |
| lumen-corner | `hot-corner` | Becomes a `fx.zone` client; its ring widget is a `ShapedSurface`. |
| lumen-desktop | `desktop` | `FolderShape` moves into `Lumen.ShapedSurface`. |
| lumen-polkit-agent | `polkit` | Same process is fine (polkit auth goes via the agent's own helper, not our buffer); keep the dialog behind slot `auth.dialog`. |
| night-light plugin | `night-light` extension | Fullscreen node with colour-matrix frag above `overlay`; deletes the last bespoke plugin. |
| startup-zoom plugin | `startup-zoom` | `views({follow_new})` + animate on map. |
| lumen-settings | stays an app | Reads manifests; per-extension settings pages via optional `Lumen.SettingsProvider` slot. |
| **Core (stays)** | `lumen-shell`, `liblumen-ext`, `lumen-fx`, `lumen-session`, `lumen-lockscreen`, `lumen-lockctl`, `lumen-osdctl` | Lockscreen stays separate so no extension shares a process with the password buffer. |

End state: one GTK process for all shell UI (≈ one GTK/GL context instead of seven), one Wayfire plugin, `wayfire-plugins/common` duplication gone.
