namespace LumenSettings {

    // Passive service constructors: opening Settings must never toggle the radios.
    public class NetworkingPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "networking"; } }
        public string title     { owned get { return "Networking"; } }
        public string icon_name { owned get { return "network-wireless-symbolic"; } }

        WifiService      wifi = new WifiService.passive();
        BluetoothService bt   = new BluetoothService.passive();
        bool building = false;

        Gtk.Box root_box;

        // Wi-Fi
        Adw.SwitchRow   wifi_switch;
        Gtk.Spinner wifi_spinner;
        Gtk.Box     wifi_list_holder;

        // Wi-Fi details
        Adw.PreferencesGroup wifi_details_group;
        Adw.ActionRow wifi_ip_row;
        Adw.ActionRow wifi_gw_row;
        Adw.ActionRow wifi_dns_row;
        Adw.ActionRow wifi_mac_row;
        Adw.ActionRow wifi_sec_row;
        Adw.ActionRow wifi_band_row;
        Adw.ActionRow wifi_pw_row;
        Gtk.ToggleButton wifi_pw_reveal;
        string    wifi_password = "";

        // Ethernet
        Adw.ActionRow eth_status_row;
        Adw.SwitchRow eth_switch;
        Adw.PreferencesGroup eth_details_group;
        Adw.ActionRow eth_ip_row;
        Adw.ActionRow eth_gw_row;
        Adw.ActionRow eth_dns_row;
        Adw.ActionRow eth_mac_row;

        // Bluetooth
        Adw.SwitchRow   bt_switch;
        Gtk.Spinner bt_spinner;
        Gtk.Box     bt_list_holder;
        Adw.PreferencesGroup   bt_details_group;
        Adw.ActionRow   bt_name_row;
        Adw.ActionRow   bt_type_row;
        Adw.ActionRow   bt_battery_row;
        Adw.ActionRow   bt_addr_row;
        Adw.ActionRow   bt_paired_row;

        // Connection tracking so details are (re)fetched only on a real change.
        string last_wifi_conn = "";
        bool   last_eth_conn  = false;
        string last_bt_conn   = "";

        // The SSID whose password dialog is open, so the single connect_result
        // handler can re-prompt on BAD_PASSWORD keyed on the right network.
        string pending_pw_ssid = "";

        public Gtk.Widget build() {
            // One box, so lists rebuilt in place keep their order between groups.
            root_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 18);

            build_wifi();
            build_wifi_details();
            build_ethernet();
            build_bluetooth();

            wifi.state_changed.connect(rebuild_wifi);
            wifi.state_changed.connect(rebuild_eth);
            wifi.connect_result.connect(on_wifi_connect_result);
            wifi.details_ready.connect(on_details_ready);
            bt.state_changed.connect(rebuild_bt);
            bt.device_details_ready.connect(on_bt_details_ready);

            rebuild_wifi();
            rebuild_eth();
            rebuild_bt();

            wifi.refresh_scan(true);
            bt.refresh_scan(true);

            var holder = new Adw.PreferencesGroup();
            holder.add(root_box);
            var page = new Adw.PreferencesPage();
            page.add(holder);
            return page;
        }

        void build_wifi() {
            var group = new Adw.PreferencesGroup() { title = "Wi-Fi" };

            wifi_switch = new Adw.SwitchRow() { title = "Wi-Fi", active = wifi.enabled };
            wifi_switch.notify["active"].connect(() => {
                if (building) return;
                wifi.set_radio(wifi_switch.active);
            });
            group.add(wifi_switch);

            var hb = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            wifi_spinner = new Gtk.Spinner();
            var rescan = new Gtk.Button.from_icon_name("view-refresh-symbolic");
            rescan.add_css_class("flat");
            rescan.tooltip_text = "Rescan";
            rescan.clicked.connect(() => wifi.refresh_scan(true));
            hb.append(wifi_spinner);
            hb.append(rescan);
            group.set_header_suffix(hb);

            root_box.append(group);

            wifi_list_holder = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            root_box.append(wifi_list_holder);
        }

        void rebuild_wifi() {
            building = true;

            wifi_switch.active = wifi.enabled;
            wifi_spinner.visible  = wifi.scanning;
            if (wifi.scanning) wifi_spinner.start(); else wifi_spinner.stop();

            clear_box(wifi_list_holder);
            if (wifi.enabled) {
                var bl = new Adw.PreferencesGroup();
                foreach (var net in sorted_nets())
                    bl.add(make_wifi_row(net));

                var hidden = new Adw.ActionRow() { title = "Connect to Hidden Network…", use_markup = false };
                hidden.add_prefix(new Gtk.Image.from_icon_name("list-add-symbolic"));
                hidden.activatable = true;
                hidden.activated.connect(() => prompt_hidden());
                bl.add(hidden);

                wifi_list_holder.append(bl);
                wifi_list_holder.visible = true;
            } else {
                wifi_list_holder.visible = false;
            }

            update_conn_tracking();
            building = false;
        }

        WifiNet[] sorted_nets() {
            WifiNet[] head = {};
            WifiNet[] tail = {};
            foreach (var n in wifi.nets) {
                if (n.ssid == wifi.connected_ssid) head += n;
                else                               tail += n;
            }
            WifiNet[] all = {};
            foreach (var n in head) all += n;
            foreach (var n in tail) all += n;
            return all;
        }

        Adw.ActionRow make_wifi_row(WifiNet net) {
            string sub;
            if      (net.ssid == wifi.connected_ssid) sub = "Connected";
            else if (net.is_saved)                    sub = "Saved";
            else if (net.is_secured())                sub = net.security;
            else                                      sub = "Open";

            var row = new Adw.ActionRow() { title = net.ssid, subtitle = sub, use_markup = false };
            row.add_prefix(new Gtk.Image.from_icon_name(signal_icon(net)));
            if (net.is_secured())
                row.add_prefix(new Gtk.Image.from_icon_name("network-wireless-encrypted-symbolic"));
            row.activatable = true;

            if (net.ssid == wifi.connecting_ssid) {
                var sp = new Gtk.Spinner();
                sp.start();
                row.add_suffix(sp);
            } else if (net.ssid == wifi.connected_ssid) {
                row.add_suffix(new Gtk.Image.from_icon_name("emblem-ok-symbolic"));
            }

            row.activated.connect(() => on_wifi_row_activated(net));
            return row;
        }

        string signal_icon(WifiNet net) {
            string level;
            if      (net.signal >= 80) level = "excellent";
            else if (net.signal >= 55) level = "good";
            else if (net.signal >= 35) level = "ok";
            else if (net.signal >= 15) level = "weak";
            else                       level = "none";
            return "network-wireless-signal-%s-symbolic".printf(level);
        }

        void on_wifi_row_activated(WifiNet net) {
            if (net.ssid == wifi.connected_ssid) {
                var dlg = new Adw.AlertDialog(net.ssid, "This network is connected.");
                dlg.add_response("cancel", "Cancel");
                dlg.add_response("forget", "Forget");
                dlg.add_response("disconnect", "Disconnect");
                dlg.set_response_appearance("disconnect", Adw.ResponseAppearance.SUGGESTED);
                dlg.set_response_appearance("forget", Adw.ResponseAppearance.DESTRUCTIVE);
                dlg.set_close_response("cancel");
                dlg.response.connect((resp) => {
                    if (resp == "disconnect") wifi.disconnect_active();
                    else if (resp == "forget") wifi.forget(net.ssid);
                });
                dlg.present(root_widget());
            } else if (net.is_saved) {
                wifi.connect_to(net.ssid, "", true);
            } else if (!net.is_secured()) {
                wifi.connect_to(net.ssid, "", false);
            } else {
                prompt_password(net.ssid, false);
            }
        }

        void on_wifi_connect_result(string ssid, WifiConnectResult res) {
            if (res == WifiConnectResult.BAD_PASSWORD && ssid == pending_pw_ssid)
                prompt_password(ssid, true);
            else
                pending_pw_ssid = "";
        }

        void prompt_password(string ssid, bool error) {
            var dlg = new Adw.AlertDialog("Connect to " + ssid, null);

            var body = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            var pw = new Adw.PasswordEntryRow();
            pw.title = "Password";
            var lb = new Adw.PreferencesGroup();
            lb.add(pw);
            body.append(lb);
            if (error) {
                var err = new Gtk.Label("Incorrect password. Please try again.") {
                    xalign = 0,
                };
                err.add_css_class("error");
                body.append(err);
            }
            dlg.set_extra_child(body);

            dlg.add_response("cancel", "Cancel");
            dlg.add_response("connect", "Connect");
            dlg.set_response_appearance("connect", Adw.ResponseAppearance.SUGGESTED);
            dlg.set_default_response("connect");
            dlg.set_close_response("cancel");
            dlg.response.connect((resp) => {
                if (resp == "connect") {
                    pending_pw_ssid = ssid;
                    wifi.connect_to(ssid, pw.text, false);
                } else {
                    pending_pw_ssid = "";
                }
            });
            dlg.present(root_widget());
        }

        void prompt_hidden() {
            var dlg = new Adw.AlertDialog("Connect to Hidden Network", null);

            var body = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            var lb = new Adw.PreferencesGroup();

            var ssid = new Adw.EntryRow();
            ssid.title = "Network name (SSID)";
            lb.add(ssid);

            var sec = new ComboRow("Security",
                new string[] { "None", "WPA/WPA2 Personal" },
                new string[] { "open", "wpa" }, "wpa");
            lb.add(sec);

            var pw = new Adw.PasswordEntryRow();
            pw.title = "Password";
            lb.add(pw);
            body.append(lb);
            dlg.set_extra_child(body);

            dlg.add_response("cancel", "Cancel");
            dlg.add_response("connect", "Connect");
            dlg.set_response_appearance("connect", Adw.ResponseAppearance.SUGGESTED);
            dlg.set_default_response("connect");
            dlg.set_close_response("cancel");

            string chosen_sec = "wpa";
            sec.value_changed.connect((v) => chosen_sec = v);

            dlg.response.connect((resp) => {
                if (resp != "connect") return;
                var name = ssid.text.strip();
                if (name == "") return;
                var pass = chosen_sec == "open" ? "" : pw.text;
                pending_pw_ssid = name;
                wifi.connect_to_hidden(name, pass);
            });
            dlg.present(root_widget());
        }

        void build_wifi_details() {
            wifi_details_group = new Adw.PreferencesGroup() { title = "Wi-Fi details" };
            wifi_ip_row   = new Adw.ActionRow() { title = "IPv4 address", use_markup = false };
            wifi_gw_row   = new Adw.ActionRow() { title = "Gateway", use_markup = false };
            wifi_dns_row  = new Adw.ActionRow() { title = "DNS", use_markup = false };
            wifi_mac_row  = new Adw.ActionRow() { title = "Hardware address", use_markup = false };
            wifi_sec_row  = new Adw.ActionRow() { title = "Security", use_markup = false };
            wifi_band_row = new Adw.ActionRow() { title = "Band", use_markup = false };

            wifi_pw_row = new Adw.ActionRow() { title = "Password", use_markup = false };
            wifi_pw_reveal = new Gtk.ToggleButton() {
                icon_name = "view-reveal-symbolic",
                tooltip_text = "Show password",
                valign = Gtk.Align.CENTER,
            };
            wifi_pw_reveal.add_css_class("flat");
            wifi_pw_reveal.toggled.connect(update_password_display);
            var wifi_pw_copy = new Gtk.Button.from_icon_name("edit-copy-symbolic") {
                tooltip_text = "Copy password",
                valign = Gtk.Align.CENTER,
            };
            wifi_pw_copy.add_css_class("flat");
            wifi_pw_copy.clicked.connect(() => {
                if (wifi_password != "")
                    root_box.get_clipboard().set_text(wifi_password);
            });
            var wifi_pw_suffix = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            wifi_pw_suffix.append(wifi_pw_reveal);
            wifi_pw_suffix.append(wifi_pw_copy);
            wifi_pw_row.add_suffix(wifi_pw_suffix);

            wifi_details_group.add(wifi_ip_row);
            wifi_details_group.add(wifi_gw_row);
            wifi_details_group.add(wifi_dns_row);
            wifi_details_group.add(wifi_mac_row);
            wifi_details_group.add(wifi_sec_row);
            wifi_details_group.add(wifi_band_row);
            wifi_details_group.add(wifi_pw_row);
            wifi_details_group.visible = false;
            root_box.append(wifi_details_group);
        }

        void update_password_display() {
            bool show = wifi_pw_reveal.active && wifi_password != "";
            // Fixed-length mask: don't leak the passphrase length when hidden.
            wifi_pw_row.subtitle = show ? wifi_password : "••••••••";
            wifi_pw_reveal.tooltip_text = wifi_pw_reveal.active
                ? "Hide password" : "Show password";
        }

        void build_ethernet() {
            var group = new Adw.PreferencesGroup() { title = "Ethernet" };

            eth_status_row = new Adw.ActionRow() { title = "Wired connection", use_markup = false };
            eth_status_row.add_prefix(new Gtk.Image.from_icon_name("network-wired-symbolic"));
            group.add(eth_status_row);

            eth_switch = new Adw.SwitchRow() { title = "Enable wired connection" };
            eth_switch.notify["active"].connect(() => {
                if (building) return;
                wifi.set_ethernet(eth_switch.active);
            });
            group.add(eth_switch);
            root_box.append(group);

            eth_details_group = new Adw.PreferencesGroup() { title = "Ethernet details" };
            eth_ip_row  = new Adw.ActionRow() { title = "IPv4 address", use_markup = false };
            eth_gw_row  = new Adw.ActionRow() { title = "Gateway", use_markup = false };
            eth_dns_row = new Adw.ActionRow() { title = "DNS", use_markup = false };
            eth_mac_row = new Adw.ActionRow() { title = "Hardware address", use_markup = false };
            eth_details_group.add(eth_ip_row);
            eth_details_group.add(eth_gw_row);
            eth_details_group.add(eth_dns_row);
            eth_details_group.add(eth_mac_row);
            eth_details_group.visible = false;
            root_box.append(eth_details_group);
        }

        void rebuild_eth() {
            building = true;
            string status;
            if      (wifi.ethernet_device == "") status = "Disabled";
            else if (wifi.ethernet_connected)    status = "Connected";
            else                                 status = "Cable unplugged";
            eth_status_row.subtitle = status;
            eth_switch.active    = wifi.ethernet_connected;
            eth_switch.sensitive    = wifi.ethernet_device != "";
            building = false;
        }

        void on_details_ready(NetDetails wifi_det, NetDetails eth_det) {
            wifi_ip_row.subtitle   = or_dash(wifi_det.ip4);
            wifi_gw_row.subtitle   = or_dash(wifi_det.gateway);
            wifi_dns_row.subtitle  = or_dash(string.joinv(", ", wifi_det.dns));
            wifi_mac_row.subtitle  = or_dash(wifi_det.mac);
            wifi_sec_row.subtitle  = or_dash(wifi_det.security);
            wifi_band_row.subtitle = or_dash(wifi_det.band);

            wifi_password = wifi_det.password;
            wifi_pw_reveal.active = false;           // re-mask on every refresh
            wifi_pw_row.visible = wifi_password != "";
            update_password_display();

            eth_ip_row.subtitle   = or_dash(eth_det.ip4);
            eth_gw_row.subtitle   = or_dash(eth_det.gateway);
            eth_dns_row.subtitle  = or_dash(string.joinv(", ", eth_det.dns));
            eth_mac_row.subtitle  = or_dash(eth_det.mac);
        }

        void update_conn_tracking() {
            bool changed = false;
            if (wifi.connected_ssid != last_wifi_conn) { last_wifi_conn = wifi.connected_ssid; changed = true; }
            if (wifi.ethernet_connected != last_eth_conn) { last_eth_conn = wifi.ethernet_connected; changed = true; }

            wifi_details_group.visible = wifi.connected;
            eth_details_group.visible  = wifi.ethernet_connected;

            if (changed && (wifi.connected || wifi.ethernet_connected))
                wifi.request_details();
        }

        void build_bluetooth() {
            var group = new Adw.PreferencesGroup() { title = "Bluetooth" };

            bt_switch = new Adw.SwitchRow() { title = "Bluetooth", active = bt.powered };
            bt_switch.notify["active"].connect(() => {
                if (building) return;
                bt.set_power(bt_switch.active);
            });
            group.add(bt_switch);

            var hb = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            bt_spinner = new Gtk.Spinner();
            var rescan = new Gtk.Button.from_icon_name("view-refresh-symbolic");
            rescan.add_css_class("flat");
            rescan.tooltip_text = "Scan";
            rescan.clicked.connect(() => bt.refresh_scan(true));
            hb.append(bt_spinner);
            hb.append(rescan);
            group.set_header_suffix(hb);

            root_box.append(group);

            bt_list_holder = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            root_box.append(bt_list_holder);

            bt_details_group = new Adw.PreferencesGroup() { title = "Device details" };
            bt_name_row    = new Adw.ActionRow() { title = "Name", use_markup = false };
            bt_type_row    = new Adw.ActionRow() { title = "Type", use_markup = false };
            bt_battery_row = new Adw.ActionRow() { title = "Battery", use_markup = false };
            bt_addr_row    = new Adw.ActionRow() { title = "Address", use_markup = false };
            bt_paired_row  = new Adw.ActionRow() { title = "Paired", use_markup = false };
            bt_details_group.add(bt_name_row);
            bt_details_group.add(bt_type_row);
            bt_details_group.add(bt_battery_row);
            bt_details_group.add(bt_addr_row);
            bt_details_group.add(bt_paired_row);
            bt_details_group.visible = false;
            root_box.append(bt_details_group);
        }

        void rebuild_bt() {
            building = true;

            bt_switch.active = bt.powered;
            bt_spinner.visible  = bt.scanning;
            if (bt.scanning) bt_spinner.start(); else bt_spinner.stop();

            clear_box(bt_list_holder);
            if (bt.powered) {
                var bl = new Adw.PreferencesGroup();
                foreach (var d in sorted_devices())
                    bl.add(make_bt_row(d));
                bt_list_holder.append(bl);
                bt_list_holder.visible = true;
            } else {
                bt_list_holder.visible = false;
            }

            update_bt_tracking();
            building = false;
        }

        BtDevice[] sorted_devices() {
            BtDevice[] conn = {};
            BtDevice[] paired = {};
            BtDevice[] rest = {};
            foreach (var d in bt.devices) {
                if      (d.connected) conn   += d;
                else if (d.paired)    paired += d;
                else                  rest   += d;
            }
            BtDevice[] all = {};
            foreach (var d in conn)   all += d;
            foreach (var d in paired) all += d;
            foreach (var d in rest)   all += d;
            return all;
        }

        Adw.ActionRow make_bt_row(BtDevice d) {
            string sub;
            if      (d.connected) sub = "Connected";
            else if (d.paired)    sub = "Paired";
            else                  sub = "Available";

            var row = new Adw.ActionRow() { title = d.name, subtitle = sub, use_markup = false };
            row.add_prefix(new Gtk.Image.from_icon_name(bt_type_icon(d.dev_icon)));
            row.activatable = true;
            if (d.connected)
                row.add_suffix(new Gtk.Image.from_icon_name("emblem-ok-symbolic"));
            row.activated.connect(() => on_bt_row_activated(d));
            return row;
        }

        string bt_type_icon(string dev_icon) {
            switch (dev_icon) {
                case "audio-card":
                case "audio-headset":
                case "audio-headphones": return "audio-headphones-symbolic";
                case "input-mouse":      return "input-mouse-symbolic";
                case "input-keyboard":   return "input-keyboard-symbolic";
                case "phone":            return "phone-symbolic";
                default:                 return "bluetooth-symbolic";
            }
        }

        void on_bt_row_activated(BtDevice d) {
            var dlg = new Adw.AlertDialog(d.name, null);
            dlg.add_response("cancel", "Cancel");
            if (d.connected) {
                dlg.add_response("disconnect", "Disconnect");
                dlg.set_response_appearance("disconnect", Adw.ResponseAppearance.DESTRUCTIVE);
            } else if (d.paired) {
                dlg.add_response("connect", "Connect");
                dlg.set_response_appearance("connect", Adw.ResponseAppearance.SUGGESTED);
            } else {
                dlg.add_response("pair", "Pair");
                dlg.set_response_appearance("pair", Adw.ResponseAppearance.SUGGESTED);
            }
            if (d.paired)
                dlg.add_response("remove", "Remove");
            dlg.set_close_response("cancel");
            dlg.response.connect((resp) => {
                switch (resp) {
                    case "connect":    bt.connect_device(d.mac);    break;
                    case "disconnect": bt.disconnect_device(d.mac); break;
                    case "pair":       bt.pair_device(d.mac);       break;
                    case "remove":     bt.remove_device(d.mac);     break;
                }
            });
            dlg.present(root_widget());

            if (d.connected) bt.request_device_details(d.mac);
        }

        void update_bt_tracking() {
            if (bt.connected_name != last_bt_conn) {
                last_bt_conn = bt.connected_name;
                if (bt.connected) {
                    var mac = connected_mac();
                    if (mac != "") bt.request_device_details(mac);
                }
            }
            bt_details_group.visible = bt.connected;
        }

        string connected_mac() {
            foreach (var d in bt.devices)
                if (d.connected) return d.mac;
            return "";
        }

        void on_bt_details_ready(BtDeviceDetails d) {
            bt_name_row.subtitle    = or_dash(d.name);
            bt_type_row.subtitle    = or_dash(d.dev_icon);
            bt_battery_row.subtitle = d.battery >= 0 ? "%d%%".printf(d.battery) : "—";
            bt_addr_row.subtitle    = or_dash(d.mac);
            bt_paired_row.subtitle  = d.bonded ? "Bonded" : (d.paired ? "Paired" : "No");
        }

        Gtk.Widget? root_widget() {
            return root_box.get_root() as Gtk.Widget;
        }

        static void clear_box(Gtk.Box box) {
            var c = box.get_first_child();
            while (c != null) {
                var n = c.get_next_sibling();
                box.remove(c);
                c = n;
            }
        }

        static string or_dash(string v) {
            return v == "" ? "—" : v;
        }
    }
}
