# lumen-search — design

## Intent

A Spotlight-style search for LumenShell. Click a magnifier in the panel tray
and a flat, rounded search bar appears. Start typing and the bar grows into
a results window listing matching apps and files, with the matched part of
each result highlighted. Matching is fzf-style fuzzy: typing `invpdf` finds
`invoice-2025.pdf`, with `i n v … p d f` highlighted. Ranking puts the user's
own documents ahead of clutter (dotfiles, build trees, `~/go/pkg/mod`).
Matching covers file names, file contents and metadata such as category.

## Goals

- Fuzzy match over app names and file names, with match positions shown.
- Full-text search inside files, shown with a highlighted snippet.
- Category/type matching: `pdf`, `image`, `music` narrow or boost results.
- Relevance: personal folders and recently used files rank above noise.
- Instant feel: name results update on every keystroke with no visible lag.

## Non-goals

- No indexer of our own. **LocalSearch (tracker3) is the index.** If it isn't
  running, file results are empty and apps still work.
- No `/etc` or `/usr` files (LocalSearch doesn't index them, and we don't want them).
- No web search, calculator, unit conversion, or settings search.
- No lumen-settings page in v1. The config file is hand-edited.

## Anti-goals

- Typing lag. The fuzzy pass runs in-process on every keystroke and must stay
  well under a frame for ~10–20k items.
- Junk outranking documents. `~/.cache/foo/invoice.json` must never beat
  `~/Documents/invoice-2025.pdf`.
- Logging queries, file names or snippets. These are user data and are logged
  at `debug()` at most (same rule as lumen-notifications).

## Constraints (found in the repo / on the machine)

- LocalSearch is running and indexes `$HOME` recursively (~10.5k files on the
  dev box). A query takes about 30 ms. The Vala bindings are `tinysparql-3.0`
  (3.11, vapi installed).
- LocalSearch's own FTS (`fts:match`) is word/prefix only. It can't do
  `invpdf`, which is why the fuzzy part is ours.
- `fzf` and `ripgrep` are not installed, and neither is needed.
- Repo conventions apply: a new `executable()` in the root `meson.build`,
  `lumen-common` sources compiled in, config filename via a new
  `Paths.search_json()` getter, theme colours via `ThemeJson` like lumen-osd,
  and `gtk4_layer_shell_dep` first in the link line.

## Approaches considered

- **A. Fuzzy names in memory + LocalSearch for content (chosen).** Pull every
  indexed file's name/path/type/category from LocalSearch once into memory,
  plus installed apps. A Vala port of fzf's scoring ranks them per keystroke
  and returns match positions. In parallel, a debounced LocalSearch FTS query
  returns content hits with snippets. This is the only option that gives both
  `invpdf` and search inside files.
- **B. LocalSearch only.** Every keystroke becomes an FTS query. Less code, but
  loses fuzzy matching. Rejected: fuzzy is the point.
- **C. Pipe to the fzf binary.** Needs installing, can't see contents, and
  spawns a process per keystroke. Strictly worse than A.

The user picked **A**.

## Design

### Processes

- **`lumen-search`** is a new resident binary: `Gtk.Application`, id
  `org.lumenshell.Search`, `hold()`, started from the `[autostart]` snippet
  like lumen-osd. It loads the index at startup so the first open is instant.
- **Opening:** `lumen-search --toggle`. GApplication uniqueness forwards the
  command line to the running instance. The panel button spawns that command
  (`LumenCommon.Proc.spawn_detached`). A Wayfire `[command]` binding can run
  the same thing for a global hotkey (suggest `<super> KEY_SPACE`), which
  needs no extra code. If the daemon isn't running, the same spawn starts it,
  and the first open waits for the index load.

### Panel tray button (lumen-panel)

- New icon-only applet `search` (`components/search/search.vala`): a
  `TrayButton` with a new `search.svg` magnifier (hard-coded
  `stroke="#ffffff"`, per the repo SVG rule).
- Registered in `main.vala` and added to `LumenTray.CATALOG` (as "Search",
  placed first) so lumen-settings can reorder or disable it.
- **The click must be claimed by the button itself.** The tray row is
  otherwise one click target that opens the Control Center. Follow how the SNI
  buttons keep their own clicks.

### Window (lumen-search)

- Layer-shell surface, layer `OVERLAY`, anchored `TOP`, horizontally centred,
  top margin ~20% of output height, on the focused output (the output under
  the pointer is fine).
- `KeyboardMode.EXCLUSIVE` while shown. The bar must take keys straight away;
  `ON_DEMAND` only delivers keys after a click. Hidden = unmapped.
- **Collapsed:** one flat pill, ~680 px wide, ~56 px tall, magnifier glyph +
  `Gtk.Text`, corner radius = half the height, no border, a soft shadow.
- **Expanded** (query non-empty): the same surface grows downward to at most
  ~480 px. Corners become ~16 px; results sit under a hairline separator.
  The growth is animated (a `Gtk.Revealer` around the results is fine).
  Clearing the query collapses it again.

```
 ╭─────────────────────────────────────────────╮
 │ 🔍  invpdf                                    │
 ├─────────────────────────────────────────────┤
 │ TOP HIT                                       │
 │ ▣ [inv]oice-2025.[pdf]   ~/Documents/Tax  PDF │  ← selected
 │ APPLICATIONS                                  │
 │ ▣ [Inv]oice Ninja                             │
 │ FILES                                         │
 │ ▣ [inv]entory.[pdf]      ~/Downloads      PDF │
 │ IN CONTENTS                                   │
 │ ▣ notes.md  …the [invoice] for [pdf] export…  │
 ╰─────────────────────────────────────────────╯
```

- Rows: icon (`GIcon` from the app / `ContentType.get_icon(mime)`), name with
  matched characters bold + accent colour (Pango attributes from match
  positions), dimmed parent dir (`~`-shortened), and a dim type label on the right.
- Keys: Up/Down move across sections, Enter opens, Ctrl+Enter reveals the
  file in the file manager (`org.freedesktop.FileManager1.ShowItems` over
  DBus), Escape hides (clears the query on first press if non-empty?
  **builder's call**). Opening anything hides the window and clears the query.
- Clicking a row opens it. Clicking outside the window to dismiss isn't
  supported in v1 (it would need a full-screen input surface). Escape and the
  tray button cover it.

### Data

- **Apps:** `AppInfo.get_all()` filtered by `should_show()`. Haystack is the
  display name; generic name and keywords are matched too at lower weight.
  Reloaded on `AppInfoMonitor.changed`.
- **Files:** one SPARQL query at startup, re-run on each open in a worker
  thread if the last load is older than ~60 s:
  `nfo:FileDataObject` → URL, `nfo:fileName`, `nie:mimeType`, the `rdf:type`s
  (Document / Image / Audio / Video / Folder …), `nfo:fileLastModified`.
  Folders are included. Exact predicate names are confirmed against the
  installed ontology by the builder.
- **Recency:** `Gtk.RecentManager.get_default()` (recently-used.xbel), joined
  by URI.
- **Contents:** per query (debounced ~150 ms, previous one cancelled via
  `Cancellable`), an FTS query with each whitespace token as `token*`, `LIMIT
  20`, using `fts:snippet` with private marker characters that become the
  highlight. Queries shorter than 3 characters skip content search.

### Fuzzy matcher (`lumen-search/src/fuzzy.vala`)

- Port fzf's scoring (algo v2: per-character score with bonuses for
  word-boundary, camelCase, consecutive run and first-character matches, and
  gap penalties), returning `score` + matched character indices. Smart-case:
  lowercase query = case-insensitive.
- **Space-separated terms are ANDed** (fzf extended mode, subset): `inv pdf`
  must match both, and the positions are unioned for highlighting.
- Matched against the **basename** (extension included, so `invpdf` works).
  A term that doesn't match the basename may match the parent path at a heavy
  discount, so `tax inv` finds `~/Documents/Tax/invoice.pdf`, with the path
  segment highlighted in the dir column.
- Pure and GTK-free, so it gets a meson `test()` with `assert`s, like
  `tests/display_identity.vala`.
- **Scale:** designed for up to ~50k indexed files. When the new query
  extends the previous one (a character appended), only the previous
  result set is re-scored. Larger indexes are a documented limit for v1
  (`ponytail:` comment at the scoring loop; upgrade path is chunked scoring
  on a worker thread).

### Category / metadata matching

- **Known type words are a hardcoded table in code** (`types.vala`), each
  mapping to a predicate over MIME type / LocalSearch class / extension, e.g.
  `pdf`, `doc`/`document`, `sheet`/`spreadsheet`, `slides`, `text`,
  `image`/`photo`/`picture`, `png`, `jpg`, `svg`, `music`/`audio`/`song`,
  `mp3`, `flac`, `video`/`movie`, `mp4`, `archive`/`zip`, `folder`/`dir`,
  `app`/`application`. The table is not user-configurable.
- **A query term that is exactly one of these words (whole word,
  case-insensitive) becomes a type filter** and is removed from the fuzzy
  terms. `pdf` alone lists all PDFs (ranked by the usual bonuses); `inv pdf`
  lists PDFs fuzzy-matching `inv`. Several type terms are ORed (`png jpg`).
  Partial words (`do`, `im`) are never type terms; they stay fuzzy text, so
  results don't vanish mid-word.
- The filter applies to Files and In Contents. `app`/`application` restricts
  results to Applications; any other type term hides Applications.
- Accepted cost: a file literally named `pdf-tools` is found by `pdft`, not
  by `pdf` alone.
- The type label in the row is highlighted when a type filter is active.

### Ranking

Sort key, in order: **(1) junk tier, (2) score**.

`score = fuzzy_score × kind_weight + location_bonus + recency_bonus`

- **Junk is a strict tier, not a weight.** Within every section (Files and In
  Contents included), any non-junk match ranks above every junk match. Junk
  appears only below all non-junk matches, so it surfaces when nothing better
  matches or when the user types its name closely.
- **What counts as junk is defined in code** (`junk.vala`, hardcoded): any
  path segment starting with `.` (dot-dirs and dotfiles) and the segments
  `node_modules`, `__pycache__`, `.git`, `target`, `build`, `dist`,
  `vendor`, `site-packages`, `.cache`, plus `~/go/pkg` and
  `~/.local/share/Trash`. Pure function, covered by the matcher test.
- `kind_weight`: apps > files. Folders score slightly below files of the same match.
- `location_bonus`: the path is under an XDG user dir (`Documents`, `Desktop`,
  `Downloads`, `Pictures`, `Music`, `Videos`) or an extra configured dir.
- `recency_bonus`: in RecentManager, decayed by age (e.g. full bonus <1 day,
  half <1 week, small <30 days).
- The exact weights are the builder's first guess, tuned against the dev
  box's real index. Test case: query `invoice` with
  `~/.cache/foo/invoice.json` and `~/Documents/invoice-2025.pdf` → the PDF
  ranks first.
- Sections: **Top Hit** (best overall, if it beats the runner-up by a margin
  or is the only strong hit), **Applications** (≤5), **Files** (≤8), **In
  Contents** (≤5). Each section is ordered by `final`.

### Config — `~/.config/lumen-shell/search.json` (`Paths.search_json()`)

Flat dotted keys, like the other `*.json` files:

```json
{
  "search.boost-dirs": ["~/Projects"],
  "search.content": true,
  "search.background": "#2a2a2aee", "search.text": "#ffffff",
  "search.muted-text": "#ffffff99", "search.highlight": "#4c9bffff",
  "search.width": 680
}
```

Lists are JSON arrays (read with json-glib directly; `ThemeJson` handles the
scalar colour keys). A missing file means defaults.

## Left to the builder

- Exact SPARQL predicates and ontology classes; validate with
  `tinysparql query` against the live index.
- fzf v2 port details and score constants.
- Ranking weights, tuned against real data.
- The expand animation mechanics and exact sizes and colours, within the
  flat/rounded look above.
- Escape semantics (clear then hide, or hide directly).

## Decided by the user

- Approach A; LocalSearch as the index; fzf-style fuzzy matching.
- Type words are a hardcoded known list and act as whole-word filters.
- Junk is defined in code and is a strict lower tier.

## Calls made by Claude (flag if wrong)

- Up to ~50k files, incremental re-scoring; larger is a v1 limit.
- tinysparql behind a meson feature option (`with_search`, `auto`), like the lockscreen.
- Resident daemon + `--toggle` via GApplication uniqueness, not a new DBus interface.
- `KeyboardMode.EXCLUSIVE` while shown; no click-outside dismiss in v1.
- File list refreshed on open (if stale >60 s), not via a live `TrackerNotifier`.
- Recency from `RecentManager`, not LocalSearch access times.
- No lumen-settings page in v1.
