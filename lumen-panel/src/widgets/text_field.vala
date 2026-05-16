using Gtk;

// Lumen-styled text input. Wraps a Gtk.Text (the bare editable text widget
// — no themed Entry chrome) inside a custom-drawn rounded container that
// renders the focus glow and bg color from the original UiTextField. CSS
// handles hover/focus background; snapshot() renders the outer focus halo
// when focused.
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

    static Gdk.RGBA glow = make_rgba(0.22f, 0.48f, 1.0f, 0.55f);
    static Gdk.RGBA make_rgba (float r, float g, float b, float a) {
        var c = Gdk.RGBA();
        c.red = r; c.green = g; c.blue = b; c.alpha = a;
        return c;
    }

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

        // Repaint focus halo when focus changes.
        entry.notify["has-focus"].connect(queue_draw);
    }

    public void grab_text_focus () {
        entry.grab_focus();
    }

    public void blur () {
        if (root != null) ((Gtk.Window) root).set_focus(null);
    }

    public bool has_focus_within () {
        return entry.has_focus;
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
            // 2 px outer halo above the CSS background, drawn with the
            // original focus_glow_color.
            int w = get_width();
            int h = get_height();
            var rect = Graphene.Rect();
            rect.init(-1, -1, w + 2, h + 2);
            var rr = Gsk.RoundedRect();
            rr.init_from_rect(rect, 10f);
            float[] widths = { 2, 2, 2, 2 };
            Gdk.RGBA[] colors = { glow, glow, glow, glow };
            s.append_border(rr, widths, colors);
        }
        base.snapshot(s);
    }
}
