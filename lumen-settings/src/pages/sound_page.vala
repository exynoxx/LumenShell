using Gtk;

namespace LumenSettings {

    // Per-application audio row widgets, kept in an index-keyed map so the
    // 1.5s poll can diff (add/remove/update) rather than rebuild the list.
    private class AppRowWidgets : GLib.Object {
        public Adw.ActionRow row;
        public Gtk.Button mute_btn;
        public Gtk.Scale  scale;
        public Gtk.Label  label;
        public bool       dragging = false;
    }

    // Live output + input audio management page. Reuses the shared lumen-common
    // SoundService/PactlClient backend; the input level meter is opt-in and
    // gated on visibility so Settings never holds a capture stream open idle.
    public class SoundPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "sound"; } }
        public string title     { owned get { return "Sound"; } }
        public string icon_name { owned get { return "audio-volume-high-symbolic"; } }

        public override string? restart_target() { return null; }

        // Sets a captured bool field; used to wire scale drag tracking.
        private delegate void SetBool(bool v);

        SoundService service;
        PactlClient  pactl = new PactlClient();  // page-local, for over-100% writes
        bool syncing = false;

        // Output widgets
        ComboRow    output_combo;
        Gtk.Button  out_mute_btn;
        Gtk.Scale   out_scale;
        Gtk.Label   out_label;
        Adw.SwitchRow allow_over_row;
        bool        out_dragging = false;
        bool        allow_over = false;
        string      sinks_sig = "";

        // Input widgets
        Adw.PreferencesGroup input_group;
        ComboRow    input_combo;
        Gtk.Button  in_mute_btn;
        Gtk.Scale   in_scale;
        Gtk.Label   in_label;
        Gtk.LevelBar? level_bar = null;
        Gtk.ToggleButton? level_toggle = null;
        bool        in_dragging = false;
        string      sources_sig = "";

        // Applications
        Adw.PreferencesGroup apps_group;
        Adw.ActionRow apps_empty_row;
        GLib.HashTable<string, AppRowWidgets> app_rows;

        // Alerts
        Adw.ActionRow alert_row;
        Gtk.Scale   alert_scale;
        string      alert_index = "";
        bool        alert_dragging = false;

        public Gtk.Widget build() {
            service   = new SoundService();
            app_rows  = new GLib.HashTable<string, AppRowWidgets>(str_hash, str_equal);

            var page = new Adw.PreferencesPage();

            page.add(build_output_group());
            page.add(build_input_group());
            page.add(build_apps_group());
            page.add(build_alerts_group());

            service.state_changed.connect(sync_ui);
            sync_ui();

            return page;
        }

        // ---------------- Output ----------------

        Adw.PreferencesGroup build_output_group() {
            var group = new Adw.PreferencesGroup() { title = "Output" };

            output_combo = new ComboRow("Output Device", {}, {}, null,
                                        "device audio plays through");
            output_combo.value_changed.connect((v) => {
                if (syncing) return;
                service.change_default_sink(v);
            });
            group.add(output_combo);

            out_scale = make_scale(0, 100);
            track_drag(out_scale, (v) => { out_dragging = v; });
            out_scale.value_changed.connect(() => {
                if (syncing) return;
                int v = (int) out_scale.get_value();
                if (v <= 100) {
                    service.change_volume(v);
                } else {
                    // Over-amplification: not clamped by change_volume().
                    pactl.set_sink_volume_by_id(service.default_sink, v, 150);
                }
                out_label.label = "%d%%".printf(v);
            });

            out_mute_btn = flat_icon_button("audio-volume-high-symbolic");
            out_mute_btn.clicked.connect(() => {
                if (syncing) return;
                service.toggle_mute();
            });

            out_label = pct_label();

            var vrow = new Adw.ActionRow() { title = "Output Volume" };
            vrow.add_suffix(slider_box(out_mute_btn, out_scale, out_label));
            group.add(vrow);

            allow_over_row = new Adw.SwitchRow() {
                title = "Allow volume above 100%", subtitle = "over-amplify the output up to 150%",
            };
            allow_over_row.notify["active"].connect(() => {
                var on = allow_over_row.active;
                allow_over = on;
                out_scale.set_range(0, on ? 150 : 100);
                if (!on && (int) out_scale.get_value() > 100)
                    service.change_volume(100);
            });
            group.add(allow_over_row);

            return group;
        }

        // ---------------- Input ----------------

        Adw.PreferencesGroup build_input_group() {
            input_group = new Adw.PreferencesGroup() { title = "Input" };

            input_combo = new ComboRow("Input Device", {}, {}, null,
                                       "microphone or capture device");
            input_combo.value_changed.connect((v) => {
                if (syncing) return;
                service.change_default_source(v);
            });
            input_group.add(input_combo);

            in_scale = make_scale(0, 100);
            track_drag(in_scale, (v) => { in_dragging = v; });
            in_scale.value_changed.connect(() => {
                if (syncing) return;
                int v = (int) in_scale.get_value();
                service.change_input_volume(v);
                in_label.label = "%d%%".printf(v);
            });

            in_mute_btn = flat_icon_button("audio-input-microphone-symbolic");
            in_mute_btn.clicked.connect(() => {
                if (syncing) return;
                service.toggle_input_mute();
            });

            in_label = pct_label();

            var vrow = new Adw.ActionRow() { title = "Input Volume" };
            vrow.add_suffix(slider_box(in_mute_btn, in_scale, in_label));
            input_group.add(vrow);

            // Level meter only when parec is present. Opening the meter starts a
            // real mic capture stream, which forces Bluetooth headsets from A2DP
            // down to the HSP/HFP call profile. So it is strictly manual: the
            // capture opens only while the user holds the Test toggle on, never
            // just because the page is visible.
            if (service.meter_available()) {
                level_bar = new Gtk.LevelBar.for_interval(0.0, 1.0) {
                    mode = Gtk.LevelBarMode.CONTINUOUS,
                    hexpand = false,
                    width_request = 160,
                    valign = Gtk.Align.CENTER,
                };
                level_toggle = new Gtk.ToggleButton.with_label("Test") {
                    valign = Gtk.Align.CENTER,
                };
                level_toggle.add_css_class("flat");
                level_toggle.toggled.connect(() => {
                    if (level_toggle.active)
                        service.start_input_monitor();
                    else
                        service.stop_input_monitor();
                });

                var lbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
                lbox.append(level_toggle);
                lbox.append(level_bar);

                var lrow = new Adw.ActionRow() {
                    title = "Input Level",
                    subtitle = "Opening the meter may switch Bluetooth headsets to call quality",
                };
                lrow.add_suffix(lbox);
                input_group.add(lrow);

                service.input_peak_changed.connect((peak) => {
                    if (level_bar != null) level_bar.value = peak;
                });

                // Safety only: if the group leaves the screen (page switched,
                // window closed) while the meter is on, stop the capture so we
                // never leave a Bluetooth headset stuck in the call profile.
                input_group.unmap.connect(() => {
                    if (level_toggle != null && level_toggle.active)
                        level_toggle.active = false;
                });
            }

            return input_group;
        }

        // ---------------- Applications ----------------

        Adw.PreferencesGroup build_apps_group() {
            apps_group = new Adw.PreferencesGroup() { title = "Applications" };
            apps_empty_row = new Adw.ActionRow() { title = "No applications playing audio" };
            apps_empty_row.sensitive = false;
            apps_group.add(apps_empty_row);
            return apps_group;
        }

        // ---------------- Alerts (best-effort) ----------------
        // Full GNOME "system sounds" parity is not achievable via pactl alone —
        // PulseAudio exposes system sounds only as a transient sink-input, so we
        // can steer it only while it is actively playing. We target the
        // "System Sounds" stream when present and disable the row otherwise.
        Adw.PreferencesGroup build_alerts_group() {
            var group = new Adw.PreferencesGroup() { title = "Alerts" };
            alert_scale = make_scale(0, 100);
            track_drag(alert_scale, (v) => { alert_dragging = v; });
            alert_scale.value_changed.connect(() => {
                if (syncing) return;
                if (alert_index == "") return;
                service.change_sink_input_volume(alert_index, (int) alert_scale.get_value());
            });
            alert_row = new Adw.ActionRow() {
                title = "Alert volume", subtitle = "volume of system alert sounds",
            };
            var abox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            abox.append(alert_scale);
            alert_row.add_suffix(abox);
            group.add(alert_row);
            return group;
        }

        // ---------------- Live sync ----------------

        void sync_ui() {
            syncing = true;

            // --- Output device combo ---
            var new_sinks_sig = sink_signature(service.sinks);
            if (new_sinks_sig != sinks_sig) {
                sinks_sig = new_sinks_sig;
                string[] labels = {}, values = {};
                foreach (var s in service.sinks) { labels += s.name; values += s.id; }
                output_combo.repopulate(labels, values, service.default_sink);
            }

            // --- Output volume / mute ---
            if (!out_dragging && (int) out_scale.get_value() != service.volume_percent
                && !(allow_over && (int) out_scale.get_value() > 100)) {
                out_scale.set_value(service.volume_percent);
            }
            out_label.label = "%d%%".printf((int) out_scale.get_value());
            set_mute_icon(out_mute_btn, service.muted,
                          "audio-volume-muted-symbolic", "audio-volume-high-symbolic");

            // --- Input device combo (filter out .monitor sources) ---
            string[] src_labels = {}, src_values = {};
            foreach (var s in service.sources) {
                if (s.monitor) continue;
                src_labels += s.name;
                src_values += s.id;
            }
            var new_sources_sig = string.joinv("|", src_values);
            if (new_sources_sig != sources_sig) {
                sources_sig = new_sources_sig;
                input_combo.repopulate(src_labels, src_values, service.default_source);
            }

            // --- Input volume / mute ---
            if (!in_dragging && (int) in_scale.get_value() != service.input_volume_percent) {
                in_scale.set_value(service.input_volume_percent);
            }
            in_label.label = "%d%%".printf((int) in_scale.get_value());
            set_mute_icon(in_mute_btn, service.input_muted,
                          "microphone-sensitivity-muted-symbolic",
                          "audio-input-microphone-symbolic");

            // --- Applications diff ---
            sync_app_rows();

            // --- Alerts ---
            sync_alert_row();

            syncing = false;
        }

        void sync_app_rows() {
            var seen = new GLib.HashTable<string, bool>(str_hash, str_equal);

            foreach (var s in service.sink_inputs) {
                if (is_system_sounds(s.app_name)) continue;  // shown in Alerts
                seen.insert(s.index, true);

                var aw = app_rows.lookup(s.index);
                if (aw == null) {
                    aw = make_app_row(s);
                    app_rows.insert(s.index, aw);
                    apps_group.add(aw.row);
                } else {
                    aw.row.title = s.app_name;
                }
                if (!aw.dragging && (int) aw.scale.get_value() != s.volume_pct)
                    aw.scale.set_value(s.volume_pct);
                set_mute_icon(aw.mute_btn, s.muted,
                              "audio-volume-muted-symbolic", "audio-volume-high-symbolic");
            }

            // Remove rows whose stream is gone.
            string[] stale = {};
            app_rows.foreach((idx, aw) => {
                if (!seen.contains(idx)) stale += idx;
            });
            foreach (var idx in stale) {
                var aw = app_rows.lookup(idx);
                if (aw != null) apps_group.remove(aw.row);
                app_rows.remove(idx);
            }

            apps_empty_row.visible = (app_rows.size() == 0);
        }

        AppRowWidgets make_app_row(StreamInfo s) {
            var aw = new AppRowWidgets();
            aw.row      = new Adw.ActionRow() { title = s.app_name, use_markup = false };
            aw.scale    = make_scale(0, 100);
            aw.mute_btn = flat_icon_button("audio-volume-high-symbolic");
            aw.label    = pct_label();

            string index = s.index;
            track_drag(aw.scale, (v) => { aw.dragging = v; });
            aw.scale.value_changed.connect(() => {
                if (syncing) return;
                int v = (int) aw.scale.get_value();
                service.change_sink_input_volume(index, v);
                aw.label.label = "%d%%".printf(v);
            });
            aw.mute_btn.clicked.connect(() => {
                if (syncing) return;
                service.toggle_sink_input_mute(index);
            });

            aw.row.add_suffix(slider_box(aw.mute_btn, aw.scale, aw.label));
            return aw;
        }

        void sync_alert_row() {
            alert_index = "";
            foreach (var s in service.sink_inputs) {
                if (is_system_sounds(s.app_name)) { alert_index = s.index;
                    if (!alert_dragging && (int) alert_scale.get_value() != s.volume_pct)
                        alert_scale.set_value(s.volume_pct);
                    break;
                }
            }
            alert_row.sensitive = (alert_index != "");
        }

        // ---------------- helpers ----------------

        bool is_system_sounds(string name) {
            return name.down().contains("system sounds");
        }

        string sink_signature(SinkInfo[] arr) {
            var sb = new StringBuilder();
            foreach (var a in arr) { sb.append(a.id); sb.append("|"); }
            return sb.str;
        }

        Gtk.Scale make_scale(int lower, int upper) {
            var s = new Gtk.Scale.with_range(Gtk.Orientation.HORIZONTAL, lower, upper, 1);
            s.draw_value    = false;
            s.hexpand       = false;
            s.width_request = 160;
            s.valign        = Gtk.Align.CENTER;
            return s;
        }

        Gtk.Box slider_box(Gtk.Button mute_btn, Gtk.Scale scale, Gtk.Label label) {
            var b = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6) { valign = Gtk.Align.CENTER };
            b.append(mute_btn);
            b.append(scale);
            b.append(label);
            return b;
        }

        Gtk.Button flat_icon_button(string icon) {
            var btn = new Gtk.Button.from_icon_name(icon);
            btn.add_css_class("flat");
            btn.valign = Gtk.Align.CENTER;
            return btn;
        }

        Gtk.Label pct_label() {
            var l = new Gtk.Label("0%");
            l.width_chars = 4;
            l.xalign      = 1.0f;
            return l;
        }

        void set_mute_icon(Gtk.Button btn, bool muted, string muted_icon, string on_icon) {
            btn.icon_name = muted ? muted_icon : on_icon;
        }

        void track_drag(Gtk.Scale scale, SetBool setter) {
            var g = new Gtk.GestureClick();
            g.pressed.connect(() => setter(true));
            g.released.connect(() => setter(false));
            scale.add_controller(g);
        }
    }
}
