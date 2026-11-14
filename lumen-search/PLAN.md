# lumen-search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Spotlight-style search popup for LumenShell. A tray magnifier opens a flat pill search bar that grows into a results window. It fuzzy-matches apps and LocalSearch-indexed files fzf-style, searches file contents, filters by known type words, and highlights what matched.

**Architecture:** `lumen-search` is a resident GTK4 + layer-shell daemon (`org.lumenshell.Search`). At startup it loads every indexed file (one SPARQL query to LocalSearch) and every app into memory. A pure-Vala port of fzf's v2 scorer ranks them on every keystroke. A debounced, cancellable LocalSearch FTS query supplies the "In Contents" section. lumen-panel gets a `search` tray applet that spawns `lumen-search --toggle`, and GApplication uniqueness forwards that to the daemon.

**Tech Stack:** Vala, GTK4, gtk4-layer-shell, tinysparql-3.0 (LocalSearch client), json-glib, Meson.

**Spec:** `lumen-search/DESIGN.md`. It's a copy of `docs/superpowers/specs/2026-11-14-lumen-search-design.md`; `docs/` is gitignored, so the copy here is the one that travels with the code.

## Global Constraints

- New meson feature option `with_search` (`auto`): build only when `tinysparql-3.0` is found, the same pattern as `with_lockscreen` (`meson.build:507-510`).
- Link order: `gtk4_layer_shell_dep` before `gtk4_dep` / `wayland_dep`, plus `link_args: ['-Wl,--no-as-needed']`.
- Any target compiling `paths_source` gets `c_args: lumen_datadir_c_args`.
- Config filename comes only from a new `LumenCommon.Paths.search_json()` (`~/.config/lumen-shell/search.json`).
- Spell `GLib.Object` (json-glib is in scope).
- **Never log queries, file names, paths or snippets** above `debug()`.
- Scale target: ≤ ~50k indexed files. Larger indexes are a documented v1 limit (a `ponytail:` comment at the scoring loop).
- LocalSearch DBus service: `org.freedesktop.LocalSearch3`. Ontology (verified live): content resource `?c nie:isStoredAs ?f ; nie:mimeType ?m`, file `?f nie:url ?u`.
- No `fzf`/`ripgrep` dependency. No lumen-settings page in v1.
- Install after every feature change: `meson compile -C build && sudo meson install -C build`.

## Review Focus

1. **LocalSearch not running / name not on the bus.** Apps still search, Files and Contents are empty, and nothing crashes or spams warnings. Task 4 verification.
2. **Non-ASCII file names (`Ærø-faktura.pdf`, the user is on da_DK).** Match positions are byte offsets valid for Pango, so highlighting never splits a UTF-8 sequence. Test in Task 1.
3. **FTS-hostile input (`a"b(`, `*`, `-`).** The content query uses a prepared statement with `~q` binding, never string concatenation, so it neither errors nor injects. Task 4 verification.
4. **Fast typing.** A stale content result from an earlier query must never replace a newer one. Uses a `Cancellable` plus a generation counter. Task 5 verification.
5. **Query that is only type words (`pdf`, `png jpg`).** With no fuzzy terms left, every file of that type is listed, ranked by bonuses only. Test in Task 3.

---

## File structure

```
lumen-search/
  PLAN.md, DESIGN.md
  src/fuzzy.vala      Fuzzy.match(): fzf-v2 scorer + positions. Pure.
  src/types.vala      Known type words → MIME prefixes. Pure.
  src/junk.vala       Junk.is_junk(path, home). Pure.
  src/query.vala      Query.parse(): split terms, pull out type words. Pure.
  src/rank.vala       Item, Hit, Results, Ranker (scoring, tiers, sections, incremental). Pure (GLib only).
  src/index.vala      FileIndex (SPARQL load), AppIndex, recency join.
  src/content.vala    ContentSearch (FTS, prepared statement, snippets).
  src/config.vala     SearchConfig: search.json (boost dirs, content toggle, colours, width).
  src/window.vala     SearchWindow: layer-shell pill → expanded results, keys, open/reveal.
  src/result_row.vala ResultRow: icon + highlighted name + dir + type label.
  src/main.vala       SearchApp: --toggle, --query (headless dump), hold().
tests/search_core.vala  asserts for fuzzy/types/junk/query/rank
lumen-panel/src/components/search/search.vala + res/search.svg
```

---

### Task 1: Fuzzy matcher + build skeleton

**Files:**
- Create: `lumen-search/src/fuzzy.vala`, `tests/search_core.vala`
- Modify: `meson_options.txt` (add `with_search`), `meson.build` (new `search_core_source` group + `test('search-core', …)`)

**Interfaces:**
- Produces: `namespace LumenSearch { public class Fuzzy { public static bool match(string pattern, string text, out int score, out int[] positions); } }`. `positions` are **byte offsets** of the start of each matched character in `text`, ascending. Smart-case: case-insensitive unless `pattern` contains an uppercase char; compare `unichar.tolower()` per char, **not** `casefold()` (which shifts offsets). An empty pattern returns true, score 0, no positions.
- Produces: meson `search_core_source = files('lumen-search/src/fuzzy.vala', 'types.vala', 'junk.vala', 'query.vala', 'rank.vala')` (grows over Tasks 1–3), test deps `[glib_dep, gio_dep]`.

- [ ] **Step 1: Write the failing test** in `tests/search_core.vala` (`int main()` with `assert`s, the same style as `tests/display_identity.vala`):

```vala
int s1, s2; int[] p;
assert(Fuzzy.match("invpdf", "invoice-2025.pdf", out s1, out p));
assert(p.length == 6 && p[0] == 0 && p[3] == 13);          // i n v … p d f
assert(!Fuzzy.match("xyz", "invoice-2025.pdf", out s1, out p));
// boundary/consecutive bonuses: prefix run beats scattered
Fuzzy.match("inv", "invoice.pdf", out s1, out p);
Fuzzy.match("inv", "main_overview.txt", out s2, out p);
assert(s1 > s2);
// smart case
assert(!Fuzzy.match("Inv", "invoice.pdf", out s1, out p));
assert(Fuzzy.match("inv", "Invoice.pdf", out s1, out p));
// UTF-8: offsets land on char starts
assert(Fuzzy.match("ærpdf", "Ærø-faktura.pdf", out s1, out p));
assert(p[0] == 0 && p[1] == 2);                            // 'Æ' is 2 bytes
```

- [ ] **Step 2: Run it and confirm it fails.** Run `meson setup build --reconfigure && meson test -C build search-core`. Expected: compile error, `Fuzzy` is undefined.

- [ ] **Step 3: Implement `Fuzzy.match`.** Port fzf `algo.go` FuzzyMatchV2: a DP over (pattern × text) with backtrace for positions, falling back to V1-greedy when `text` is longer than 1000 chars. Use fzf's constants: `scoreMatch 16, scoreGapStart -3, scoreGapExtension -1, bonusBoundary 8, bonusNonWord 8, bonusCamel123 7, bonusConsecutive 4, bonusFirstCharMultiplier 2`. Delimiters `/ - _ . space` count as boundaries. Add the `with_search` option to `meson_options.txt`, mirroring `with_lockscreen`, and the `search_core_source` + `test('search-core', executable('test-search-core', files('tests/search_core.vala') + search_core_source, dependencies: [glib_dep, gio_dep]))`. The test runs regardless of the option, because the core is GLib-only.

- [ ] **Step 4: Run the test and confirm it passes.** Run `meson test -C build search-core`. Expected: `1/1 search-core OK`.

- [ ] **Step 5: Commit.** `git add lumen-search/src/fuzzy.vala tests/search_core.vala meson.build meson_options.txt && git commit -m "lumen-search: fzf-v2 fuzzy matcher"`

---

### Task 2: Type words, junk, query parsing

**Files:**
- Create: `lumen-search/src/types.vala`, `lumen-search/src/junk.vala`, `lumen-search/src/query.vala`
- Modify: `tests/search_core.vala`, `meson.build` (append to `search_core_source`)

**Interfaces:**
- Produces: `Types.lookup(string word) → string[]?`, which returns MIME prefixes for a known word (case-insensitive) or null. `Types.APP_WORDS = {"app","application"}` is handled by `Query`, not `lookup`. Table (hardcoded, not configurable):
  - `pdf`→`application/pdf`
  - `doc`,`document`→`application/pdf`, `application/vnd.oasis.opendocument.text`, `application/msword`, `application/vnd.openxmlformats-officedocument.wordprocessingml`
  - `sheet`,`spreadsheet`→`…opendocument.spreadsheet`, `application/vnd.ms-excel`, `…spreadsheetml`, `text/csv`
  - `slides`→`…opendocument.presentation`, `application/vnd.ms-powerpoint`, `…presentationml`
  - `text`→`text/`
  - `image`,`photo`,`picture`→`image/`; `png`→`image/png`; `jpg`,`jpeg`→`image/jpeg`; `svg`→`image/svg`
  - `music`,`audio`,`song`→`audio/`; `mp3`→`audio/mpeg`; `flac`→`audio/flac`
  - `video`,`movie`→`video/`; `mp4`→`video/mp4`
  - `archive`,`zip`→`application/zip`, `application/x-tar`, `application/x-7z`, `application/gzip`, `application/x-compressed-tar`
  - `folder`,`dir`→`inode/directory`
- Produces: `Junk.is_junk(string path, string home) → bool`. True if any segment starts with `.`, or a segment is one of `node_modules __pycache__ target build dist vendor site-packages`, or the path is under `home + "/go/pkg"` or `home + "/.local/share/Trash"`.
- Produces: `class Query { string raw; string[] terms; string[] mime_prefixes; bool apps_only; bool hide_apps; static Query parse(string raw); bool matches_mime(string mime); }`. Split on whitespace. A whole-word type term goes to `mime_prefixes` (union = OR). An `app` term sets `apps_only`. Any other type term sets `hide_apps`. Everything else stays in `terms` (original case kept for smart-case).

- [ ] **Step 1: Write the failing tests** (append to `search_core.vala`):

```vala
assert(Types.lookup("PDF")[0] == "application/pdf");
assert(Types.lookup("do") == null);                 // partial word is not a type
var q = Query.parse("inv pdf");
assert(q.terms.length == 1 && q.terms[0] == "inv" && q.hide_apps && !q.apps_only);
assert(q.matches_mime("application/pdf") && !q.matches_mime("image/png"));
var q2 = Query.parse("png jpg");
assert(q2.terms.length == 0 && q2.matches_mime("image/jpeg") && q2.matches_mime("image/png"));
assert(Query.parse("app fire").apps_only);
var h = "/home/u";
assert(Junk.is_junk("/home/u/.cache/foo/invoice.json", h));
assert(Junk.is_junk("/home/u/go/pkg/mod/x.go", h));
assert(Junk.is_junk("/home/u/src/app/node_modules/a/b.js", h));
assert(!Junk.is_junk("/home/u/Documents/invoice-2025.pdf", h));
```

- [ ] **Step 2: Run them and confirm they fail.** Run `meson test -C build search-core`. Expected: compile error, `Types`/`Query`/`Junk` are undefined.
- [ ] **Step 3: Implement the three files** per the interfaces above.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `meson test -C build search-core`. Expected: OK.
- [ ] **Step 5: Commit.** `git commit -am "lumen-search: type words, junk rules, query parsing"` (add the new files first).

---

### Task 3: Ranker

**Files:**
- Create: `lumen-search/src/rank.vala`
- Modify: `tests/search_core.vala`, `meson.build`

**Interfaces:**
- Consumes: `Fuzzy.match`, `Query`, `Junk.is_junk`.
- Produces:
  - `enum ItemKind { APP, FILE, FOLDER }`
  - `class Item : GLib.Object { ItemKind kind; string name; string dir /* "" for apps */; string uri; string mime; int64 recent_age_s = -1; bool junk; bool boosted; GLib.AppInfo? app; string[] extra /* app generic name + keywords */; }`
  - `class Hit : GLib.Object { Item item; int score; int[] name_pos; int[] dir_pos; string? snippet_markup; }`
  - `class Results { Hit? top; Hit[] apps; Hit[] files; }`
  - `class Ranker { set_items(Item[] items); Results search(Query q); }`

- [ ] **Step 1: Write the failing tests.** Build Items by hand:

```vala
var pdf  = file_item("invoice-2025.pdf", "/home/u/Documents", "application/pdf", boosted: true);
var junk = file_item("invoice.json", "/home/u/.cache/foo", "application/json", junk: true);
var r = new Ranker(); r.set_items({ junk, pdf });
var res = r.search(Query.parse("invoice"));
assert(res.files[0].item == pdf);                   // anti-goal: junk never first
assert(res.top.item == pdf);
// strict tier: junk loses even with a better fuzzy match
var exact_junk = file_item("invpdf", "/home/u/.cache", "text/plain", junk: true);
r.set_items({ exact_junk, pdf });
assert(r.search(Query.parse("invpdf")).files[0].item == pdf);
// type-only query lists all of that type
r.set_items({ pdf, junk });
var t = r.search(Query.parse("pdf"));
assert(t.files.length == 1 && t.files[0].item == pdf && t.apps.length == 0);
// path match: "tax inv" hits dir segment, positions in dir_pos
var tax = file_item("invoice.pdf", "/home/u/Documents/Tax", "application/pdf", boosted: true);
r.set_items({ tax });
var d = r.search(Query.parse("tax inv")).files[0];
assert(d.dir_pos.length == 3 && d.name_pos.length == 3);
// incremental: appending a char reuses the candidate set, same answer
r.set_items({ pdf, junk });
r.search(Query.parse("inv"));
assert(r.search(Query.parse("invo")).files[0].item == pdf);
```

(`file_item(...)` is a small helper inside the test file.)

- [ ] **Step 2: Run them and confirm they fail.** Run `meson test -C build search-core`. Expected: compile error.
- [ ] **Step 3: Implement `Ranker`.**
  - Each term must match the name, or else the `dir` at **×0.5** score (and app `extra` at ×0.7). Terms are ANDed. Positions are unioned per field.
  - `score = fuzzy × kind_weight + location + recency`, with `kind_weight` APP 1.5 / FILE 1.0 / FOLDER 0.9, `location` 40 if `boosted`, and `recency` 60 if age < 1 d, 30 if < 7 d, 10 if < 30 d.
  - Sort key: `(junk ? 1 : 0, -score)`.
  - Type filter via `q.matches_mime`. `apps_only` / `hide_apps` gate sections.
  - Limits: apps 5, files 8.
  - `top` = best non-junk hit across apps+files if it is the only hit or ≥ 1.2× the runner-up. The top hit is removed from its section.
  - Incremental: remember the last `q.raw` and its matching candidates. If the new raw starts with the old one and has the same type terms, score only those candidates. Add `// ponytail: full rescan per new query; chunk on a worker thread if indexes exceed ~50k`.
- [ ] **Step 4: Run the tests and confirm they pass.** Run `meson test -C build search-core`. Expected: OK.
- [ ] **Step 5: Commit.** `git commit -m "lumen-search: ranker with junk tier, type filter, sections"`

---

### Task 4: Index + content search + headless `--query`

**Files:**
- Create: `lumen-search/src/index.vala`, `lumen-search/src/content.vala`, `lumen-search/src/config.vala`, `lumen-search/src/main.vala` (CLI part)
- Modify: `lumen-common/paths.vala` (add `search_json()`), `meson.build` (the `lumen-search` executable under `with_search`)

**Interfaces:**
- Consumes: `Item`, `Ranker`, `Query`, `Junk`.
- Produces:
  - `class SearchConfig { static string[] boost_dirs; static bool content; static int width; static string background, text, muted_text, highlight; static void load(); }`. Reads `Paths.search_json()` via json-glib. Defaults: XDG user dirs (`GLib.get_user_special_dir` for DOCUMENTS, DESKTOP, DOWNLOAD, PICTURES, MUSIC, VIDEOS) + `search.boost-dirs`, `content` true, width 680, colours as in the spec.
  - `class FileIndex { async Item[] load(Cancellable? c) throws Error; }`. Query: `SELECT ?u ?m ?mod WHERE { ?f a nfo:FileDataObject ; nie:url ?u . OPTIONAL { ?c nie:isStoredAs ?f ; nie:mimeType ?m } OPTIONAL { ?f nfo:fileLastModified ?mod } }`. Sets `junk` / `boosted` per item, and `kind = FOLDER` for `inode/directory`. Recency is joined from `Gtk.RecentManager.get_default().get_items()` by URI.
  - `class AppIndex { static Item[] load(); }`, from `AppInfo.get_all()` filtered by `should_show()`.
  - `class ContentSearch { async Hit[] run(Query q, Cancellable c) throws Error; }`. Uses a prepared statement: `SELECT ?u fts:snippet(?c, "\u0002", "\u0003", "…", 8) WHERE { ?c fts:match ~q ; nie:isStoredAs ?f . ?f nie:url ?u } ORDER BY DESC(fts:rank(?c)) LIMIT 20`. `~q` = each term sanitised to `[\w]+` + `*`, space-joined. Fewer than 3 total chars → empty. `snippet_markup` = `Markup.escape_text` first, then `\u0002`/`\u0003` → `<b>`/`</b>`.
  - Shared `Tsparql.SparqlConnection.bus_new("org.freedesktop.LocalSearch3", null, null)`. On failure, log one `warning` (no paths), and file and content results stay empty.
  - CLI: `lumen-search --query TEXT` handled in `handle_local_options`. It loads the indexes, prints the sections (`TOP`, `APPS`, `FILES`, `CONTENTS`, one item per line with matched chars wrapped in `[]`), and exits 0. This is the headless check for this task and for Review Focus 1 and 3.

- [ ] **Step 1: Add `Paths.search_json()`** next to `osd_json()`, then add the executable to `meson.build`. Deps: `gtk4_layer_shell_dep, gtk4_dep, wayland_dep, glib_dep, gio_dep, json_dep, tinysparql_dep`. Vala `--pkg=tinysparql-3.0`. Sources: `search_sources + search_core_source + paths_source + theme_json_source + proc_source`.
- [ ] **Step 2: Implement the files above.**
- [ ] **Step 3: Verify against the live index.** Run `meson compile -C build && ./build/lumen-search --query invpdf`. Expected: exits 0 and lists files with `[i][n][v]…[p][d][f]`. Then run `./build/lumen-search --query 'pdf'`: only PDFs, with `~/Documents` ones above any dot-dir ones.
- [ ] **Step 4: Verify hostile input.** Run `./build/lumen-search --query 'a"b( *'`. Expected: exits 0, no SPARQL error on stderr.
- [ ] **Step 5: Verify degradation.** Run `DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent ./build/lumen-search --query fire`. Expected: one warning line, an APPS section, empty FILES, exit 0.
- [ ] **Step 6: Commit.** `git commit -m "lumen-search: LocalSearch index, content FTS, --query"`

---

### Task 5: Search window

**Files:**
- Create: `lumen-search/src/window.vala`, `lumen-search/src/result_row.vala`
- Modify: `lumen-search/src/main.vala` (GUI path, `--toggle`)

**Interfaces:**
- Consumes: `Ranker`, `FileIndex`, `AppIndex`, `ContentSearch`, `SearchConfig`, `Hit`.
- Produces: `SearchApp : Gtk.Application`, id `org.lumenshell.Search`, `HANDLES_COMMAND_LINE`, `hold()`. `command_line` handles `--toggle` (show/hide); a bare launch just starts the daemon hidden. `SearchWindow.toggle()`.

- [ ] **Step 1: Build `SearchWindow`.**
  - Layer `OVERLAY`, anchor `TOP` only, top margin = 20% of the monitor height, `KeyboardMode.EXCLUSIVE`, namespace `lumen-search`.
  - Collapsed: a pill `SearchConfig.width` wide and 56 px tall, radius 28, magnifier glyph + `Gtk.Text`.
  - Expanded (text non-empty): a `Gtk.Revealer` (`SLIDE_DOWN`) with a hairline separator and a scrolled list capped at 480 px. The outer radius becomes 16.
  - Inline CSS built from `SearchConfig` colours.
  - On show: refresh `FileIndex` in the background if the last load is > 60 s old.
- [ ] **Step 2: Build `ResultRow(Hit h)`.**
  - Icon: `app.get_icon()` or `ContentType.get_icon(mime)`.
  - Name label with a `Pango.AttrList`: bold + `highlight` foreground over `[pos, pos + utf8 char len)` for each `name_pos`.
  - Dir label: `~`-shortened, muted, highlighted the same way from `dir_pos`.
  - Right label: `ContentType.get_description(mime)`, or "Application", highlighted when the query has type terms.
  - Contents rows show `snippet_markup` as markup under the name.
  - Section headers: "Top Hit", "Applications", "Files", "In Contents".
- [ ] **Step 3: Wire typing.**
  - `changed` → `Ranker.search` synchronously → rebuild rows.
  - Content search: a 150 ms debounce, cancel the previous `Cancellable`, bump the generation `int`. Drop results whose generation is stale (Review Focus 4). Skip it when `!SearchConfig.content`.
- [ ] **Step 4: Wire keys and clicks.**
  - Up/Down move the selection across all rows, skipping headers.
  - Enter opens: `app.launch(null, display.get_app_launch_context())`, else `AppInfo.launch_default_for_uri_async`.
  - Ctrl+Enter reveals: DBus `org.freedesktop.FileManager1` `/org/freedesktop/FileManager1` `ShowItems(as uris, s "")`.
  - Escape clears the text if it's non-empty, otherwise hides.
  - Clicking a row opens it.
  - Opening anything hides the window and clears the query.
- [ ] **Step 5: Manual verification.** Run `meson devenv -C build ./lumen-search &`, then `./build/lumen-search --toggle`. Check:
  - The pill appears and takes keys immediately.
  - Typing `invpdf` expands it, with highlighted letters.
  - Hammering keys quickly never shows contents for an older query.
  - Escape twice hides it.
  - `--toggle` again shows it instantly.
- [ ] **Step 6: Commit.** `git commit -m "lumen-search: layer-shell search window"`

---

### Task 6: Panel tray button + session wiring + docs

**Files:**
- Create: `lumen-panel/src/components/search/search.vala`, `lumen-panel/src/res/search.svg`
- Modify:
  - `lumen-panel/src/main.vala` (register `"search"`)
  - `lumen-common/tray_applets.vala` (`{ "search", "Search" }` first in `CATALOG`)
  - `lumen-panel/src/resources.gresource.xml`
  - `lumen-panel/src/widgets/tray.vala:48-50` (hover check also skips `tray-search`)
  - `meson.build` (`panel_sources`)
  - `lumen-lockscreen/data/wayfire/lumenshell.ini.d/autostart.ini` (`search = systemd-cat -t lumen-search lumen-search`, plus `[command] binding_search = <super> KEY_SPACE` / `command_search = lumen-search --toggle`)
  - `CLAUDE.md` (lumen-search section, the build-targets list, the `paths.vala` getter list, the architecture diagram line)

**Interfaces:**
- Consumes: `ITrayApplet.tray_widget()`, `TrayButton(string)`, `LumenCommon.Proc.spawn_detached(string[])`.
- Produces: `class SearchTray : GLib.Object, ITrayApplet`. Its widget is a `TrayButton("search")` with css class `tray-search` and a `Gtk.GestureClick` that **claims** the press (`set_state(Gtk.EventSequenceState.CLAIMED)`) so the Control Center doesn't toggle, then spawns `{"lumen-search", "--toggle"}`.

- [ ] **Step 1: Draw `search.svg`.** A 24×24 magnifier, `stroke="#ffffff"` hard-coded, round caps, the same stroke width as `sound-max.svg`.
- [ ] **Step 2: Implement `SearchTray`**, register it, and add it to the catalog and resources.
- [ ] **Step 3: Verify.** Run `meson compile -C build && meson test -C build && sudo meson install -C build`, restart the panel, then check:
  - Clicking the magnifier opens search, and the Control Center stays closed.
  - Clicking other tray icons still opens the Control Center.
  - The lumen-settings Panel page lists "Search" in the reorder list.
- [ ] **Step 4: Update `CLAUDE.md` and the autostart snippet**, then commit: `git commit -m "lumen-panel: search tray button; wire lumen-search into session"`

---

## Self-review notes

- Spec coverage: every spec item maps to a task.
  - Fuzzy matching: T1
  - Types and junk: T2
  - Ranking, sections, Top Hit, incremental re-scoring: T3
  - LocalSearch file index, content search, recency, config: T4
  - Window, highlighting, keys, reveal: T5
  - Tray button, hotkey, autostart: T6
- Deferred per the spec: click-outside dismiss, settings page, live `TrackerNotifier`, indexes beyond 50k.
