using Gtk;

public class WifiPage : Gtk.Box {

    WifiService service;
    Gtk.SearchEntry search;
    Gtk.ListBox list;
    Gtk.Button rescan_btn;
    string filter_text = "";

    public WifiPage (WifiService service) {
        GLib.Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
        this.service = service;
        add_css_class("wifi-page");
        set_size_request(360, 320);

        var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
        var title = new Gtk.Label("Wi-Fi") { xalign = 0, hexpand = true };
        title.add_css_class("page-title");
        header.append(title);

        rescan_btn = new Gtk.Button.from_icon_name("view-refresh-symbolic");
        rescan_btn.add_css_class("flat");
        rescan_btn.clicked.connect(() => service.refresh_scan(true));
        header.append(rescan_btn);
        append(header);

        search = new Gtk.SearchEntry() {
            placeholder_text = "Search networks",
        };
        search.search_changed.connect(() => {
            filter_text = search.text.down();
            list.invalidate_filter();
        });
        append(search);

        list = new Gtk.ListBox() {
            selection_mode = Gtk.SelectionMode.NONE,
            hexpand = true,
        };
        list.add_css_class("wifi-list");
        list.set_filter_func((row) => {
            if (filter_text == "") return true;
            var wrow = (WifiRow) row;
            return wrow.ssid.down().contains(filter_text);
        });
        list.row_activated.connect((row) => on_row_activated((WifiRow) row));

        var scroll = new Gtk.ScrolledWindow() {
            child = list,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
            vexpand = true,
            min_content_height = 200,
        };
        append(scroll);

        service.state_changed.connect(refresh);
        refresh();
    }

    void refresh () {
        Gtk.Widget? r;
        while ((r = list.get_first_child()) != null) list.remove(r);

        foreach (var net in service.nets) {
            list.append(new WifiRow(net, net.ssid == service.connected_ssid));
        }
        rescan_btn.sensitive = !service.scanning;
    }

    void on_row_activated (WifiRow row) {
        if (row.is_connected) {
            service.disconnect_active();
            return;
        }
        if (!row.is_secured) {
            service.connect_to(row.ssid, "");
            return;
        }
        prompt_password(row.ssid);
    }

    void prompt_password (string ssid) {
        var dialog = new Gtk.Window() {
            title = "Connect to " + ssid,
            modal = true,
            default_width = 280,
            transient_for = (Gtk.Window?) get_root(),
        };
        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8) {
            margin_top = 12, margin_bottom = 12,
            margin_start = 12, margin_end = 12,
        };
        var entry = new Gtk.PasswordEntry() {
            placeholder_text = "Password",
            show_peek_icon = true,
        };
        var btn_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8) { halign = Gtk.Align.END };
        var cancel = new Gtk.Button.with_label("Cancel");
        var connect = new Gtk.Button.with_label("Connect");
        connect.add_css_class("suggested-action");
        cancel.clicked.connect(() => dialog.destroy());
        connect.clicked.connect(() => {
            service.connect_to(ssid, entry.text);
            dialog.destroy();
        });
        entry.activate.connect(() => connect.activate());
        btn_row.append(cancel); btn_row.append(connect);
        box.append(entry); box.append(btn_row);
        dialog.set_child(box);
        dialog.present();
    }
}
