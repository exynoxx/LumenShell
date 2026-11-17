// One-window-per-monitor bookkeeping. Needs gtk4 only.
namespace LumenCommon {
    public class Monitors {
        public static GenericArray<Gdk.Monitor> live() {
            var live = new GenericArray<Gdk.Monitor>();
            var display = Gdk.Display.get_default();
            if (display == null) return live;
            var model = display.get_monitors();
            for (uint i = 0; i < model.get_n_items(); i++)
                live.add((Gdk.Monitor) model.get_item(i));
            return live;
        }

        // What to build one window each for: a single null (unpinned window)
        // while no monitor is reported yet, so the surface still appears.
        public static Gdk.Monitor?[] or_unpinned() {
            var l = live();
            if (l.length == 0) return { null };
            Gdk.Monitor?[] r = {};
            foreach (var m in l.data) r += m;
            return r;
        }

        public static bool contains(GenericArray<Gdk.Monitor> live, Gdk.Monitor m) {
            foreach (var x in live.data) if (x == m) return true;
            return false;
        }

        // Destroys and drops every window whose monitor is gone. W must be a Gtk.Window.
        public static void prune<W>(HashTable<Gdk.Monitor, W> wins, GenericArray<Gdk.Monitor> live) {
            var gone = new GenericArray<Gdk.Monitor>();
            wins.foreach((mon, win) => { if (!contains(live, mon)) gone.add(mon); });
            foreach (var mon in gone.data) {
                var win = wins.get(mon);
                if (win != null) ((Gtk.Window) win).destroy();
                wins.remove(mon);
            }
        }

        // `cur` while still connected, else the first live monitor (null if none).
        public static Gdk.Monitor? keep_primary(Gdk.Monitor? cur, GenericArray<Gdk.Monitor> live) {
            if (live.length == 0) return null;
            return (cur != null && contains(live, cur)) ? cur : live.get(0);
        }
    }
}
