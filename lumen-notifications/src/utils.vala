using GLib;

public class Utils {
    // Precedence: explicit env override → the user's config in
    // ~/.config/lumen-shell/ (what lumen-settings writes) → the packaged
    // read-only default. This keeps all editable config in the home dir.
    public static string THEME_FILE {
        owned get {
            var env = Environment.get_variable("LUMEN_NOTIFICATIONS_THEME_FILE");
            if (env != null) return env;
            var home = Environment.get_user_config_dir() + "/lumen-shell/notifications.json";
            if (FileUtils.test(home, FileTest.EXISTS)) return home;
            return "/usr/share/lumen-notifications/default-notifications-theme.json";
        }
    }

    // Convert a freedesktop notification body into valid Pango markup.
    //
    // Per the Desktop Notifications spec the body may carry a small markup
    // subset (<b>, <i>, <u>, <a href>, <img>). Apps in the wild often send
    // more than that — full HTML, unclosed tags, raw ampersands — which Pango
    // refuses to parse, leaving the label to show the raw tags. We keep only
    // the tags Pango understands, drop the rest, and escape stray text so the
    // result always parses.
    public static string body_to_markup(string body) {
        var sb = new StringBuilder();
        // Stack of formatting tags we've opened, so we can close any the app
        // left dangling and ignore stray closes — the result is always
        // well-balanced and accepted by GtkLabel.set_markup.
        var open = new GLib.Queue<string>();
        int len = body.length; // byte length
        int i = 0;
        // '<', '>', '&' are ASCII, so byte-wise scanning is safe for UTF-8:
        // multi-byte sequences never contain these bytes, and non-matching
        // bytes are copied through verbatim.
        while (i < len) {
            char c = body[i];
            if (c == '<') {
                int close = body.index_of_char('>', i + 1);
                if (close < 0) {
                    // No closing '>' — treat the rest as literal text.
                    sb.append(Markup.escape_text(body.substring(i)));
                    break;
                }
                string tag = body.substring(i, close - i + 1);
                emit_tag(sb, open, tag);
                i = close + 1;
            } else if (c == '&') {
                // Preserve valid entities, escape bare ampersands.
                if (is_entity(body, i)) {
                    sb.append_c('&');
                } else {
                    sb.append("&amp;");
                }
                i++;
            } else {
                sb.append_c(c);
                i++;
            }
        }
        // Close anything still open, innermost first.
        while (!open.is_empty()) {
            sb.append("</%s>".printf(open.pop_head()));
        }
        return sb.str;
    }

    // Append the GtkLabel-markup equivalent of a single HTML/markup tag,
    // updating the open-tag stack so output stays balanced.
    private static void emit_tag(StringBuilder sb, GLib.Queue<string> open, string tag) {
        // tag includes the surrounding angle brackets, e.g. "<b>", "</a>",
        // "<a href=\"x\">", "<br/>".
        string inner = tag.substring(1, tag.length - 2).strip(); // strip <>
        bool closing = inner.has_prefix("/");
        if (closing) inner = inner.substring(1).strip();

        // Tag name is up to the first whitespace or '/'.
        string name = inner;
        int sp = -1;
        for (int k = 0; k < inner.length; k++) {
            char ch = inner[k];
            if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '/') { sp = k; break; }
        }
        if (sp >= 0) name = inner.substring(0, sp);
        name = name.down();

        switch (name) {
            case "b":
            case "i":
            case "u":
                if (closing) {
                    // Only emit a close if it matches the innermost open tag;
                    // otherwise drop it to keep nesting valid.
                    if (!open.is_empty() && open.peek_head() == name) {
                        sb.append("</%s>".printf(name));
                        open.pop_head();
                    }
                } else {
                    sb.append("<%s>".printf(name));
                    open.push_head(name);
                }
                return;
            case "a":
                // GtkLabel links aren't actionable in a transient banner; keep
                // the link's visible text and drop the tag itself.
                return;
            case "br":
                sb.append_c('\n');
                return;
            case "img":
                // Pango has no <img>; surface the alt text if present.
                string? alt = attr_value(inner, "alt");
                if (alt != null) sb.append(Markup.escape_text((!) alt));
                return;
            default:
                return; // unknown tag: drop it
        }
    }

    // Extract attribute value (handles single or double quotes).
    private static string? attr_value(string inner, string attr) {
        int idx = inner.down().index_of(attr + "=");
        if (idx < 0) return null;
        int v = idx + attr.length + 1;
        if (v >= inner.length) return null;
        char q = inner[v];
        if (q == '"' || q == '\'') {
            int end = inner.index_of_char(q, v + 1);
            if (end < 0) return null;
            return inner.substring(v + 1, end - (v + 1));
        }
        // Unquoted: read until whitespace or '>'.
        int end = v;
        while (end < inner.length) {
            char ch = inner[end];
            if (ch == ' ' || ch == '\t' || ch == '>') break;
            end++;
        }
        return inner.substring(v, end - v);
    }

    // Does the '&' at byte position `pos` begin a valid XML entity?
    private static bool is_entity(string s, long pos) {
        int semi = s.index_of_char(';', (int) pos + 1);
        if (semi < 0 || semi - pos > 12) return false;
        string ent = s.substring(pos + 1, semi - pos - 1);
        if (ent == "amp" || ent == "lt" || ent == "gt"
            || ent == "quot" || ent == "apos") return true;
        // Numeric: &#123; or &#x1F;
        if (ent.has_prefix("#")) {
            string num = ent.substring(1);
            if (num.has_prefix("x") || num.has_prefix("X")) num = num.substring(1);
            if (num.length == 0) return false;
            for (int k = 0; k < num.length; k++) {
                if (!num[k].isxdigit()) return false;
            }
            return true;
        }
        return false;
    }
}
