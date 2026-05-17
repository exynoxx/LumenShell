using GLib;
using Gee;

public class SearchDb {
    public bool active;
    public int size;

    private unowned AppEntry[] all_apps;
    public Utils.AliasArray<AppEntry> filtered;

    private string last_query = "";

    public SearchDb(AppEntry[] apps) {
        this.all_apps = apps;
        filtered = new Utils.AliasArray<AppEntry>(apps, PER_PAGE);
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
        // Pass 1: prefix matches. has_prefix is a cheap memcmp on the head
        // of the name, so re-running it in pass 2 is faster than allocating
        // a bool[all_apps.length] tracker per keystroke.
        size = 0;
        for (int i = 0; i < all_apps.length && size < PER_PAGE; i++) {
            if (all_apps[i].name.has_prefix(search_lc)) {
                filtered.alias_index(size++, i);
            }
        }
        if (size >= PER_PAGE) return;

        var pattern = new StringBuilder.sized(2 * search_lc.length + 2);
        pattern.append_c('*');
        foreach (var c in search_lc.to_utf8()) {
            pattern.append_c(c);
            pattern.append_c('*');
        }
        var q = new PatternSpec(pattern.str);

        for (int i = 0; i < all_apps.length && size < PER_PAGE; i++) {
            unowned string name = all_apps[i].name;
            if (!name.has_prefix(search_lc) && q.match_string(name)) {
                filtered.alias_index(size++, i);
            }
        }
    }
}
