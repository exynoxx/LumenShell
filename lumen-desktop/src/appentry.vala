public class AppEntry {
    public AppInfo info;
    public string display_name;
    public string short_name;
    public string name;

    public signal void launched();

    public AppEntry(AppInfo info) {
        this.info = info;
        this.display_name = info.get_display_name();
        this.short_name = display_name.char_count() > 20
            ? display_name.substring(0, 20) + "..."
            : display_name;
        this.name = display_name.ascii_down();
    }

    public void launch() {
        try {
            info.launch(null, null);
        } catch (Error e) {
            stderr.printf("Failed to launch %s: %s\n", display_name, e.message);
        }
        launched();
    }
}
