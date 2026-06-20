namespace LumenSettings {

    // Adw.SwitchRow is sealed, so we compose: an Adw.ActionRow (via our base)
    // with a Gtk.Switch suffix — the same shape Adw.SwitchRow has internally.
    // `sw` is kept public so pages can drive sensitivity / active state.
    public class SwitchRow : ActionRow {
        public Gtk.Switch sw { get; private set; }
        public signal void toggled(bool active);

        public SwitchRow(string title, string subtitle = "", bool initial = false) {
            base(title, subtitle);
            sw = new Gtk.Switch() { active = initial };
            sw.notify["active"].connect(() => toggled(sw.active));
            set_suffix(sw);
            activatable_widget = sw;
        }
    }
}
