namespace LumenSettings {

    // Adw.SpinRow is sealed, so we compose: an Adw.ActionRow (via our base)
    // with a Gtk.SpinButton suffix. `spin` stays public for parity with the
    // old API.
    public class SpinRow : ActionRow {
        public Gtk.SpinButton spin { get; private set; }
        public signal void value_changed(double v);

        public SpinRow(string title, double min, double max, double step,
                       double initial, double precision = 0,
                       string subtitle = "") {
            base(title, subtitle);
            var adj = new Gtk.Adjustment(initial, min, max, step, step * 10, 0);
            uint digits = (uint) precision;
            spin = new Gtk.SpinButton(adj, step, digits);
            spin.numeric = true;
            spin.notify["value"].connect(() => value_changed(spin.get_value()));
            set_suffix(spin);
        }
    }
}
