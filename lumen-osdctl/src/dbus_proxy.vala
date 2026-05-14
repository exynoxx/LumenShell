[DBus(name = "org.lumenshell.OSD1")]
public interface OsdProxy : Object {
    public abstract void show(string                       kind,
                              double                       value,
                              string                       text,
                              HashTable<string, Variant>   opts) throws DBusError, IOError;
}
