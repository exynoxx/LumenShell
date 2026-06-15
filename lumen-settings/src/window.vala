using Gtk;

namespace LumenSettings {

    public class SettingsWindow : Gtk.ApplicationWindow {
        Sidebar sidebar;
        Gtk.Stack stack;
        Gtk.Label title_label;
        Gtk.Button restart_btn;
        string? restart_target;
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

            restart_btn = new Gtk.Button.with_label("Restart") {
                valign = Gtk.Align.CENTER,
                visible = false,
            };
            restart_btn.add_css_class("suggested-action");
            restart_btn.clicked.connect(restart_current_page);
            header.append(restart_btn);

            right.append(header);

            stack = new Gtk.Stack() {
                transition_type = Gtk.StackTransitionType.CROSSFADE,
                hexpand = true, vexpand = true,
            };
            right.append(stack);

            root.append(right);
            set_child(root);

            registry.changed.connect(rebuild_stack);
            rebuild_stack();

            sidebar.page_selected.connect((id) => {
                stack.set_visible_child_name(id);
                var page = registry.lookup(id);
                if (page != null) {
                    title_label.label = page.title;
                    restart_target = page.restart_target();
                    restart_btn.visible = restart_target != null;
                }
            });

            sidebar.select_first();
        }

        void restart_current_page() {
            if (restart_target == null) return;
            try {
                // setsid -f fully detaches the new process so it outlives
                // lumen-settings; the sleep lets the old surface tear down.
                //
                // pkill -x matches against the kernel's `comm`, which is capped
                // at 15 chars (TASK_COMM_LEN-1), so the full name of a longer
                // target (lumen-lockscreen=16, lumen-notifications=19) never
                // matches and the old daemon survives — then the freshly spawned
                // one can't own its bus name and quits. Match the truncated comm.
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
            Gtk.Widget? child = stack.get_first_child();
            while (child != null) {
                Gtk.Widget? next = child.get_next_sibling();
                stack.remove(child);
                child = next;
            }
            for (uint i = 0; i < registry.size; i++) {
                var page = registry.get_at(i);
                var body = page.build();
                // Pages that scroll themselves (e.g. ones with a pinned search
                // bar or back button) go in verbatim; everyone else gets the
                // standard margins and a ScrolledWindow wrapper.
                if (page.scrolls_itself()) {
                    stack.add_named(body, page.id);
                    continue;
                }
                var wrap = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                    margin_start = 24, margin_end = 24,
                    margin_top = 6, margin_bottom = 24,
                };
                wrap.append(body);
                var scroller = new Gtk.ScrolledWindow() {
                    hscrollbar_policy = Gtk.PolicyType.NEVER,
                    vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                    hexpand = true, vexpand = true,
                    child = wrap,
                };
                stack.add_named(scroller, page.id);
            }
        }
    }
}
