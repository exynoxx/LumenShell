using Gtk;
using Gee;

namespace LumenSettings {

    public class DisplayPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "display"; } }
        public string title     { owned get { return "Display"; } }
        public string icon_name { owned get { return "video-display-symbolic"; } }

        OutputManager wlr = new OutputManager();
        Gee.ArrayList<OutputInfo> baseline = new Gee.ArrayList<OutputInfo>();
        Gee.ArrayList<OutputInfo> working  = new Gee.ArrayList<OutputInfo>();
        string primary_name = "";

        int sel = 0;
        bool dirty = false;
        bool building = false;        // suppress signal handlers during rebuild

        DisplayArranger arranger;
        Gtk.Box controls_holder;
        Gtk.Button apply_btn;
        Gtk.Revealer confirm_revealer;
        Gtk.Label confirm_label;
        uint countdown_id = 0;
        int countdown_left = 0;

        uint watch_id = 0;            // periodic queue pump that surfaces hotplugs
        bool reload_pending = false;

        public Gtk.Widget build() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18) {
                margin_top = 18, margin_bottom = 18,
                margin_start = 18, margin_end = 18,
            };

            wlr.init();
            if (!wlr.available()) {
                var bl = new BoxedList("Display");
                bl.add_row(new ActionRow("Output management unavailable",
                    "The compositor does not expose wlr-output-management-v1, so displays can't be configured here."));
                box.append(bl);
                return box;
            }

            DiagLog.log("page: build() — enumerating displays");
            baseline = wlr.enumerate();
            working = clone_list(baseline);
            primary_name = read_primary();
            DiagLog.log("page: primary=%s", primary_name != "" ? primary_name : "(none)");
            if (working.size > 0) sel = 0;

            arranger = new DisplayArranger();
            arranger.set_outputs(working);
            arranger.output_selected.connect((name) => {
                for (int i = 0; i < working.size; i++) {
                    if (working.get(i).name == name) { sel = i; break; }
                }
                rebuild_controls();
            });
            arranger.layout_changed.connect(() => mark_dirty());
            box.append(arranger);

            controls_holder = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            box.append(controls_holder);

            // Confirmation banner (hidden until Apply).
            confirm_revealer = new Gtk.Revealer() {
                transition_type = Gtk.RevealerTransitionType.SLIDE_DOWN,
                reveal_child = false,
            };
            var cb = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                margin_top = 6,
            };
            cb.add_css_class("lumen-confirm-bar");
            confirm_label = new Gtk.Label("Keep these display settings?") { hexpand = true, xalign = 0 };
            var keep = new Gtk.Button.with_label("Keep");
            keep.add_css_class("suggested-action");
            keep.clicked.connect(on_keep);
            var rev = new Gtk.Button.with_label("Revert");
            rev.clicked.connect(on_revert);
            cb.append(confirm_label);
            cb.append(rev);
            cb.append(keep);
            confirm_revealer.set_child(cb);
            box.append(confirm_revealer);

            // Apply bar.
            var bar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) {
                halign = Gtk.Align.END, margin_top = 6,
            };
            apply_btn = new Gtk.Button.with_label("Apply");
            apply_btn.add_css_class("suggested-action");
            apply_btn.sensitive = false;
            apply_btn.clicked.connect(on_apply);
            bar.append(apply_btn);
            box.append(bar);

            rebuild_controls();
            start_output_watch();
            return box;
        }

        public override string? restart_target() { return null; }

        // ---- live hotplug watch --------------------------------------------

        // Re-enumerate the page when a monitor is plugged in or unplugged while
        // the window is open. wlhooks fires `outputs_changed` only when the
        // connected SET of heads changes — but it only fires while the private
        // queue is dispatched, so a 1 s roundtrip drives it. Self-contained: no
        // fd watch to contend with GDK's read of the shared wl_display.
        void start_output_watch() {
            if (watch_id != 0) return;
            WLHooks.output_mgmt_register_outputs_changed(on_outputs_changed);
            watch_id = Timeout.add_seconds(1, () => {
                wlr.pump();
                return GLib.Source.CONTINUE;
            });
        }

        void on_outputs_changed() {
            // Fired from inside pump()'s roundtrip; defer the reload to idle so
            // we never re-enter wl_display_roundtrip_queue reentrantly.
            if (reload_pending) return;
            reload_pending = true;
            Idle.add(() => { reload_pending = false; reload_outputs(); return GLib.Source.REMOVE; });
        }

        // A monitor was added/removed: the live layout is now authoritative, so
        // discard any unsaved edits and rebuild from the new set.
        void reload_outputs() {
            DiagLog.log("page: outputs changed — reloading display list");
            stop_countdown();
            if (confirm_revealer != null) confirm_revealer.reveal_child = false;
            baseline = wlr.enumerate();
            working  = clone_list(baseline);
            primary_name = read_primary();
            sel = working.size > 0 ? 0 : -1;
            arranger.set_outputs(working);
            rebuild_controls();
            dirty = false;
            if (apply_btn != null) apply_btn.sensitive = false;
        }

        // ---- controls -------------------------------------------------------

        void rebuild_controls() {
            building = true;
            var child = controls_holder.get_first_child();
            while (child != null) {
                var next = child.get_next_sibling();
                controls_holder.remove(child);
                child = next;
            }
            if (sel < 0 || sel >= working.size) { building = false; return; }
            var o = working.get(sel);

            var bl = new BoxedList(o.description != "" ? o.description : o.name);

            // Enabled
            var en = new SwitchRow("Enabled", "Turn this display on or off", o.enabled);
            en.toggled.connect((v) => {
                if (building) return;
                if (!v && enabled_count() <= 1) {
                    // Don't allow disabling the last display.
                    en.sw.active = true;
                    return;
                }
                o.enabled = v;
                arranger.refresh();
                mark_dirty();
                rebuild_controls();
            });
            bl.add_row(en);

            if (o.enabled && o.current_mode != null) {
                // Resolution
                var res_keys = o.resolutions();
                string[] rlabels = res_keys.to_array();
                var res_row = new ComboRow("Resolution", rlabels, rlabels,
                    o.current_mode.res_key(), "");
                res_row.value_changed.connect((v) => {
                    if (building) return;
                    var cands = o.modes_for(v);
                    if (cands.size > 0) {
                        // keep closest refresh, default to highest
                        o.current_mode = cands.get(0);
                    }
                    arranger.refresh();
                    mark_dirty();
                    rebuild_controls();
                });
                bl.add_row(res_row);

                // Refresh
                var rmodes = o.modes_for(o.current_mode.res_key());
                string[] flabels = new string[rmodes.size];
                string[] fvalues = new string[rmodes.size];
                for (int i = 0; i < rmodes.size; i++) {
                    flabels[i] = rmodes.get(i).refresh_label();
                    fvalues[i] = rmodes.get(i).refresh_key();
                }
                var rinit = o.current_mode.refresh_key();
                var ref_row = new ComboRow("Refresh rate", flabels, fvalues, rinit, "");
                ref_row.value_changed.connect((v) => {
                    if (building) return;
                    foreach (var m in rmodes) {
                        if (m.refresh_key() == v) { o.current_mode = m; break; }
                    }
                    mark_dirty();
                });
                bl.add_row(ref_row);

                // Orientation
                string[] olabels = {
                    OutputTransform.NORMAL.label(),
                    OutputTransform.ROT_90.label(),
                    OutputTransform.ROT_180.label(),
                    OutputTransform.ROT_270.label(),
                    OutputTransform.FLIPPED.label(),
                    OutputTransform.FLIPPED_90.label(),
                    OutputTransform.FLIPPED_180.label(),
                    OutputTransform.FLIPPED_270.label(),
                };
                string[] ovalues = { "0","1","2","3","4","5","6","7" };
                var or_row = new ComboRow("Orientation", olabels, ovalues,
                    ((int) o.transform).to_string(), "");
                or_row.value_changed.connect((v) => {
                    if (building) return;
                    o.transform = OutputTransform.from_index(int.parse(v));
                    arranger.refresh();
                    mark_dirty();
                });
                bl.add_row(or_row);

                // Primary
                var pr = new SwitchRow("Primary display",
                    "Where the panel and app drawer anchor",
                    primary_name == o.name);
                pr.toggled.connect((v) => {
                    if (building) return;
                    if (v) { primary_name = o.name; mark_dirty(); }
                    else if (primary_name == o.name) { primary_name = ""; mark_dirty(); }
                });
                bl.add_row(pr);
            }

            controls_holder.append(bl);
            building = false;
        }

        int enabled_count() {
            int n = 0;
            foreach (var o in working) if (o.enabled) n++;
            return n;
        }

        void mark_dirty() {
            dirty = true;
            if (apply_btn != null) apply_btn.sensitive = true;
        }

        // ---- apply / revert -------------------------------------------------

        void on_apply() {
            log_working("apply requested");
            var err = wlr.apply_all(working);
            if (err != null) {
                confirm_label.label = "Failed to apply: " + err;
                confirm_revealer.reveal_child = true;
                return;
            }
            countdown_left = 15;
            update_countdown_label();
            confirm_revealer.reveal_child = true;
            apply_btn.sensitive = false;
            if (countdown_id != 0) Source.remove(countdown_id);
            countdown_id = Timeout.add_seconds(1, () => {
                countdown_left--;
                if (countdown_left <= 0) { on_revert(); return false; }
                update_countdown_label();
                return true;
            });
        }

        void update_countdown_label() {
            confirm_label.label =
                "Keep these display settings? Reverting in %ds".printf(countdown_left);
        }

        void on_keep() {
            DiagLog.log("page: KEEP — persisting to disk");
            stop_countdown();
            persist();
            save_profile();
            baseline = clone_list(working);
            dirty = false;
            apply_btn.sensitive = false;
            confirm_revealer.reveal_child = false;
        }

        void on_revert() {
            DiagLog.log("page: REVERT — restoring baseline (no disk write)");
            stop_countdown();
            wlr.apply_all(baseline);
            working = clone_list(baseline);
            arranger.set_outputs(working);
            if (sel >= working.size) sel = working.size > 0 ? 0 : -1;
            rebuild_controls();
            dirty = false;
            apply_btn.sensitive = false;
            confirm_revealer.reveal_child = false;
        }

        void stop_countdown() {
            if (countdown_id != 0) { Source.remove(countdown_id); countdown_id = 0; }
        }

        // ---- persistence ----------------------------------------------------

        void persist() {
            var wf = new IniStore(Paths.wayfire_ini());
            foreach (var o in working) {
                var sect = "output:" + o.name;
                if (!o.enabled) {
                    wf.set_value(sect, "mode", "off");
                    DiagLog.log("persist: [%s] mode=off", sect);
                    continue;
                }
                if (o.current_mode != null) {
                    wf.set_value(sect, "mode", o.current_mode.to_wayfire_arg());
                }
                wf.set_value(sect, "position", "%d,%d".printf(o.pos_x, o.pos_y));
                wf.set_value(sect, "transform", o.transform.to_arg());
                DiagLog.log("persist: [%s] mode=%s position=%d,%d transform=%s", sect,
                    o.current_mode != null ? o.current_mode.to_wayfire_arg() : "(none)",
                    o.pos_x, o.pos_y, o.transform.to_arg());
            }
            wf.save();
            DiagLog.log("persist: wrote %s", Paths.wayfire_ini());

            var disp = new IniStore(Paths.display_ini());
            disp.set_value("display", "primary", primary_name);
            disp.save();
            DiagLog.log("persist: wrote %s (primary=%s)", Paths.display_ini(), primary_name);
        }

        // Remember this layout, keyed by the connected monitor set (EDID), so
        // the lumen-session daemon can re-apply it when the same set reconnects.
        void save_profile() {
            // connector name -> stable EDID identity, from the live heads.
            var ident = new Gee.HashMap<string, string>();
            WLHooks.output_mgmt_for_each_head_identity((idx, name, make, model, serial, desc) => {
                ident.set(name, DisplayProfileStore.identity_for(make, model, serial, desc, name));
            });

            var prof = new DisplayProfile();
            foreach (var o in working) {
                var id = ident.has_key(o.name) ? ident.get(o.name)
                       : DisplayProfileStore.identity_for("", "", "", o.description, o.name);
                prof.outputs.add(id);
                var s = new DisplayOutputState();
                s.enabled = o.enabled && o.current_mode != null;
                if (o.current_mode != null) {
                    s.width       = o.current_mode.width;
                    s.height      = o.current_mode.height;
                    s.refresh_mhz = o.current_mode.refresh_mhz();
                }
                s.x = o.pos_x; s.y = o.pos_y;
                s.transform = (int) o.transform;
                prof.states.set(id, s);
            }
            DisplayProfileStore.save_or_update(prof);
            DiagLog.log("profile: saved layout for set [%s] -> %s",
                prof.set_key(), DisplayProfileStore.path());
        }

        // Snapshot the in-memory working layout to the diagnostic log.
        void log_working(string why) {
            DiagLog.log("page: working layout (%s):", why);
            foreach (var o in working) {
                DiagLog.log("    %s  enabled=%s  mode=%s  pos=%d,%d  transform=%s  primary=%s",
                    o.name, o.enabled.to_string(),
                    (o.enabled && o.current_mode != null) ? o.current_mode.to_arg() : "(off)",
                    o.pos_x, o.pos_y, o.transform.to_arg(),
                    (primary_name == o.name).to_string());
            }
        }

        string read_primary() {
            var disp = new IniStore(Paths.display_ini());
            return disp.get_value("display", "primary") ?? "";
        }

        // ---- helpers --------------------------------------------------------

        static Gee.ArrayList<OutputInfo> clone_list(Gee.ArrayList<OutputInfo> src) {
            var dst = new Gee.ArrayList<OutputInfo>();
            foreach (var o in src) dst.add(o.clone());
            return dst;
        }
    }
}
