using LumenCommon;

namespace LumenSettings {

    // The desktop is drawn by wf-background, which reads wf-shell.ini
    // [background] live (image = file or directory, fill_mode, cycle_timeout
    // in seconds, randomize). wallpaper.ini [wallpaper] `image` (the lock
    // screen's) is always a FILE, even while wf-shell.ini points at a
    // slideshow folder; `gallery-folders` is the gallery's KeyFile string list.
    public class WallpaperPage : GLib.Object, SettingsPage {
        public string id        { owned get { return "wallpaper"; } }
        public string title     { owned get { return "Wallpaper"; } }
        public string icon_name { owned get { return "lumen-settings-wallpaper"; } }

        // ponytail: gallery stops at this many images; page it if folders get huge.
        const int MAX_THUMBS = 300;
        const int THUMB_W = 160;
        const int THUMB_H = 100;

        IniRows wf;   // wf-shell.ini [background]
        IniRows wp;   // wallpaper.ini [wallpaper]
        Gtk.Picture preview;
        Gtk.FlowBox gallery;
        Adw.PreferencesGroup folders_group;
        Gtk.Widget[] folder_rows = {};
        Adw.SwitchRow slideshow;
        FileRow file_row;
        string folder;
        bool gallery_started = false;
        uint gallery_gen = 0;   // only the newest scan may add tiles

        public Gtk.Widget build() {
            wf = new IniRows(Paths.wf_shell_ini(), "background");
            wp = new IniRows(Paths.wallpaper_ini(), "wallpaper");

            var wf_image = wf.get_str("image") ?? "";
            bool wf_is_dir = wf_image != "" && FileUtils.test(wf_image, FileTest.IS_DIR);
            folder = wf_is_dir ? wf_image : (wp.get_str("slideshow-folder") ?? default_folder());

            var page = new Adw.PreferencesPage();

            // ── Preview ───────────────────────────────────────────────
            preview = new Gtk.Picture() { can_shrink = true };
            var frame = new Gtk.AspectFrame(0.5f, 0.5f, monitor_ratio(), false) {
                child = preview, height_request = 240, overflow = Gtk.Overflow.HIDDEN,
            };
            frame.add_css_class("card");
            var preview_group = new Adw.PreferencesGroup();
            preview_group.add(frame);
            page.add(preview_group);

            // ── Image ─────────────────────────────────────────────────
            var group = new Adw.PreferencesGroup() { title = "Background" };
            file_row = new FileRow("Image", current_image(), "background image file");
            file_row.value_changed.connect(apply_image);
            group.add(file_row);

            var fill = wf.combo_row("fill_mode", "Fill mode",
                                    { "Fill and crop", "Fit", "Stretch" },
                                    { "fill_and_crop", "preserve_aspect", "stretch" },
                                    "stretch");
            fill.value_changed.connect(set_fit);
            group.add(fill);
            page.add(group);
            set_fit(wf.get_str("fill_mode") ?? "stretch");

            // ── Gallery ───────────────────────────────────────────────
            var gallery_group = new Adw.PreferencesGroup() { title = "Gallery" };
            gallery = new Gtk.FlowBox() {
                homogeneous = true,
                selection_mode = Gtk.SelectionMode.SINGLE,
                min_children_per_line = 2,
                max_children_per_line = 8,
                column_spacing = 6,
                row_spacing = 6,
            };
            gallery.child_activated.connect((c) => {
                apply_image(c.get_data<string>("path"));
            });
            gallery_group.add(gallery);
            page.add(gallery_group);
            // Pages are built eagerly at startup; only walk the disk once shown.
            gallery.map.connect(() => {
                if (gallery_started) return;
                gallery_started = true;
                load_gallery();
            });

            folders_group = new Adw.PreferencesGroup() { title = "Gallery folders" };
            page.add(folders_group);
            rebuild_folder_rows();

            // ── Slideshow ─────────────────────────────────────────────
            var show_group = new Adw.PreferencesGroup() { title = "Slideshow" };
            slideshow = new Adw.SwitchRow() {
                title = "Slideshow", subtitle = "cycle through the images in a folder",
                active = wf_is_dir,
            };
            slideshow.notify["active"].connect(on_slideshow_toggled);
            show_group.add(slideshow);

            var folder_button = new Gtk.Button.with_label(Path.get_basename(folder)) {
                valign = Gtk.Align.CENTER,
            };
            var folder_row = new Adw.ActionRow() { title = "Folder", use_markup = false };
            folder_row.add_suffix(folder_button);
            folder_button.clicked.connect(() => pick_folder(folder_button));
            show_group.add(folder_row);

            show_group.add(wf.int_row("cycle_timeout", "Change every", 5, 86400, 5, 150,
                                      "seconds"));
            show_group.add(wf.bool_row("randomize", "Shuffle", false));
            page.add(show_group);

            show_preview();
            return page;
        }

        string current_image() {
            return wp.get_str("image") ?? "";
        }

        void set_fit(string mode) {
            preview.content_fit = mode == "fill_and_crop" ? Gtk.ContentFit.COVER
                                : mode == "preserve_aspect" ? Gtk.ContentFit.CONTAIN
                                : Gtk.ContentFit.FILL;
        }

        static string default_folder() {
            var pics = Environment.get_user_special_dir(UserDirectory.PICTURES)
                ?? Path.build_filename(Environment.get_home_dir(), "Pictures");
            var walls = Path.build_filename(pics, "Wallpapers");
            return FileUtils.test(walls, FileTest.IS_DIR) ? walls : pics;
        }

        static float monitor_ratio() {
            var display = Gdk.Display.get_default();
            var mon = display != null ? display.get_monitors().get_item(0) as Gdk.Monitor : null;
            if (mon != null && mon.geometry.height > 0)
                return (float) mon.geometry.width / mon.geometry.height;
            return 16.0f / 9.0f;
        }

        // A single image always ends the slideshow; the toggle handler then
        // copies wallpaper.ini's image (set first) into wf-shell.ini.
        void apply_image(string path) {
            wp.put("image", path);
            if (slideshow.active) slideshow.active = false;
            else wf.put("image", path);
            show_preview();
            select_current();
        }

        void on_slideshow_toggled() {
            if (!slideshow.active) {
                wf.put("image", current_image());
                return;
            }
            wf.put("image", folder);
            var cur = current_image();
            if (cur == "" || Path.get_dirname(cur) != folder) {
                var first = first_image(folder);
                if (first != null) {
                    wp.put("image", first);
                    show_preview();
                    select_current();
                }
            }
        }

        // ── Gallery folders ───────────────────────────────────────────
        // A raw KeyFile value round-trips through a scratch KeyFile so `;`
        // and escapes follow the real string-list format.
        string[] gallery_folders() {
            var raw = wp.get_str("gallery-folders");
            if (raw == null) return { default_folder(), Paths.system_data_file("backgrounds") };
            var kf = new KeyFile();
            kf.set_value("x", "x", raw);
            try {
                return kf.get_string_list("x", "x");
            } catch (KeyFileError e) {
                return {};
            }
        }

        void set_gallery_folders(string[] dirs) {
            var kf = new KeyFile();
            kf.set_string_list("x", "x", dirs);
            try {
                wp.put("gallery-folders", kf.get_value("x", "x"));
            } catch (KeyFileError e) { /* just set */ }
            rebuild_folder_rows();
            if (gallery_started) load_gallery();
        }

        void rebuild_folder_rows() {
            foreach (var r in folder_rows) folders_group.remove(r);
            folder_rows = {};
            var dirs = gallery_folders();
            foreach (var d in dirs) {
                var row = new Adw.ActionRow() { title = d, use_markup = false };
                var rm = new Gtk.Button.from_icon_name("list-remove-symbolic") {
                    valign = Gtk.Align.CENTER, tooltip_text = "Remove folder",
                };
                rm.add_css_class("flat");
                rm.clicked.connect(() => {
                    string[] keep = {};
                    foreach (var k in gallery_folders()) if (k != d) keep += k;
                    set_gallery_folders(keep);
                });
                row.add_suffix(rm);
                folders_group.add(row);
                folder_rows += row;
            }
            var add = new Adw.ButtonRow() { title = "Add folder…", start_icon_name = "list-add-symbolic" };
            add.activated.connect(() => {
                var dlg = new Gtk.FileDialog() { title = "Add a gallery folder", modal = true };
                dlg.select_folder.begin((Gtk.Window) folders_group.get_root(), null, (obj, res) => {
                    try {
                        var p = dlg.select_folder.end(res).get_path();
                        var cur = gallery_folders();
                        if (p == null || p in cur) return;
                        cur += p;
                        set_gallery_folders(cur);
                    } catch (Error e) { /* cancel */ }
                });
            });
            folders_group.add(add);
            folder_rows += add;
        }

        void pick_folder(Gtk.Button button) {
            var dlg = new Gtk.FileDialog() { title = "Choose a folder", modal = true };
            dlg.initial_folder = File.new_for_path(folder);
            dlg.select_folder.begin((Gtk.Window) button.get_root(), null, (obj, res) => {
                try {
                    var p = dlg.select_folder.end(res).get_path();
                    if (p == null) return;
                    folder = p;
                    button.label = Path.get_basename(p);
                    wp.put("slideshow-folder", p);
                    if (slideshow.active) on_slideshow_toggled();
                    else slideshow.active = true;
                } catch (Error e) { /* cancel */ }
            });
        }

        void show_preview() {
            var path = current_image();
            if (path == "") { preview.paintable = null; return; }
            new Thread<void*>("wallpaper-preview", () => {
                var tex = load_scaled(path, 1280, 1280);   // unreadable: blank preview
                Idle.add(() => {
                    if (path == current_image()) preview.paintable = tex;
                    return Source.REMOVE;
                });
                return null;
            });
        }

        void select_current() {
            var cur = current_image();
            gallery.unselect_all();
            for (var c = gallery.get_first_child(); c != null; c = c.get_next_sibling()) {
                var child = (Gtk.FlowBoxChild) c;
                if (child.get_data<string>("path") == cur) gallery.select_child(child);
            }
        }

        void load_gallery() {
            var gen = ++gallery_gen;
            gallery.remove_all();
            var roots = gallery_folders();
            new Thread<void*>("wallpaper-gallery", () => {
                var paths = new GenericArray<string>();
                foreach (var r in roots) collect_images(r, paths, true);
                foreach (var p in paths) {
                    if (gen != gallery_gen) break;   // superseded by a newer scan
                    var tex = load_scaled(p, THUMB_W * 2, THUMB_H * 2);
                    if (tex == null) continue;   // unsupported format: just skip it
                    Idle.add(() => {
                        if (gen == gallery_gen) add_tile(p, tex);
                        return Source.REMOVE;
                    });
                }
                return null;
            });
        }

        void add_tile(string path, Gdk.Texture tex) {
            var pic = new Gtk.Picture.for_paintable(tex) {
                content_fit = Gtk.ContentFit.COVER,
                width_request = THUMB_W, height_request = THUMB_H,
                overflow = Gtk.Overflow.HIDDEN,
            };
            pic.add_css_class("card");
            var child = new Gtk.FlowBoxChild() {
                child = pic, tooltip_text = Path.get_basename(path),
            };
            child.set_data<string>("path", path);
            gallery.append(child);
            if (path == current_image()) gallery.select_child(child);
        }

        static void collect_images(string dir, GenericArray<string> out_paths, bool recurse) {
            if (out_paths.length >= MAX_THUMBS) return;
            var names = new Gee.ArrayList<string>();
            var dirs = new Gee.ArrayList<string>();
            try {
                var en = File.new_for_path(dir).enumerate_children(
                    "standard::name,standard::type,standard::fast-content-type,standard::is-hidden",
                    FileQueryInfoFlags.NONE);
                FileInfo? info;
                while ((info = en.next_file()) != null) {
                    if (info.get_is_hidden()) continue;
                    var p = Path.build_filename(dir, info.get_name());
                    if (info.get_file_type() == FileType.DIRECTORY) {
                        dirs.add(p);
                    } else {
                        var ct = info.get_attribute_string(FileAttribute.STANDARD_FAST_CONTENT_TYPE);
                        if (ct != null && ContentType.is_mime_type(ct, "image/*")) names.add(p);
                    }
                }
            } catch (Error e) {
                return;
            }
            names.sort();
            foreach (var p in names) {
                if (out_paths.length >= MAX_THUMBS) return;
                out_paths.add(p);
            }
            if (!recurse) return;
            dirs.sort();
            foreach (var d in dirs) collect_images(d, out_paths, true);
        }

        static string? first_image(string dir) {
            var paths = new GenericArray<string>();
            collect_images(dir, paths, false);
            return paths.length > 0 ? paths[0] : null;
        }

        // Decoded at reduced size (gdk-pixbuf scales while loading), safe off
        // the main thread. MemoryTexture rather than the deprecated
        // Gdk.Texture.for_pixbuf.
        static Gdk.Texture? load_scaled(string path, int w, int h) {
            try {
                return to_texture(new Gdk.Pixbuf.from_file_at_scale(path, w, h, true));
            } catch (Error e) {
                return null;
            }
        }

        static Gdk.Texture to_texture(Gdk.Pixbuf pb) {
            return new Gdk.MemoryTexture(
                pb.width, pb.height,
                pb.has_alpha ? Gdk.MemoryFormat.R8G8B8A8 : Gdk.MemoryFormat.R8G8B8,
                pb.read_pixel_bytes(), pb.rowstride);
        }
    }
}
