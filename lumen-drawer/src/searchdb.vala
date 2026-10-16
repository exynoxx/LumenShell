using GLib;

public class SearchDb {
    public bool active;
    public int size;

    private unowned AppEntry[] all_apps;
    // Fixed one-page capacity, never reallocated; only the first `size` slots are valid.
    public AppEntry[] filtered;

    private string last_query = "";

    public SearchDb(AppEntry[] apps) {
        this.all_apps = apps;
        filtered = new AppEntry[LumenDrawer.DrawerConfig.per_page];
    }

    public void set_query(string query) {
        var trimmed = query.strip();
        if (trimmed.length == 0) {
            active = false;
            size = 0;
            last_query = "";
            return;
        }
        var lc = trimmed.ascii_down();
        if (active && lc == last_query) return;
        active = true;
        last_query = lc;
        index(lc);
    }

    private void index(string search_lc) {
        // Prefix matches first; re-checking has_prefix in pass 2 is cheaper
        // than a per-keystroke seen[] array.
        int cap = filtered.length;
        size = 0;
        for (int i = 0; i < all_apps.length && size < cap; i++) {
            if (all_apps[i].name.has_prefix(search_lc)) {
                filtered[size++] = all_apps[i];
            }
        }
        if (size >= cap) return;

        var pattern = new StringBuilder.sized(2 * search_lc.length + 2);
        pattern.append_c('*');
        foreach (var c in search_lc.to_utf8()) {
            pattern.append_c(c);
            pattern.append_c('*');
        }
        var q = new PatternSpec(pattern.str);

        for (int i = 0; i < all_apps.length && size < cap; i++) {
            unowned string name = all_apps[i].name;
            if (!name.has_prefix(search_lc) && q.match_string(name)) {
                filtered[size++] = all_apps[i];
            }
        }
    }
}
