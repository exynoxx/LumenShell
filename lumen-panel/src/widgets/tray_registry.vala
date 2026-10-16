using Gtk;

public delegate ITrayApplet TrayAppletFactory ();

public class TrayRegistry : GLib.Object {

    // A delegate-with-target can't be a generic type argument (Vala limitation),
    // so each factory is boxed in a GLib.Object holder before going in the table.
    class Entry : GLib.Object {
        public TrayAppletFactory factory;
        public Entry (owned TrayAppletFactory factory) { this.factory = (owned) factory; }
    }

    GLib.HashTable<string, Entry> factories =
        new GLib.HashTable<string, Entry>(str_hash, str_equal);

    public void register (string id, owned TrayAppletFactory factory) {
        factories.insert(id, new Entry((owned) factory));
    }

    // null when the id is unknown — make_tray() simply skips it.
    public ITrayApplet? create (string id) {
        unowned Entry? e = factories.lookup(id);
        return e != null ? e.factory() : null;
    }
}
