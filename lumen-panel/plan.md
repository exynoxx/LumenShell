Here is Claude's plan:
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
Lumen-Panel Comprehensive Code Review

Context

The lumen-panel codebase has grown organically and now mixes responsibilities, contains dead code, repeats logic between sibling files, and does heavy work (process spawning, I/O,
allocations) inside the per-frame render path. The user wants a clean, readable codebase where:

- composites only compose; primitives only draw
- render methods are cheap (state-change work is hoisted into the constructor or out-of-band handlers)
- single-line "command" calls aren't broken across many lines
- each class has a clear, single responsibility

This document is both the review (findings) and the execution plan (the refactor list keyed to those findings). Scope is limited to lumen-panel/src/ — no behavioural redesigns, only
structural cleanup.

---
Review Findings

A. Dead / commented-out code (delete outright)

┌─────────────────────────────────────────┬──────────┬────────────────────────────────────────────────────────────────────────────────────┐
│                  File                   │  Lines   │                                        What                                        │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/animation.vala                      │ 56–66    │ TransitionEmpty class — never instantiated                                         │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/animation.vala                      │ 88       │ commented-out print                                                                │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/animation.vala                      │ 115–162  │ huge commented-out MoveTransition block                                            │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/components/trays/itray.vala         │ 7–12     │ commented-out method blocks                                                        │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/components/trays/itray.vala         │ 21–25    │ IExpandable interface — never used                                                 │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/utils.vala                          │ 235, 244 │ leftover debug print() calls                                                       │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/utils.vala                          │ 256–264  │ last_time static + elapsed_ms() — unreferenced                                     │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/main.vala                           │ 5        │ KICKOFF_ID = uint.MAX — unreferenced                                               │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/components/trays/iconandtext.vala   │ 16–17    │ last_mx/last_my — written but never read by any subclass                           │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/components/trays/iconandtext.vala   │ 13, 27   │ text field + set_text — text is never rendered (BatteryTray writes it for nothing) │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────────────────────────────────┤
│ src/components/trays/hoverableicon.vala │ 68–70    │ load() is just an alias for set_icon()                                             │
└─────────────────────────────────────────┴──────────┴────────────────────────────────────────────────────────────────────────────────────┘

B. Hardcoded absolute paths (collapse to one named constant per path)

┌─────────────────────────────────────────┬──────────┬────────────────────────────────────────────────────────┐
│                  File                   │   Line   │                          Path                          │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────┤
│ src/components/app.vala                 │ 128, 156 │ /home/nicholas/.../Kickoff/main (twice)                │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────┤
│ src/components/app.vala                 │ 199, 212 │ /home/nicholas/.../lumen-panel/src/res/app.svg (twice) │
├─────────────────────────────────────────┼──────────┼────────────────────────────────────────────────────────┤
│ src/components/trays/hoverableicon.vala │ 6        │ base_path = "/home/nicholas/.../src/res/"              │
└─────────────────────────────────────────┴──────────┴────────────────────────────────────────────────────────┘

Per the user decision: replace with named constants only — no env var indirection. Add at top of utils.vala:

public const string RES_DIR    = "/home/nicholas/Dokumenter/layer-shell-experiments/lumen-panel/src/res/";
public const string KICKOFF_BIN = "/home/nicholas/Dokumenter/layer-shell-experiments/Kickoff/main";

hoverableicon.vala base_path references RES_DIR; app.vala references RES_DIR for the fallback icon and KICKOFF_BIN for the launcher spawn (one definition, used in both on_click and
launch_new_window).

C. Heavy work inside render() (hoist to ctor or signal-driven cache)

File: src/components/trays/sound.vala
Line(s): 51–56
Issue: SoundTray.render() polls pactl/wpctl (refresh_state()) every ~1.2 s inside the render loop. Spawning processes from render is the worst offender.
Fix: Move polling to GLib.Timeout.add(1500, ...) (already used by SoundPage.on_activate) — the tray icon should subscribe to _page.state_changed, not poll.
────────────────────────────────────────
File: src/components/panel.vala
Line(s): 230, 451
Issue: update_input_region() runs every frame and calls WLHooks.get_screen_size() per call.
Fix: Cache screen_width/screen_height once in the ctor (already cached partially as screen_width); only call WLHooks.set_input_region() when tray.expanded_height or popup_h changes.
────────────────────────────────────────
File: src/components/panel.vala
Line(s): 407–412
Issue: render_popup() builds 6 Color literals per frame.
Fix: Move to private fields initialised in ctor: bg_color, border_color, sep_color, text_color, action_color, action_bg_color.
────────────────────────────────────────
File: src/components/panel.vala
Line(s): 446
Issue: popup_action_label(i) allocates a string per frame.
Fix: Cache the action labels in show_popup_for() / when is_pinned or has_open_windows() change — store a string[3] popup_labels.
────────────────────────────────────────
File: src/components/tray.vala
Line(s): 228, 234–250
Issue: render() calls layout_children() every frame; many Color literals constructed inline.
Fix: Layout only when expanded_height changes (track previous). Cache colours as fields.
────────────────────────────────────────
File: src/components/trays/wifipage.vala
Line(s): 159, 170, 175, 180, 195, 199, 230, 233, 242, 259, 270, 282, 287–289, 306–308
Issue: Header text width calc, ~15 inline Color literals, button colour reassignments per frame.
Fix: (1) Cache colours on the page as fields. (2) Cache chip_tw = ctx.width_of(cached_chip_txt, ...) whenever cached_chip_txt is updated (update_connection_chip()). (3) Stop reassigning
button colours from inside render_pass() — set them only when the connect/disconnect mode changes (similar to apply_mute_visuals pattern).
────────────────────────────────────────
File: src/components/trays/soundpage.vala
Line(s): 182, 200
Issue: Re-computes ctx.width_of(cached_pct_txt, 12.5f) every frame.
Fix: Cache the width into cached_pct_w whenever cached_pct_txt changes (in apply_mute_visuals).
────────────────────────────────────────
File: src/components/trays/batterypage.vala
Line(s): 76
Issue: Re-computes width_of(cached_pct_str, 11f) every frame.
Fix: Cache as cached_pct_w in refresh().
────────────────────────────────────────
File: src/components/trays/wifipage.vala
Line(s): 162–167, 188–214, 277–314
Issue: Bounds re-set on refresh_button, connect_button, disconnect_button, password_field every frame.
Fix: Bounds depend on the dynamic content rect, so this is unavoidable per-frame unless geometry is split: page receives only the rect once per state change (call relayout(rect) from
Tray
when expanded_height settles or first becomes non-zero), then render() only does draws. Acceptable simpler change: move all set_bounds calls to a single relayout() method invoked from
render() first.
────────────────────────────────────────
File: src/common/textfield.vala
Line(s): 96–100
Issue: obscure_text rebuilds a "•"-string with += in a per-character loop every frame.
Fix: Cache display_text whenever text changes; use string.nfill(text.length, '•') for the obscured form.
────────────────────────────────────────
File: src/components/trays/clock.vala
Line(s): 45–47
Issue: OK — string only rebuilt every 1 s. Keep as-is.
Fix:

D. Mixed / wrong responsibilities (single-responsibility violations)

┌──────────────────────────────┬─────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────────┐
│            Class             │                       Currently does                        │                                    Suggested split                                    │
├──────────────────────────────┼─────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
│ Panel                        │ App registry, input dispatch, pin persistence, popup state  │ Extract AppPopup class (popup_x/y/h/hovered/pressed, show_for(App), render(ctx),      │
│ (src/components/panel.vala)  │ + popup rendering, layer-shell input region. ~460 lines.    │ hit-testing, action labels). Panel keeps the registry + dispatch only.                │
├──────────────────────────────┼─────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
│                              │ Both read /sys/class/power_supply/BAT0/... independently    │ New BatteryService (fields + single refresh() reading sysfs once, signal              │
│ BatteryTray + BatteryPage    │ with private duplicate sysfs/sysfs_int.                     │ state_changed). BatteryTray becomes display-only on the service; BatteryPage consumes │
│                              │                                                             │  the same service.                                                                    │
├──────────────────────────────┼─────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
│                              │ Both spawn nmcli independently. Both have an identical      │ New NmcliClient exposing query_state() → {connected_ssid, link_state, device},        │
│ WifiTray + WifiPage          │ split_nmcli_terse() (wifi.vala:119–154,                     │ scan_networks(rescan: bool), connect(ssid, pw), disconnect(). Move                    │
│                              │ wifipage.vala:596–631).                                     │ split_nmcli_terse() into it. Both UI classes call the client.                         │
├──────────────────────────────┼─────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
│                              │ Mixes pactl/wpctl shelling, parsing, regex, and rendering   │ Extract PactlClient (all run_pactl_sync, query_*, parse_sink_descriptions,            │
│ SoundPage                    │ in one ~470-line file.                                      │ pretty_sink_name, first_percent, parse_wpctl_percent, shell_quote). SoundPage keeps   │
│                              │                                                             │ UI + sink-row rendering.                                                              │
├──────────────────────────────┼─────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
│ SoundPage.SinkRow            │ Simple primitive component but lives nested inside          │ Move to its own src/common/uisinkrow.vala or keep nested but rename if used only here │
│                              │ SoundPage.                                                  │  (current placement is fine — note it as acceptable).                                 │
└──────────────────────────────┴─────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────────┘

E. UI-component composition rule (composites must only compose)

The user's rule: a UI component is either a primitive (button/text/icon/bar) or a composite that only positions and calls into children.

Violators today:

1. WifiPage.render() directly emits draw_rect_rounded, draw_rect, pdt, pdt_center for the header chip and the network rows. The chip is a tiny composite (rounded rect + text) — extract
UiChip { text, color, set_bounds, render }. The network row is a composite (signal bars + text + optional lock + optional disconnect button) — extract WifiRow similarly. Then
WifiPage.render() is only positioning + delegation. Same for render_pass(): extract UiPasswordRow { textfield + connect_button } or simply call children without primitive draws.
2. SoundPage.render() has the same chip pattern (lines 182–186) — reuse the extracted UiChip.
3. Panel.render_popup() is a self-contained popup composite. After Section D extraction, the new AppPopup becomes a proper composite: rounded-rect bg primitive + N PopupRow children.
Internally each PopupRow is (optional separator + hover bg + label) and renders itself.
4. Tray.render() correctly delegates to children and only draws the container background + separator + stencil mask. The container background and separator could be extracted to a
UiPanelFrame primitive, but this is borderline (acceptable as-is).
5. App.render() is a primitive itself (icon tile). Acceptable.
6. SoundTray.render() mixes a primitive pdt(...) for the volume label with the icon child. Either treat the whole SoundTray as a primitive composite (acceptable) or extract a tiny UiText
{ string, color, set_position, render } so SoundTray only composes (icon + UiText). Recommendation: extract UiText — it will collapse half a dozen pdt(...) calls across the codebase
into a reusable primitive.

F. Hacks / smells

1. src/components/panel.vala:69+ — the body of Panel from line 69 onward is indented at 12 spaces (the rest of the file is at 4). Reformat the whole class.
2. src/components/trays/wifipage.vala:284–290, 303–309 — connect_btn_is_disconnect is a sentinel that flips inside render_pass() to prevent re-applying colours every frame. This is a
workaround for the fact that the button's mode ("Connect" vs "Disconnect") isn't an explicit property. Replace with a proper connect_button.set_mode(Mode.Connect | Disconnect) method (or
stop swapping the same button — use two UiButton instances, one rendered conditionally).
3. src/components/trays/iconandtext.vala:21 — constructor takes Context ctx but never uses it; this dead parameter has propagated into WifiTray, BatteryTray, ExitTray, plus the analogous
unused param in Clock. Remove from base + all call sites. (Note: SoundTray is a sibling that does use ctx for width_of — keep there.)
4. src/animation.vala:47 — *ref_x += ex - (*ref_x); is a convoluted way to write *ref_x = ex;. Replace.
5. src/animation.vala:8–10 — easeOutExpo is an instance method on the Transition interface; it's stateless. Make it a free function or a static on the class; remove from the interface.
6. src/components/trays/hoverableicon.vala:79–90 — the hover/selected branch resets set_tex_color({1,1,1,1}) but the non-hover branch does not. Asymmetric — fragile contract for callers
(WifiTray.render does manual reset at line 116, but only because of this). Make the icon always render with a known set_tex_color and remove the resets at call sites; or document that
the icon is colour-neutral.
7. src/ini.vala:6 — function name Get_key_value violates Vala/GLib convention (should be get_key_value). One caller (utils.vala:152, 154) — easy rename.
8. src/components/panel.vala:9–11 — APP_UNDERLINE_Y, APP_Y, APP_HEIGHT, APP_WIDTH are app-related constants living in panel.vala. Move to app.vala.
9. src/components/trays/exit.vala:12 — hardcoded pkill wayfire. Acceptable as defaults but should be a constant at the top of the file or driven by env var, so it can be changed without
touching the click handler.
10. src/components/trays/wifipage.vala:20, 123, 403, 421, 460–464, 469, 473, 495, 505, 509, 516, 545, 557–561, 581 — the DEBUG_WIFI flag and ~15 conditional print statements clutter the
file. Remove or replace with a single wifi_debug(string) helper at minimum.
11. src/components/trays/soundpage.vala:159–164 — closure captures idx = i; for sink-row signal connect — this is a Vala loop-capture pitfall. Fine as-is but worth a one-line // capture
i for closure comment to keep the next reader sane (currently not commented).
12. src/components/trays/wifipage.vala:518–522 — background thread mutates nets, connected, scanning, selected_row directly from a worker thread; render() reads them on the main thread.
There is no synchronisation. The data types are pointers/strings so partial reads are unlikely to crash but can produce a torn frame. Use GLib.Idle.add(...) to apply the update on the
main thread.
13. src/main.vala:6–8 — three free-floating globals (redraw, panel, animations). panel is only needed inside main() for the closures and isn't read elsewhere — make it a local. Keep
redraw and animations (they are widely used and replacing them is out of scope).

G. Multi-line "command" calls to collapse to one line

The user specifically asked for command-shape calls (single function call with arg list) on one line. Worst offenders:

- src/components/panel.vala:223 — ctx.draw_rect(active.x, APP_UNDERLINE_Y, APP_WIDTH, UNDERLINE_HEIGHT, color); is fine; but panel.vala:308 and panel.vala:414–446 have many
ctx.draw_rect_rounded(...,\n    Color(){...}) split across two lines.
- src/components/tray.vala:117–123, 138–139, 234–235, 243–244, 248–249 — animations.add(new Transition1D(EXPAND_ANIM_ID, &expanded_height, EXPAND_FULL, 0.28d)); and the
ctx.draw_rect_rounded(... , Color(){...}) calls are broken across lines.
- src/components/trays/wifipage.vala:172–175, 178–181, 193–195, 197–199, 229–231, 232–234, 269–270 — ctx.draw_rect_rounded(... , Color(){...}) calls split.
- src/components/trays/soundpage.vala:185, 194, 211 — same pattern.
- src/components/trays/batterypage.vala:59, 67, 77, 92, 93 — pdt(... , Color(){...}) split — these are all single-call lines.

Once colours are pulled into named fields (Section C), most of these collapse naturally because the trailing Color(){...} argument becomes a short identifier.

H. Duplication

┌──────────────────────────────────────────────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                 Code                                 │                                                    Files                                                     │
├──────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ split_nmcli_terse()                                                  │ src/components/trays/wifi.vala:119–154 and src/components/trays/wifipage.vala:596–631 (byte-identical) —     │
│                                                                      │ fold into NmcliClient.                                                                                       │
├──────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ sysfs(name) / sysfs_int(name)                                        │ src/components/trays/battery.vala:63–76 and src/components/trays/batterypage.vala:159–172 — fold into        │
│                                                                      │ BatteryService.                                                                                              │
├──────────────────────────────────────────────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Color(){r=1f, g=1f, b=1f, a=1f} (white) and Color(){r=0,g=0,b=0,a=0} │ Many places. Add module-level WHITE, TRANSPARENT, SEPARATOR constants in a small colors.vala.                │
│  (transparent)                                                       │                                                                                                              │
└──────────────────────────────────────────────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

---
Recommended Refactor Order (smallest blast radius first)

1. Pure deletions (Section A + obvious cleanup): commented blocks, dead fields, IExpandable, TransitionEmpty, KICKOFF_ID, last_time, elapsed_ms, Get_key_value rename. Touches no
behaviour.
2. Indentation + style: re-indent Panel body (Section F.1); collapse the multi-line draw_*/pdt/animations.add(...) calls (Section G); remove ctx parameter from IconAndText ctor and the
three callers (Section F.3); replace *ref_x += ex - (*ref_x) with *ref_x = ex (Section F.4).
3. Hoist colours to fields in Panel, Tray, WifiPage, SoundPage, BatteryPage, UiButton, UiHorizontalSlider, UiTextField, UiSignalBars (most colours already are fields — finish the job for
panel.vala/tray.vala/the page files).
4. Cache width_of results when source string changes (WifiPage.cached_chip_tw, SoundPage.cached_pct_w, BatteryPage.cached_pct_w, UiTextField.cached_display_w).
5. Move SoundTray polling from render() into a GLib.Timeout started in its ctor; subscribe SoundTray to _page.state_changed (already wired) instead of polling.
6. Stop calling update_input_region() from render — wire it to popup/tray expansion changes only.
7. Path constants: add public const string RES_DIR and public const string KICKOFF_BIN at the top of src/utils.vala. Replace the three hardcoded literals (one in hoverableicon.vala, two
in app.vala).
8. Hardcoded pkill wayfire: lift to a const string EXIT_CMD at the top of exit.vala.
9. Extract NmcliClient (src/services/nmcli.vala or in src/components/trays/) — fold the duplicate split_nmcli_terse, query_connected, get_wifi_device, fetch_nets, connect, disconnect.
WifiTray and WifiPage consume it.
10. Extract BatteryService with one sysfs read path; BatteryTray and BatteryPage consume it. Subscribe via signal.
11. Extract PactlClient out of SoundPage. SoundPage keeps UI; SoundTray already subscribes to state_changed.
12. Extract AppPopup out of Panel. ~150 lines move out; Panel.render() becomes 1 line of popup delegation.
13. Extract UiChip primitive; reuse in WifiPage header chip and SoundPage header chip. Extract UiText primitive; reuse where pdt(... , col) is called only to render a single label.
14. Extract WifiRow (and optionally UiPasswordRow) so WifiPage.render() only positions children.
15. Apply GLib.Idle.add synchronisation to WifiPage.refresh_nets_async so the nets/connected/scanning fields are mutated on the main thread (Section F.12).
16. Clean up DEBUG_WIFI prints — collapse to a single helper or remove.

Steps 1–8 are mechanical and risk-free. Steps 9–14 change file structure but preserve behaviour. Step 15 is the only thread-safety fix.

---
Critical Files (paths reviewers should focus on)

- src/components/panel.vala — popup extraction, indentation, colour cache, stop calling input-region from render
- src/components/tray.vala — colour cache, layout-on-change, collapse multi-line draw calls
- src/components/trays/wifipage.vala — biggest single file, biggest refactor target
- src/components/trays/soundpage.vala — pactl extraction, colour/string caches
- src/components/trays/battery.vala + batterypage.vala — service extraction