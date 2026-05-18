using Gtk;

namespace LumenSettings {

    public class SettingsWindow : Gtk.ApplicationWindow {
        Sidebar sidebar;
        Gtk.Stack stack;
        Gtk.Label title_label;
        PageRegistry registry;

        public SettingsWindow(Gtk.Application app, PageRegistry r) {
            Object(application: app);
            registry = r;

            title = "Lumen Settings";
            set_default_size(980, 680);
            add_css_class("lumen-settings");

            var root = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0) {
                hexpand = true, vexpand = true,
            };

            sidebar = new Sidebar(registry);
            root.append(sidebar);

            var separator = new Gtk.Separator(Gtk.Orientation.VERTICAL);
            root.append(separator);

            var right = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                hexpand = true, vexpand = true,
            };

            var header = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 12) {
                margin_start = 24, margin_end = 24,
                margin_top = 18, margin_bottom = 6,
            };
            header.add_css_class("lumen-settings-header");
            title_label = new Gtk.Label("") {
                xalign = 0, hexpand = true,
            };
            title_label.add_css_class("title-1");
            header.append(title_label);
            right.append(header);

            stack = new Gtk.Stack() {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                hexpand = true, vexpand = true,
            };
            var scroller = new Gtk.ScrolledWindow() {
                hscrollbar_policy = Gtk.PolicyType.NEVER,
                vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                hexpand = true, vexpand = true,
                child = stack,
            };
            right.append(scroller);

            root.append(right);
            set_child(root);

            registry.changed.connect(rebuild_stack);
            rebuild_stack();

            sidebar.page_selected.connect((id) => {
                stack.set_visible_child_name(id);
                var page = registry.lookup(id);
                if (page != null) title_label.label = page.title;
            });

            sidebar.select_first();
        }

        void rebuild_stack() {
            Gtk.Widget? child = stack.get_first_child();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling();
                stack.remove(child);
                child = next;
            }
            for (uint i = 0; i < registry.size; i++) {
                var page = registry.get_at(i);
                var body = page.build();
                var wrap = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                    margin_start = 24, margin_end = 24,
                    margin_top = 6, margin_bottom = 24,
                };
                wrap.append(body);
                stack.add_named(wrap, page.id);
            }
        }
    }
}
