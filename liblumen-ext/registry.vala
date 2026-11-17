namespace Lumen {

    public enum Cardinality { ONE, MANY }

    // slot id → ordered (provider id, impl). ONE slots have an active impl chosen
    // in extensions.json "slots", defaulting to the first provider.
    public class Registry : GLib.Object {

        class Entry {
            public string ext_id;
            public GLib.Object impl;
            public Entry (string ext_id, GLib.Object impl) { this.ext_id = ext_id; this.impl = impl; }
        }

        class Slot {
            public Cardinality card;
            public GLib.GenericArray<Entry> entries = new GLib.GenericArray<Entry> ();
            public Slot (Cardinality card) { this.card = card; }
        }

        ExtensionConfig config;
        GLib.HashTable<string, Slot> slots = new GLib.HashTable<string, Slot> (str_hash, str_equal);

        public signal void changed (string slot);

        public Registry (ExtensionConfig config) {
            this.config = config;
        }

        public void declare (string slot, Cardinality card) {
            if (!slots.contains (slot)) slots.insert (slot, new Slot (card));
        }

        public void provide (string slot, string ext_id, GLib.Object impl) {
            unowned Slot? s = slots.lookup (slot);
            if (s == null) {
                warning ("lumen-ext: %s provides undeclared slot %s", ext_id, slot);
                return;
            }
            s.entries.add (new Entry (ext_id, impl));
            changed (slot);
        }

        public void withdraw (string ext_id) {
            slots.foreach ((name, s) => {
                bool hit = false;
                for (int i = (int) s.entries.length - 1; i >= 0; i--) {
                    if (s.entries[i].ext_id == ext_id) { s.entries.remove_index (i); hit = true; }
                }
                if (hit) changed (name);
            });
        }

        public GLib.Object? active (string slot) {
            unowned Slot? s = slots.lookup (slot);
            if (s == null || s.entries.length == 0) return null;
            var want = config.active_for (slot);
            if (want != null) {
                foreach (var e in s.entries) if (e.ext_id == want) return e.impl;
            }
            return s.entries[0].impl;
        }

        public string? active_id (string slot) {
            var impl = active (slot);
            unowned Slot? s = slots.lookup (slot);
            if (impl == null) return null;
            foreach (var e in s.entries) if (e.impl == impl) return e.ext_id;
            return null;
        }

        public GLib.GenericArray<GLib.Object> all (string slot) {
            var out_ = new GLib.GenericArray<GLib.Object> ();
            unowned Slot? s = slots.lookup (slot);
            if (s != null) foreach (var e in s.entries) out_.add (e.impl);
            return out_;
        }

        public string[] provider_ids (string slot) {
            string[] out_ = {};
            unowned Slot? s = slots.lookup (slot);
            if (s != null) foreach (var e in s.entries) out_ += e.ext_id;
            return out_;
        }
    }
}
