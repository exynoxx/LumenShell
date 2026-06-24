using Gtk;

namespace LumenSettings {

    public class PanelPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "panel"; } }
        public string title     { owned get { return "Panel"; } }
        public string icon_name { owned get { return "preferences-system-symbolic"; } }

        JsonStore store;
        JsonStore theme;

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
#if WITH_WAYFIRE_CONFIG
            wf_store = new IniStore(Paths.wayfire_ini());
#endif

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            var layout = new BoxedList("Layout");

            string[] pos_labels = { "Bottom", "Top" };
            string[] pos_values = { "bottom", "top" };
            var pos_initial = store.get_string("position") ?? "bottom";
            var position_row = new ComboRow("Position", pos_labels, pos_values, pos_initial,
                "which screen edge the panel sits on");
            position_row.value_changed.connect((v) => {
                store.set_string("position", v);
                store.save();
#if WITH_WAYFIRE_CONFIG
                // Keep the push plugin's edge aligned with the panel position.
                if (current_mode() == "push") {
                    wf_store.reload();
                    wf_store.set_value(PUSH_SECTION, "direction", v);
                    wf_store.save();
                }
#endif
            });
            layout.add_row(position_row);
            box.append(layout);

            var colors = new BoxedList("Colors");

            var panel_bg_initial = theme.get_string("panel.background") ?? "#1a1d27ff";
            panel_rgba = parse_rgba(panel_bg_initial);
            panel_opacity = (int) (panel_rgba.alpha * 100 + 0.5);
            var autohide_initial = theme.get_string("panel.autohide-background");
            autohide_opacity = autohide_initial != null
                ? (int) (parse_rgba(autohide_initial).alpha * 100 + 0.5)
                : 50;

            var panel_color_row = new ColorRow("Panel color", panel_bg_initial,
                "panel color shown on the bottom strip");
            var panel_opacity_row = new SpinRow("Panel opacity", 0, 100, 1, panel_opacity, 0,
                "panel opacity at all times, in percent");
            panel_color_row.value_changed.connect((hex) => {
                var picked = parse_rgba(hex);
                panel_rgba.red   = picked.red;
                panel_rgba.green = picked.green;
                panel_rgba.blue  = picked.blue;
                write_panel_colors();
                // Force the swatch to show the color at the configured opacity,
                // not whatever alpha the picker dialog returned.
                panel_color_row.set_color_hex(panel_bg_hex());
            });
            colors.add_row(panel_color_row);

            panel_opacity_row.value_changed.connect((v) => {
                panel_opacity = (int) v;
                write_panel_colors();
                panel_color_row.set_color_hex(panel_bg_hex());
            });
            colors.add_row(panel_opacity_row);

            colors.add_row(color_row("tray.background",       "Tray background",       "#222633ff", "tray icon background when not hovered"));
            colors.add_row(color_row("tray.icon-hover",       "Tray icon hover",       "#2c3140ff", "tray icon background while the pointer is over it"));
            colors.add_row(color_row("app.hover",             "App hover",             "#2c3140ff", "taskbar app background while the pointer is over it"));
            colors.add_row(color_row("app.launching",         "App launching",         "#3d7affff", "taskbar app background while the app is starting up"));
            colors.add_row(color_row("app.open-indicator-color", "Open app indicator", "#3d7affff", "color of the open-app dot, brackets, or shade"));
            box.append(colors);

            var clock_group = new BoxedList("Clock");

            var fmt_initial = store.get_string("clock.format") ?? "%a %d %b  %H:%M";
            var fmt_row = new EntryRow("Format", fmt_initial, "strftime pattern, e.g. %H:%M or %Y-%m-%d %H:%M");
            fmt_row.value_changed.connect((v) => {
                store.set_string("clock.format", v);
                store.save();
            });
            clock_group.add_row(fmt_row);

            box.append(clock_group);

            var behavior_group = new BoxedList("Behavior");

            string[] mode_labels = { "Always visible", "Auto-hide (overlay)", "Push reveal" };
            string[] mode_values = { "normal", "hidden", "push" };
            var mode_initial = current_mode();
            var mode_row = new ComboRow("Panel mode", mode_labels, mode_values, mode_initial,
                "Always visible reserves space; Auto-hide reveals over windows; Push slides the whole screen aside to reveal the panel");
            mode_row.value_changed.connect((v) => {
                store.set_string("behavior.mode", v);
                // Keep the legacy bool in sync for older panel builds.
                store.set_bool("behavior.auto-hide", v == "hidden" || v == "push");
                store.save();
#if WITH_WAYFIRE_CONFIG
                bool push = (v == "push");
                set_plugin_enabled(PUSH_PLUGIN, push);
                if (push) sync_push_options();
#endif
            });
            behavior_group.add_row(mode_row);

            var launcher_initial = store.get_bool("app.launcher-button", false);
            var launcher_row = new SwitchRow("Show app launcher button",
                "Pin an app button to the left edge that opens the app drawer (peek)",
                launcher_initial);
            launcher_row.toggled.connect((v) => {
                store.set_bool("app.launcher-button", v);
                store.save();
            });
            behavior_group.add_row(launcher_row);

#if WITH_WAYFIRE_CONFIG
            // Global shortcut to open/close the tray (Control Center). Stored as a
            // Wayfire [command] keybinding; Wayfire picks up the wayfire.ini edit
            // live, so no panel restart is needed. Right-click the button clears it.
            var tray_key_initial = wf_store.get_value("command", "binding_" + TRAY_CMD_NAME) ?? "";
            var tray_key_row = new BindingRow("Toggle tray shortcut", tray_key_initial,
                "global key that opens or closes the tray; right-click to clear");
            tray_key_row.value_changed.connect((binding) => set_tray_binding(binding));
            behavior_group.add_row(tray_key_row);
#endif

            var autohide_opacity_row = new SpinRow("Auto-hide opacity", 0, 100, 1, autohide_opacity, 0,
                "panel opacity while auto-hidden, in percent (uses the panel color)");
            autohide_opacity_row.value_changed.connect((v) => {
                autohide_opacity = (int) v;
                theme.set_string("panel.autohide-background", autohide_hex());
                theme.save();
            });
            behavior_group.add_row(autohide_opacity_row);

            string[] ind_labels = { "Bottom shade", "Dot", "Corner brackets", "Glass (hover look)", "None" };
            string[] ind_values = { "shade", "dot", "corners", "glass", "none" };
            var ind_initial = store.get_string("app.open-indicator") ?? "shade";
            var ind_row = new ComboRow("Open app indicator", ind_labels, ind_values, ind_initial,
                "how a running app is marked apart from a pinned, closed one");
            ind_row.value_changed.connect((v) => {
                store.set_string("app.open-indicator", v);
                store.save();
            });
            behavior_group.add_row(ind_row);

            box.append(behavior_group);

            box.append(build_tray_group());

            var multi_group = new BoxedList("Multi-monitor");
            var multi_initial = store.get_bool("behavior.multi-monitor", false);
            var multi_row = new SwitchRow("Show panel on every screen",
                "Place a panel on each connected monitor", multi_initial);
            multi_group.add_row(multi_row);

            var per_initial = store.get_bool("behavior.per-monitor-apps", false);
            var per_row = new SwitchRow("Show only this screen's apps",
                "Each monitor's panel lists only the windows on that monitor", per_initial);
            per_row.sw.set_sensitive(multi_initial);
            multi_group.add_row(per_row);

            var tray_initial = store.get_bool("behavior.tray-all-monitors", false);
            var tray_row = new SwitchRow("Show tray on every screen",
                "Each monitor's panel shows the tray area (system-tray icons stay on the primary)", tray_initial);
            tray_row.sw.set_sensitive(multi_initial);
            multi_group.add_row(tray_row);

            multi_row.toggled.connect((v) => {
                store.set_bool("behavior.multi-monitor", v);
                store.save();
                per_row.sw.set_sensitive(v);
                tray_row.sw.set_sensitive(v);
                if (!v && per_row.sw.active) per_row.sw.active = false;
                if (!v && tray_row.sw.active) tray_row.sw.active = false;
            });
            per_row.toggled.connect((v) => {
                store.set_bool("behavior.per-monitor-apps", v);
                store.save();
            });
            tray_row.toggled.connect((v) => {
                store.set_bool("behavior.tray-all-monitors", v);
                store.save();
            });

            box.append(multi_group);

            return box;
        }

        public override string? restart_target() { return "lumen-panel"; }

        // Build the "Tray applets" group: a drag-to-reorder list of every
        // catalog applet, ordered by the stored tray.order (catalog order for
        // any id not listed), each switch reflecting tray.disabled. Edits are
        // written straight to panel.json's tray.order/tray.disabled arrays; the
        // header Restart applies them (restart_target() is already lumen-panel).
        Gtk.Widget build_tray_group() {
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

            var group = new BoxedList("Tray applets");
            var reorder = new ReorderList(ids, labels, enabled);
            reorder.changed.connect((order, disabled) => {
                store.set_string_array("tray.order",    order);
                store.set_string_array("tray.disabled", disabled);
                store.save();
            });
            group.add_row(reorder);
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

        // Add/remove a plugin from wayfire.ini's [core] plugins list, preserving
        // order and dropping duplicates.
        void set_plugin_enabled(string name, bool on) {
            wf_store.reload();   // fresh [core] plugins so we don't clobber the Wayfire page
            var raw = wf_store.get_value("core", "plugins") ?? "";
            var seen = new Gee.HashSet<string>();
            var ordered = new Gee.ArrayList<string>();
            foreach (var tok in raw.split(" ")) {
                var t = tok.strip();
                if (t == "") continue;
                if (!seen.contains(t)) { seen.add(t); ordered.add(t); }
            }
            if (on) {
                if (!seen.contains(name)) ordered.add(name);
            } else {
                ordered.remove(name);
            }
            var sb = new StringBuilder();
            for (int i = 0; i < ordered.size; i++) {
                if (i > 0) sb.append(" ");
                sb.append(ordered.get(i));
            }
            wf_store.set_value("core", "plugins", sb.str);
            wf_store.save();
        }
#endif

        ColorRow color_row(string key, string label, string fallback, string subtitle) {
            var initial = theme.get_string(key) ?? fallback;
            var row = new ColorRow(label, initial, subtitle);
            row.value_changed.connect((hex) => {
                theme.set_string(key, hex);
                theme.save();
            });
            return row;
        }

        void write_panel_colors() {
            theme.set_string("panel.background", panel_bg_hex());
            theme.set_string("panel.autohide-background", autohide_hex());
            theme.save();
        }

        // Both backdrops share the panel RGB; only the opacity (alpha) differs.
        string panel_bg_hex() { return rgba_hex(panel_rgba, panel_opacity); }
        string autohide_hex() { return rgba_hex(panel_rgba, autohide_opacity); }

        static string rgba_hex(Gdk.RGBA c, int opacity) {
            return "#%02X%02X%02X%02X".printf(
                (uint) (c.red   * 255 + 0.5),
                (uint) (c.green * 255 + 0.5),
                (uint) (c.blue  * 255 + 0.5),
                (uint) (opacity * 255 / 100));
        }

        static Gdk.RGBA parse_rgba(string s) {
            var c = Gdk.RGBA();
            if (!c.parse(s)) { c.red = 0; c.green = 0; c.blue = 0; c.alpha = 1; }
            return c;
        }
    }
}
