using GLib;

public class Presenter : Object {

    private OsdWindowGroup group;

    public Presenter(OsdWindowGroup group) {
        this.group = group;
    }

    public void present(string kind, double value, string text,
                        string? icon_override, bool muted) {
        string icon = (icon_override != null)
                      ? (!) icon_override
                      : icon_for(kind, value, muted);

        foreach (var w in group.windows())
            apply(w.pill, kind, value, text, icon);
    }

    private static void apply(Pill pill, string kind, double value,
                              string text, string icon) {
        switch (kind) {
            case "volume":
            case "mic":
            case "brightness":
            case "kbd-brightness":
                pill.show_slider(icon, value,
                    text != "" ? text : "%d%%".printf((int) Math.round(value * 100)));
                break;

            case "caps-lock":
                pill.show_chip(icon, text != "" ? text : "Caps");
                break;

            case "display":
                pill.show_chip(icon, text != "" ? text : "Display");
                break;

            case "custom":
            default:
                if (text != "" && value <= 0.0) {
                    pill.show_chip(icon, text);
                } else if (value > 0.0) {
                    pill.show_slider(icon, value, text);
                } else {
                    pill.show_chip(icon, kind);
                }
                break;
        }
    }

    private static string icon_for(string kind, double value, bool muted) {
        switch (kind) {
            case "volume":
                if (muted || value <= 0.01) return "audio-volume-muted-symbolic";
                if (value < 0.34) return "audio-volume-low-symbolic";
                if (value < 0.67) return "audio-volume-medium-symbolic";
                return "audio-volume-high-symbolic";
            case "mic":
                if (muted) return "microphone-sensitivity-muted-symbolic";
                if (value < 0.34) return "microphone-sensitivity-low-symbolic";
                if (value < 0.67) return "microphone-sensitivity-medium-symbolic";
                return "microphone-sensitivity-high-symbolic";
            case "brightness":
                return "display-brightness-symbolic";
            case "kbd-brightness":
                return "keyboard-brightness-symbolic";
            case "caps-lock":
                return "keyboard-symbolic";
            case "display":
                return "video-display-symbolic";
            case "custom":
            default:
                return "dialog-information-symbolic";
        }
    }
}
