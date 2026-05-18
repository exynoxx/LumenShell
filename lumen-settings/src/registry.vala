using Gtk;

namespace LumenSettings {

    public class PageRegistry : GLib.Object {
        public signal void changed();

        GLib.GenericArray<SettingsPage> pages = new GLib.GenericArray<SettingsPage>();
        GLib.GenericArray<string>       sections = new GLib.GenericArray<string>();

        public void add(SettingsPage page, string section = "") {
            pages.add(page);
            sections.add(section);
            changed();
        }

        public uint size { get { return pages.length; } }

        public SettingsPage get_at(uint i) { return pages.get(i); }
        public string section_at(uint i) { return sections.get(i); }

        public SettingsPage? lookup(string id) {
            for (uint i = 0; i < pages.length; i++) {
                if (pages.get(i).id == id) return pages.get(i);
            }
            return null;
        }
    }
}
