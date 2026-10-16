using LumenCommon;
using Gtk;

namespace LumenSettings {

    public class PanelPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "panel"; } }
        public string title     { owned get { return "Panel"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        JsonStore store;
        JsonStore theme;
        JsonRows  store_rows;
        JsonRows  theme_rows;

#if WITH_WAYFIRE_CONFIG
        IniStore wf_store;
        const string PUSH_PLUGIN  = "wayfire-panel-push";
        const string PUSH_SECTION = "wayfire-panel-push";
        // lumen-panel always renders a fixed-height strip (App.ICON_ROW_HEIGHT);
        // the push reveal must free exactly that many pixels.
        const int PANEL_HEIGHT_PX = 60;

        // The tray-toggle hotkey is a Wayfire [command] binding: pressing the key
        // runs a one-shot dbus-send that calls the panel's ToggleTray method (see
        // lumen-panel/src/panel_service.vala). binding_/command_ share this suffix
        // so we can find and rewrite our own entry without touching the user's
        // other command bindings.
        const string TRAY_CMD_NAME = "lumen_tray";
        const string TRAY_DBUS_CMD =
            "dbus-send --session --dest=org.lumenshell.Panel "
            + "/org/lumenshell/Panel org.lumenshell.Panel1.ToggleTray";
#endif

        // Panel color is a shared RGB; normal mode ("at all times") and auto-hide
        // mode each layer their own opacity (alpha) on top of it.
        Gdk.RGBA panel_rgba;
        int panel_opacity;
        int autohide_opacity;

        public Gtk.Widget build() {
            store = new JsonStore(Paths.panel_json());
            theme = new JsonStore(Paths.theme_json());
            store_rows = new JsonRows(store);
            theme_rows = new JsonRows(theme);
#if WITH_WAYFIRE_CONFIG
            wf_store = new IniStore(Paths.wayfire_ini());
#endif

            var page = new Adw.PreferencesPage();

            var layout = new Adw.PreferencesGroup() { title = "Layout" };

            string[] pos_labels = { "Bottom", "Top" };
            string[] pos_values = { "bottom", "top" };
            var position_row = store_rows.combo_row("position", "Position", pos_labels, pos_values,
                "bottom", "which screen edge the panel sits on");
#if WITH_WAYFIRE_CONFIG
            // Keep the push plugin's edge aligned with the panel position.
            position_row.value_changed.connect((v) => {
                if (current_mode() != "push") return;
                wf_store.reload();
                wf_store.set_value(PUSH_SECTION, "direction", v);
                wf_store.save();
            });
#endif
            layout.add(position_row);
            page.add(layout);

            var colors = new Adw.PreferencesGroup() { title = "Colors" };

            var panel_bg_initial = theme.get_string("panel.background") ?? "#1a1d27ff";
            panel_rgba = ColorRow.parse_or_white(panel_bg_initial);
            panel_opacity = (int) (panel_rgba.alpha * 100 + 0.5);
            var autohide_initial = theme.get_string("panel.autohide-background");
            autohide_opacity = autohide_initial != null
                ? (int) (ColorRow.parse_or_white(autohide_initial).alpha * 100 + 0.5)
                : 50;

            var panel_color_row = new ColorRow("Panel color", panel_bg_initial,
                "panel color shown on the bottom strip");
            var panel_opacity_row = SettingsRows.spin_row("Panel opacity", 0, 100, 1, panel_opacity, 0,
                "panel opacity at all times, in percent");
            panel_color_row.value_changed.connect((hex) => {
                var picked = ColorRow.parse_or_white(hex);
                panel_rgba.red   = picked.red;
                panel_rgba.green = picked.green;
                panel_rgba.blue  = picked.blue;
                write_panel_colors();
                // Force the swatch to show the color at the configured opacity,
                // not whatever alpha the picker dialog returned.
                panel_color_row.set_color_hex(panel_bg_hex());
            });
            colors.add(panel_color_row);

            panel_opacity_row.notify["value"].connect(() => {
                panel_opacity = (int) panel_opacity_row.value;
                write_panel_colors();
                panel_color_row.set_color_hex(panel_bg_hex());
            });
            colors.add(panel_opacity_row);

            colors.add(theme_rows.color_row("tray.background",    "Tray background", "#222633ff", "tray icon background when not hovered"));
            colors.add(theme_rows.color_row("tray.icon-hover",    "Tray icon hover", "#2c3140ff", "tray icon background while the pointer is over it"));
            colors.add(theme_rows.color_row("app.hover",          "App hover",       "#2c3140ff", "taskbar app background while the pointer is over it"));
            colors.add(theme_rows.color_row("app.open-indicator-color", "Open app indicator", "#3d7affff", "color of the open-app dot, brackets, or shade"));

            var clock_group = new Adw.PreferencesGroup() { title = "Clock" };

            var fmt_initial = store.get_string("clock.format") ?? "%a %d %b  %H:%M";
            var fmt_row = new Adw.EntryRow() {
                title = "Format",
                text = fmt_initial,
                tooltip_text = "strftime pattern, e.g. %H:%M or %Y-%m-%d %H:%M",
            };
            fmt_row.changed.connect(() => {
                store.set_string("clock.format", fmt_row.text);
                store.save();
            });
            clock_group.add(fmt_row);

            page.add(clock_group);

            var behavior_group = new Adw.PreferencesGroup() { title = "Behavior" };

            string[] mode_labels = { "Always visible", "Auto-hide (overlay)", "Push reveal" };
            string[] mode_values = { "normal", "hidden", "push" };
            var mode_row = store_rows.combo_row("behavior.mode", "Panel mode", mode_labels, mode_values,
                current_mode(),
                "Always visible reserves space; Auto-hide reveals over windows; Push slides the whole screen aside to reveal the panel");
            mode_row.value_changed.connect((v) => {
                // Keep the legacy bool in sync for older panel builds.
                store.set_bool("behavior.auto-hide", v == "hidden" || v == "push");
                store.save();
#if WITH_WAYFIRE_CONFIG
                bool push = (v == "push");
                Wayfire.PluginList.set_enabled(wf_store, PUSH_PLUGIN, push);
                if (push) sync_push_options();
#endif
            });
            behavior_group.add(mode_row);

            behavior_group.add(store_rows.bool_row("app.launcher-button",
                "Show app launcher button", false,
                "Pin an app button to the left edge that opens the app drawer (peek)"));

#if WITH_WAYFIRE_CONFIG
            // Global shortcut to open/close the tray (Control Center). Stored as a
            // Wayfire [command] keybinding; Wayfire picks up the wayfire.ini edit
            // live, so no panel restart is needed. Right-click the button clears it.
            var tray_key_initial = wf_store.get_value("command", "binding_" + TRAY_CMD_NAME) ?? "";
            var tray_key_row = new BindingRow("Toggle tray shortcut", tray_key_initial,
                "global key that opens or closes the tray; right-click to clear");
            tray_key_row.value_changed.connect((binding) => set_tray_binding(binding));
            behavior_group.add(tray_key_row);
#endif

            var autohide_opacity_row = SettingsRows.spin_row("Auto-hide opacity", 0, 100, 1, autohide_opacity, 0,
                "panel opacity while auto-hidden, in percent (uses the panel color)");
            autohide_opacity_row.notify["value"].connect(() => {
                autohide_opacity = (int) autohide_opacity_row.value;
                theme.set_string("panel.autohide-background", autohide_hex());
                theme.save();
            });
            behavior_group.add(autohide_opacity_row);

            string[] active_labels = { "Underline", "Ring", "Sunshine", "Glass (navy)", "Circle (glass)" };
            string[] active_values = { "underline", "ring", "sunshine", "glass", "circle" };
            behavior_group.add(store_rows.combo_row("app.active-indicator", "Active app indicator",
                active_labels, active_values, "underline",
                "how the focused app is marked: an accent bar, a ring, sunshine rays, a navy glass disc, or a faint glass circle"));

            string[] ind_labels = { "Bottom shade", "Dot", "Corner brackets", "Glass (squared)", "Glass (rounded)", "None" };
            string[] ind_values = { "shade", "dot", "corners", "glass", "round", "none" };
            behavior_group.add(store_rows.combo_row("app.open-indicator", "Open app indicator",
                ind_labels, ind_values, "shade",
                "how a running app is marked apart from a pinned, closed one"));

            page.add(behavior_group);

            page.add(build_tray_group());

            var multi_group = new Adw.PreferencesGroup() { title = "Multi-monitor" };
            var multi_initial = store.get_bool("behavior.multi-monitor", false);

            var multi_row = store_rows.bool_row("behavior.multi-monitor",
                "Show panel on every screen", false,
                "Place a panel on each connected monitor");
            multi_group.add(multi_row);

            var per_row = store_rows.bool_row("behavior.per-monitor-apps",
                "Show only this screen's apps", false,
                "Each monitor's panel lists only the windows on that monitor");
            per_row.sensitive = multi_initial;
            multi_group.add(per_row);

            var tray_row = store_rows.bool_row("behavior.tray-all-monitors",
                "Show tray on every screen", false,
                "Each monitor's panel shows the tray area (system-tray icons stay on the primary)");
            tray_row.sensitive = multi_initial;
            multi_group.add(tray_row);

            // The two per-monitor options are meaningless without a panel on
            // every monitor, so they follow the master switch.
            multi_row.notify["active"].connect(() => {
                var v = multi_row.active;
                per_row.sensitive = v;
                tray_row.sensitive = v;
                if (!v) {
                    per_row.active = false;
                    tray_row.active = false;
                }
            });

            page.add(multi_group);

            page.add(colors);

            return page;
        }

        public override string? restart_target() { return "lumen-panel"; }

        // Build the "Tray applets" group: a drag-to-reorder list of every
        // catalog applet, ordered by the stored tray.order (catalog order for
        // any id not listed), each switch reflecting tray.disabled. Edits are
        // written straight to panel.json's tray.order/tray.disabled arrays; the
        // header Restart applies them (restart_target() is already lumen-panel).
        Adw.PreferencesGroup build_tray_group() {
            var stored_order = store.get_string_array("tray.order");
            var disabled_set = new Gee.HashSet<string>();
            foreach (var id in store.get_string_array("tray.disabled")) {
                disabled_set.add(id);
            }

            // Resolve display order: stored ids first (catalog ids only), then any
            // catalog id not yet listed appended in catalog order — same upgrade-
            // safe rule the panel uses, so the UI matches what the panel renders.
            var ordered = new Gee.ArrayList<string>();
            foreach (var id in stored_order) {
                if (catalog_has(id) && !ordered.contains(id)) ordered.add(id);
            }
            foreach (var info in LumenTray.CATALOG) {
                if (!ordered.contains(info.id)) ordered.add(info.id);
            }

            string[] ids = {};
            string[] labels = {};
            bool[] enabled = {};
            foreach (var id in ordered) {
                ids += id;
                labels += catalog_label(id);
                enabled += !disabled_set.contains(id);
            }

            var group = new Adw.PreferencesGroup() { title = "Tray applets" };
            var reorder = new ReorderList(ids, labels, enabled);
            reorder.changed.connect((order, disabled) => {
                store.set_string_array("tray.order",    order);
                store.set_string_array("tray.disabled", disabled);
                store.save();
            });
            group.add(reorder);
            return group;
        }

        static bool catalog_has(string id) {
            foreach (var info in LumenTray.CATALOG) {
                if (info.id == id) return true;
            }
            return false;
        }

        static string catalog_label(string id) {
            foreach (var info in LumenTray.CATALOG) {
                if (info.id == id) return info.label;
            }
            return id;
        }

        // Resolve the current panel mode, migrating the legacy auto-hide bool.
        string current_mode() {
            var m = store.get_string("behavior.mode");
            if (m != null) return m;
            return store.get_bool("behavior.auto-hide", false) ? "hidden" : "normal";
        }

#if WITH_WAYFIRE_CONFIG
        // Mirror the push plugin's edge + distance to the panel position/height.
        void sync_push_options() {
            wf_store.reload();   // pick up any [core] plugins edits from the Wayfire page
            var pos = store.get_string("position") ?? "bottom";
            var h   = "%d".printf(PANEL_HEIGHT_PX);
            wf_store.set_value(PUSH_SECTION, "direction", pos);
            wf_store.set_value(PUSH_SECTION, "push_px", h);
            wf_store.save();
        }

        // Write (or clear) the tray-toggle hotkey in wayfire.ini's [command]
        // section. An empty binding removes both keys so a cleared shortcut
        // doesn't leave a dangling command behind.
        void set_tray_binding(string binding) {
            wf_store.reload();   // don't clobber other [command]/[core] edits
            if (binding.strip() == "") {
                wf_store.remove_key("command", "binding_" + TRAY_CMD_NAME);
                wf_store.remove_key("command", "command_" + TRAY_CMD_NAME);
            } else {
                wf_store.set_value("command", "binding_" + TRAY_CMD_NAME, binding);
                wf_store.set_value("command", "command_" + TRAY_CMD_NAME, TRAY_DBUS_CMD);
            }
            wf_store.save();
        }
#endif

        void write_panel_colors() {
            theme.set_string("panel.background", panel_bg_hex());
            theme.set_string("panel.autohide-background", autohide_hex());
            theme.save();
        }

        // Both backdrops share the panel RGB; only the opacity (alpha) differs.
        string panel_bg_hex()  { return hex_at_opacity(panel_opacity); }
        string autohide_hex()  { return hex_at_opacity(autohide_opacity); }

        string hex_at_opacity(int percent) {
            var c = panel_rgba;
            c.alpha = (float) percent / 100f;
            return ColorRow.to_hex(c);
        }
    }
}
