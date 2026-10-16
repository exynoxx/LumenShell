public class LumenTextField : Gtk.Widget {

    Gtk.Text entry;

    public signal void submitted ();
    public signal void cancelled ();

    public string placeholder {
        get { return entry.placeholder_text; }
        set { entry.placeholder_text = value; }
    }
    public string text {
        get { return entry.text; }
        set { entry.text = value; }
    }

    public bool obscure_text {
        get { return !entry.visibility; }
        set { entry.visibility = !value; }
    }

    static Gdk.RGBA glow = Utils.rgba(0.22f, 0.48f, 1.0f, 0.55f);

    public LumenTextField () {
        layout_manager = new Gtk.BinLayout();
        add_css_class("lumen-text-field");

        entry = new Gtk.Text() {
            hexpand = true,
            valign = Gtk.Align.CENTER,
            margin_start = 10,
            margin_end = 10,
            margin_top = 6,
            margin_bottom = 6,
        };
        entry.add_css_class("lumen-text-field-entry");
        entry.set_parent(this);

        entry.activate.connect(() => submitted());
        var key = new Gtk.EventControllerKey();
        key.key_pressed.connect((keyval, kc, mods) => {
            if (keyval == Gdk.Key.Escape) {
                cancelled();
                return true;
            }
            return false;
        });
        entry.add_controller(key);

        // Repaint the focus halo and reconcile the layer keyboard mode.
        entry.notify["has-focus"].connect(() => {
            queue_draw();
            sync_layer_keyboard();
        });
    }

    // Wayfire doesn't reliably grant keyboard focus to an ON_DEMAND layer surface on
    // click, so the field would never see a keystroke. Take EXCLUSIVE while focused
    // and hand back ON_DEMAND the moment focus leaves.
    void sync_layer_keyboard () {
        var win = get_root() as Gtk.Window;
        if (win == null || !GtkLayerShell.is_layer_window(win)) return;
        GtkLayerShell.set_keyboard_mode(
            win,
            entry.has_focus ? GtkLayerShell.KeyboardMode.EXCLUSIVE
                            : GtkLayerShell.KeyboardMode.ON_DEMAND);
    }

    public void grab_text_focus () {
        entry.grab_focus();
    }

    public void blur () {
        if (root != null) ((Gtk.Window) root).set_focus(null);
    }

    public override void dispose () {
        if (entry != null) {
            entry.unparent();
            entry = null;
        }
        base.dispose();
    }

    public override void snapshot (Gtk.Snapshot s) {
        if (entry.has_focus) {
            int w = get_width();
            int h = get_height();
            var rect = Graphene.Rect();
            rect.init(-1, -1, w + 2, h + 2);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(rect, 14f);
            float[] widths = { 2, 2, 2, 2 };
            Gdk.RGBA[] colors = { glow, glow, glow, glow };
            s.append_border(rr, widths, colors);
        }
        base.snapshot(s);
    }
}
