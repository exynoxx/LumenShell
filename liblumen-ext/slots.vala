// Slot interfaces shared by the host (lumen-panel) and extensions — they live
// here so both sides see one GType.
namespace Lumen {

    // Slot ids.
    public const string SLOT_TRAY_APPLET    = "tray.applet";      // MANY: TrayAppletFactory
    public const string SLOT_TRAY_PRESENTER = "tray.presenter";   // ONE:  TrayPresenter

    // One item in the tray's icon row. Applets with a control surface also
    // implement CcModule; icon-only items (clock, systray) don't.
    public interface TrayApplet : GLib.Object {
        public abstract Gtk.Widget tray_widget ();
    }

    public interface CcModule : GLib.Object {
        public abstract string      module_id ();   // "wifi", "bluetooth", …
        public abstract Gtk.Widget  home_tile ();   // shown in the overview
        public abstract Gtk.Widget? detail_view (); // inline detail, or null

        public signal void open_detail ();
    }

    // What the tray.applet slot holds. A factory, not an instance: a widget has
    // one parent, and every panel that shows a tray needs its own applets.
    // The applet's id (what panel.json tray.order / tray.disabled name) is the
    // provider id: built-ins provide as "wifi", "clock", …; an extension's
    // applet is named by its extension id, so it provides at most one.
    public interface TrayAppletFactory : GLib.Object {
        public abstract string label { owned get; }
        public abstract TrayApplet create ();
    }

    // The applets one tray presents, in configured order.
    public class TrayModel : GLib.Object {
        public GLib.GenericArray<TrayApplet> applets = new GLib.GenericArray<TrayApplet> ();
        public GLib.GenericArray<CcModule>   modules = new GLib.GenericArray<CcModule> ();

        public void add (TrayApplet a) {
            applets.add (a);
            var m = a as CcModule;
            if (m != null) modules.add (m);
        }
    }

    // One live tray on one panel window.
    public interface Tray : GLib.Object {
        // Widget placed at the end of the panel strip, or null if the tray
        // lives entirely in its own surfaces.
        public abstract Gtk.Widget? strip_widget ();
        public abstract void toggle ();     // tray icon row click / DBus ToggleTray
        public abstract void collapse ();   // Escape, auto-hide
        public abstract bool expanded  { get; }
        public abstract bool animating { get; }
        // Union into `region` (panel_window surface coords) whatever must stay
        // clickable while expanded or animating. Own-surface trays add nothing.
        public abstract void input_rects (Gtk.Window panel_window, Cairo.Region region);

        public signal void expanded_changed ();
    }

    // What the tray.presenter slot holds: builds one Tray per hosting panel.
    public interface TrayPresenter : GLib.Object {
        public abstract Tray create (TrayModel model, Gtk.Window panel_window);
    }
}
