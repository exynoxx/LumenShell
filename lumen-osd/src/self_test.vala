using GLib;

public class OsdSelfTest : Object {

    private struct Frame {
        bool   is_chip;
        string icon;
        double value;
        string text;
    }

    private OsdWindow window;
    private Gtk.Application app;

    public OsdSelfTest(Gtk.Application app, OsdWindow window) {
        this.app = app;
        this.window = window;
    }

    public void run() {
        stderr.printf("[lumen-osd] --test: running development visualizer\n");
        Frame[] frames = {
            { false, "audio-volume-muted-symbolic",            0.00, "Volume muted" },
            { false, "audio-volume-low-symbolic",              0.20, "Volume 20%" },
            { false, "audio-volume-medium-symbolic",           0.55, "Volume 55%" },
            { false, "audio-volume-high-symbolic",             0.95, "Volume 95%" },

            { false, "microphone-sensitivity-muted-symbolic",  0.00, "Mic muted" },
            { false, "microphone-sensitivity-low-symbolic",    0.20, "Mic 20%" },
            { false, "microphone-sensitivity-medium-symbolic", 0.55, "Mic 55%" },
            { false, "microphone-sensitivity-high-symbolic",   0.90, "Mic 90%" },

            { false, "display-brightness-symbolic",            0.10, "Brightness 10%" },
            { false, "display-brightness-symbolic",            0.50, "Brightness 50%" },
            { false, "display-brightness-symbolic",            1.00, "Brightness 100%" },

            { false, "keyboard-brightness-symbolic",           0.00, "Kbd light off" },
            { false, "keyboard-brightness-symbolic",           0.50, "Kbd light 50%" },
            { false, "keyboard-brightness-symbolic",           1.00, "Kbd light 100%" },

            { true,  "keyboard-symbolic",                      0.00, "Caps ON" },
            { true,  "keyboard-symbolic",                      0.00, "Caps OFF" },

            { true,  "dialog-information-symbolic",            0.00, "Hello chip" },
            { false, "dialog-information-symbolic",            0.40, "Custom 40%" }
        };

        int step = 0;
        Timeout.add(900, () => {
            if (step >= frames.length) {
                stderr.printf("[lumen-osd] --test: done, quitting\n");
                window.set_visible(false);
                app.quit();
                return Source.REMOVE;
            }
            var f = frames[step];
            stderr.printf("[lumen-osd] --test [%2d/%d] %s icon=%s value=%.2f text=\"%s\"\n",
                          step + 1, frames.length,
                          f.is_chip ? "chip  " : "slider",
                          f.icon, f.value, f.text);
            if (f.is_chip) {
                window.pill.show_chip(f.icon, f.text);
            } else {
                window.pill.show_slider(f.icon, f.value, f.text);
            }
            window.set_visible(true);
            step++;
            return Source.CONTINUE;
        });
    }
}
