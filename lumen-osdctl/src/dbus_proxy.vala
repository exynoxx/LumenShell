[DBus(name = "org.lumenshell.OSD1")]
public interface OsdProxy : Object {
    public abstract void show(string                       kind,
                              double                       value,
                              string                       text,
                              HashTable<string, Variant>   opts) throws DBusError, IOError;

    public abstract void show_selector(string[]                     icons,
                                       string[]                     labels,
                                       int                          selected,
                                       HashTable<string, Variant>   opts) throws DBusError, IOError;

    public abstract void hide() throws DBusError, IOError;

    public abstract void begin_picker() throws DBusError, IOError;
}
