using LumenCommon;

namespace LumenSettings {

    // No password row: AccountsService SetPassword needs auth_admin and a
    // pre-crypt()ed hash (bypassing PAM quality checks and the keyring), and the
    // only other route is scraping passwd's prompts through a pty.
    public class UsersPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "users"; } }
        public string title     { owned get { return "Users"; } }
        public string icon_name { owned get { return "system-users-symbolic"; } }

        const string[] FORMAT_VARS = {
            "LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER",
        };

        // label, content type, extra-type globs: GNOME Settings' own set
        // (cc-default-apps-page.blp), plus text editor and file manager.
        const string[,] DEFAULT_APPS = {
            { "Web browser",  "x-scheme-handler/http", "text/html;application/xhtml+xml;x-scheme-handler/https" },
            { "Mail",         "x-scheme-handler/mailto", "" },
            { "Calendar",     "text/calendar", "" },
            { "Music",        "audio/x-vorbis+ogg", "audio/*" },
            { "Video",        "video/x-ogm+ogg", "video/*" },
            { "Photos",       "image/jpeg", "image/*" },
            { "Text editor",  "text/plain", "" },
            { "File manager", "inode/directory", "" },
        };

        Adw.PreferencesGroup account;
        Adw.Avatar avatar;

        public Gtk.Widget build() {
            var page = new Adw.PreferencesPage();
            var usr = AccountsClient.current_user_proxy();
            var info = AccountsClient.load_current_user();

            // ---- Account ------------------------------------------------------
            account = new Adw.PreferencesGroup() { title = "Account" };

            avatar = new Adw.Avatar(64, info.real_name, true);
            show_icon(info.icon_path);
            var avatar_row = new Adw.ActionRow() { title = "Avatar" };
            avatar_row.add_prefix(avatar);
            var change = new Gtk.Button.with_label("Change…") { valign = Gtk.Align.CENTER };
            change.clicked.connect(pick_avatar);
            avatar_row.add_suffix(change);
            account.add(avatar_row);

            var name_row = new Adw.EntryRow() {
                title = "Name", text = info.real_name, show_apply_button = true,
            };
            name_row.apply.connect(() => {
                try {
                    AccountsClient.set_real_name(name_row.text.strip());
                    avatar.text = name_row.text;
                    report(null);
                } catch (Error e) { report("Could not change the name: " + e.message); }
            });
            account.add(name_row);

            account.add(info_row("Username", Environment.get_user_name()));
            int type = -1;
            var t = usr != null ? usr.get_cached_property("AccountType") : null;
            if (t != null && t.is_of_type(VariantType.INT32)) type = t.get_int32();
            account.add(info_row("Account type",
                type == 1 ? "Administrator" : type == 0 ? "Standard" : "Unknown"));
            page.add(account);

            // ---- Language & Region -------------------------------------------
            var region = new Adw.PreferencesGroup() {
                title = "Language &amp; Region",
                description = "Changes apply at next login.",
            };
            string[] locales = {};
#if FREEBSD
            // No localectl: locale(1) lists every installed locale; offer the
            // UTF-8 ones, as localectl effectively does.
            var out = Proc.run_capture({ "locale", "-a" });
            if (out != null)
                foreach (var l in out.split("\n"))
                    if (l.strip().has_suffix(".UTF-8")) locales += l.strip();
#else
            var out = Proc.run_capture({ "localectl", "list-locales" });
            if (out != null)
                foreach (var l in out.split("\n")) if (l.strip() != "") locales += l.strip();
#endif

            var lang = "";
            var lv = usr != null ? usr.get_cached_property("Language") : null;
            if (lv != null && lv.is_of_type(VariantType.STRING)) lang = lv.get_string();
            var lang_row = locale_row("Language",
                "Used by the login screen and applications", "System default", locales, lang);
            lang_row.value_changed.connect((v) => {
                try { AccountsClient.set_language(v); report(null); }
                catch (Error e) { report("Could not change the language: " + e.message); }
            });
            region.add(lang_row);

            var fmt_row = locale_row("Formats", "Dates, numbers and currency",
                "Same as language", locales, read_formats());
            fmt_row.value_changed.connect(write_formats);
            region.add(fmt_row);
            page.add(region);

            // ---- Default Applications ----------------------------------------
            var apps = new Adw.PreferencesGroup() { title = "Default Applications" };
            for (int i = 0; i < DEFAULT_APPS.length[0]; i++)
                apps.add(default_app_row(DEFAULT_APPS[i, 0], DEFAULT_APPS[i, 1], DEFAULT_APPS[i, 2]));
            page.add(apps);

            return page;
        }

        static Adw.ActionRow info_row(string title, string val) {
            var row = new Adw.ActionRow() { title = title, use_markup = false };
            row.add_suffix(new Gtk.Label(val) { valign = Gtk.Align.CENTER });
            return row;
        }

        // Inline status under the Account group title; null clears it.
        void report(string? msg) {
            if (msg != null) warning("users: %s", msg);
            account.description = msg != null ? Markup.escape_text(msg) : "";
        }

        void show_icon(string path) {
            if (path == "") { avatar.custom_image = null; return; }
            try { avatar.custom_image = Gdk.Texture.from_filename(path); }
            catch (Error e) { avatar.custom_image = null; }
        }

        void pick_avatar() {
            var filter = new Gtk.FileFilter() { name = "Images" };
            filter.add_mime_type("image/*");
            var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            var dlg = new Gtk.FileDialog() { title = "Choose an avatar", filters = filters };
            dlg.open.begin((Gtk.Window) avatar.get_root(), null, (o, res) => {
                File f;
                try { f = dlg.open.end(res); } catch (Error e) { return; }   // cancelled
                var src = f.get_path();
                if (src == null) return;
                try {
                    // accounts-daemon rejects big files ("too large to be used
                    // as an icon"), so hand it a downscaled PNG copy.
                    var pix = new Gdk.Pixbuf.from_file_at_scale(src, 512, 512, true);
                    var dst = Path.build_filename(Environment.get_user_cache_dir(),
                                                  "lumen-settings-avatar.png");
                    pix.save(dst, "png");
                    AccountsClient.set_icon_file(dst);
                    show_icon(dst);
                    report(null);
                } catch (Error e) { report("Could not change the avatar: " + e.message); }
            });
        }

        static ComboRow locale_row(string title, string subtitle, string none_label,
                                   string[] locales, string current) {
            string[] labels = { none_label };
            string[] values = { "" };
            if (current != "" && !(current in locales)) { labels += current; values += current; }
            foreach (var l in locales) { labels += l; values += l; }
            return new ComboRow(title, labels, values, current, subtitle);
        }

        // Our own environment.d drop-in: LC_TIME=... lines, nothing else.
        static string read_formats() {
            string text;
            try { FileUtils.get_contents(Paths.formats_env_conf(), out text); }
            catch (Error e) { return ""; }
            foreach (var line in text.split("\n"))
                if (line.has_prefix("LC_TIME=")) return line.substring(8).strip();
            return "";
        }

        void write_formats(string locale) {
            var path = Paths.formats_env_conf();
            try {
                if (locale == "") {
                    FileUtils.unlink(path);
                } else {
                    DirUtils.create_with_parents(Path.get_dirname(path), 0755);
                    var sb = new StringBuilder("# Written by lumen-settings (Users > Formats).\n");
                    foreach (var v in FORMAT_VARS) sb.append("%s=%s\n".printf(v, locale));
                    FileUtils.set_contents(path, sb.str);
                }
                report(null);
            } catch (Error e) { report("Could not save formats: " + e.message); }
        }

        static Gtk.Widget default_app_row(string title, string type, string filters) {
            var cur = AppInfo.get_default_for_type(type, false);
            string cur_id = cur != null ? cur.get_id() ?? "" : "";

            string[] labels = {};
            string[] values = {};
            if (cur_id == "") { labels += "None"; values += ""; }
            else { labels += cur.get_display_name(); values += cur_id; }
            foreach (var app in AppInfo.get_all_for_type(type)) {
                var aid = app.get_id();
                if (aid == null || aid == cur_id) continue;
                labels += app.get_display_name();
                values += aid;
            }

            var row = new ComboRow(title, labels, values, cur_id);
            row.sensitive = values.length > 1 || cur_id != "";
            row.value_changed.connect((aid) => {
                if (aid == "") return;
                AppInfo? app = null;   // no gio-unix here, so no DesktopAppInfo(id)
                foreach (var a in AppInfo.get_all_for_type(type)) if (a.get_id() == aid) app = a;
                if (app == null) return;
                try { app.set_as_default_for_type(type); }
                catch (Error e) { warning("users: default %s → %s: %s", type, aid, e.message); }
                // Like GNOME: also every type the app claims that matches a glob.
                if (filters == "") return;
                foreach (var m in app.get_supported_types() ?? new string[0]) {
                    foreach (var glob in filters.split(";")) {
                        if (!PatternSpec.match_simple(glob, m)) continue;
                        try { app.set_as_default_for_type(m); }
                        catch (Error e) { warning("users: default %s → %s: %s", m, aid, e.message); }
                        break;
                    }
                }
            });
            return row;
        }
    }
}
