using GLib;
using Gee;

public class SearchDb {
    public bool active;
    public int size;

    private unowned AppEntry[] all_apps;
    public Utils.AliasArray<AppEntry> filtered;

    public SearchDb(AppEntry[] apps) {
        this.all_apps = apps;
        filtered = new Utils.AliasArray<AppEntry>(apps, PER_PAGE);
    }

    public void set_query(string query) {
        var trimmed = query.strip();
        if (trimmed.length == 0) {
            active = false;
            size = 0;
            return;
        }
        active = true;
        index(trimmed.ascii_down());
    }

    private void index(string search_lc) {
        var included = new bool[all_apps.length];

        size = 0;
        for (int i = 0; i < all_apps.length; i++) {
            if (size >= PER_PAGE) break;
            if (all_apps[i].name.has_prefix(search_lc)) {
                included[i] = true;
                filtered.alias_index(size++, i);
            }
        }

        var pattern = new StringBuilder("*");
        foreach (var c in search_lc.to_utf8()) {
            pattern.append_c(c);
            pattern.append_c('*');
        }
        var q = new PatternSpec(pattern.str);

        for (int i = 0; i < all_apps.length; i++) {
            if (size >= PER_PAGE) break;
            if (!included[i] && q.match_string(all_apps[i].name)) {
                filtered.alias_index(size++, i);
            }
        }
    }
}
