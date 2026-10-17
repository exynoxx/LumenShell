namespace LumenSettings {

    public class SettingsWindow : Adw.ApplicationWindow {
        Sidebar sidebar;
        Gtk.Stack stack;
        Adw.NavigationSplitView split;
        Adw.NavigationPage content_page;
        Gtk.Button restart_btn;
        string? restart_target;
        PageRegistry registry;

        public SettingsWindow(Gtk.Application app, PageRegistry r) {
            Object(application: app);
            registry = r;

            title = "Lumen Settings";
            set_default_size(980, 680);
            add_css_class("lumen-settings");

            sidebar = new Sidebar(registry);
            var sidebar_view = new Adw.ToolbarView() { content = sidebar };
            sidebar_view.add_top_bar(new Adw.HeaderBar());

            stack = new Gtk.Stack() {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                hexpand = true, vexpand = true,
            };

            restart_btn = new Gtk.Button.with_label("Restart") {
                valign = Gtk.Align.CENTER,
                visible = false,
            };
            restart_btn.add_css_class("suggested-action");
            restart_btn.clicked.connect(restart_current_page);

            var content_header = new Adw.HeaderBar();
            content_header.pack_end(restart_btn);
            var content_view = new Adw.ToolbarView() { content = stack };
            content_view.add_top_bar(content_header);
            content_page = new Adw.NavigationPage(content_view, "Settings");

            split = new Adw.NavigationSplitView() {
                sidebar = new Adw.NavigationPage(sidebar_view, "Lumen Settings"),
                content = content_page,
                min_sidebar_width = 220,
                max_sidebar_width = 300,
            };
            set_content(split);

            rebuild_stack();

            sidebar.page_selected.connect(show_page);
            sidebar.select_first();

            // Cross-page links: target "<page-id>" or "<page-id>:<anchor>".
            var show_action = new SimpleAction("show-page", VariantType.STRING);
            show_action.activate.connect((param) => {
                var parts = param.get_string().split(":", 2);
                sidebar.select_id(parts[0]);
                var page = registry.lookup(parts[0]);
                if (page != null && parts.length > 1) {
                    string anchor = parts[1];
                    // After the stack switch, so the focus scroll has an allocation.
                    Idle.add(() => { page.reveal(anchor); return Source.REMOVE; });
                }
            });
            add_action(show_action);
        }

        void show_page(string id) {
            stack.set_visible_child_name(id);
            var page = registry.lookup(id);
            if (page == null) return;

            content_page.title = page.title;
            restart_target = page.restart_target();
            restart_btn.visible = restart_target != null;
            // Only matters when collapsed (sidebar and content share a pane).
            split.show_content = true;
        }

        void restart_current_page() {
            if (restart_target == null) return;
            try {
                // pkill -x matches the kernel comm, capped at 15 chars; longer
                // names never match and the old daemon keeps its bus name.
                var comm = restart_target.length > 15
                    ? restart_target.substring(0, 15) : restart_target;
                GLib.Process.spawn_command_line_async(
                    "sh -c 'pkill -x %s; sleep 0.3; setsid -f %s'".printf(
                        comm, restart_target));
            } catch (GLib.SpawnError e) {
                warning("lumen-settings: failed to restart %s: %s", restart_target, e.message);
            }
        }

        void rebuild_stack() {
            for (uint i = 0; i < registry.size; i++) {
                var page = registry.get_at(i);
                stack.add_named(page.build(), page.id);
            }
        }
    }
}
