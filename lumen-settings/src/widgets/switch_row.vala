using Gtk;

namespace LumenSettings {

    public class SwitchRow : ActionRow {
        public Gtk.Switch sw { get; private set; }
        public signal void toggled(bool active);

        public SwitchRow(string title, string subtitle = "", bool initial = false) {
            base(title, subtitle);
            sw = new Gtk.Switch() { active = initial };
            sw.notify["active"].connect(() => toggled(sw.active));
            set_suffix(sw);
        }
    }
}
