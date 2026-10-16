namespace LumenCommon {

    // Strip .desktop Exec field codes for a raw argv (AppInfo.launch() would
    // expand them). "%%" keeps one literal '%'.
    public string strip_field_codes(string exec) {
        var sb = new StringBuilder();
        int i = 0;
        unichar c;
        bool pct = false;
        while (exec.get_next_char(ref i, out c)) {
            if (pct) {
                if (c == '%') sb.append_c('%');
                pct = false;
            } else if (c == '%') {
                pct = true;
            } else {
                sb.append_unichar(c);
            }
        }
        return sb.str.strip();
    }
}
