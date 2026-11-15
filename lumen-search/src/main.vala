namespace LumenSearch {
    public class SearchApp : Gtk.Application {
        public SearchApp() {
            GLib.Object(application_id: "org.lumenshell.Search", flags: ApplicationFlags.HANDLES_COMMAND_LINE);
            add_main_option("toggle", 0, OptionFlags.NONE, OptionArg.NONE,
                "Show or hide the search window", null);
            add_main_option("query", 0, OptionFlags.NONE, OptionArg.STRING,
                "Run a headless query and print the sections", "TEXT");
        }

        protected override int handle_local_options(VariantDict opts) {
            string? text = null;
            if (!opts.lookup("query", "s", out text)) return -1;
            run_query(text);
            return 0;
        }

        SearchWindow? window;

        // Primary instance only: the daemon starts hidden and stays resident.
        protected override void startup() {
            base.startup();
            SearchConfig.load();
            window = new SearchWindow(this);
            hold();
        }

        protected override int command_line(ApplicationCommandLine cmd) {
            if (cmd.get_options_dict().contains("toggle")) window.toggle();
            return 0;
        }

        // Matched byte offsets wrapped in [].
        static string bracket(string s, int[] pos) {
            var sb = new StringBuilder();
            int pi = 0;
            for (int i = 0; i < s.length; ) {
                var ch = s.get_char(i);
                bool m = pi < pos.length && pos[pi] == i;
                if (m) { pi++; sb.append_c('['); }
                sb.append_unichar(ch);
                if (m) sb.append_c(']');
                i += ch.to_string().length;
            }
            return sb.str;
        }

        static void print_hit(Hit h) {
            var it = h.item;
            stdout.printf("  %s%s%s\n", bracket(it.name, h.name_pos),
                it.dir == "" ? "" : "  -- " + bracket(it.dir, h.dir_pos),
                h.snippet_markup != null ? "  | " + h.snippet_markup : "");
        }

        static void section(string title, Hit[] hits) {
            stdout.printf("%s\n", title);
            foreach (var h in hits) print_hit(h);
        }

        void run_query(string text) {
            var loop = new MainLoop();
            SearchConfig.load();
            var q = Query.parse(text);
            var ranker = new Ranker();
            Item[] items = AppIndex.load();
            Hit[] contents = {};
            // load files and contents concurrently, then quit
            int pending = 2;
            Item[] files = {};
            var fi = new FileIndex();
            fi.load.begin(null, (o, r) => {
                try { files = fi.load.end(r); } catch (GLib.Error e) { warning("file index: %s", e.message); }
                if (--pending == 0) loop.quit();
            });
            var cs = new ContentSearch();
            cs.run.begin(q, null, (o, r) => {
                try { contents = cs.run.end(r); } catch (GLib.Error e) { warning("content search failed"); }
                if (--pending == 0) loop.quit();
            });
            loop.run();
            foreach (var f in files) items += f;
            ranker.set_items(items);
            var res = ranker.search(q);
            stdout.printf("TOP\n");
            if (res.top != null) print_hit(res.top);
            section("APPS", res.apps);
            section("FILES", res.files);
            section("CONTENTS", contents);
        }
    }

    int main(string[] args) {
        return new SearchApp().run(args);
    }
}
