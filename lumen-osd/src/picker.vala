// The keyboard grab exists to see the Super release (Wayfire command bindings
// fire on press only), which commits the highlighted mode.
public class Picker : Object {

    // Tile order; the trailing ABORT_INDEX tile has no mode behind it.
    private const DisplayCtl.Mode[] MODES = {
        DisplayCtl.Mode.INTERNAL_ONLY,
        DisplayCtl.Mode.EXTEND,
        DisplayCtl.Mode.EXTERNAL_ONLY,
    };
    private const int ABORT_INDEX = 3;
    private const int TILE_COUNT  = 4;

    // Safety net against a missed Super-release holding the grab forever;
    // re-armed on every keypress.
    private const uint IDLE_DISMISS_MS = 8000;

    private OsdWindowGroup group;
    private OsdWindow window;
    private bool      _active        = false;
    private bool      saw_super      = false;
    private bool      user_moved     = false;   // ignore async seed once touched
    private int       index          = 0;
    private int       last_index     = 0;        // remembered between invocations
    private uint      dismiss_source = 0;

    public bool active { get { return _active; } }

    public Picker(OsdWindowGroup group) {
        this.group  = group;
        this.window = group.primary;

        var keys = new Gtk.EventControllerKey();
        // CAPTURE so we win over any focusable child the selector might gain.
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        keys.key_pressed.connect(on_key_pressed);
        keys.key_released.connect(on_key_released);
        keys.modifiers.connect(on_modifiers);
        ((Gtk.Widget) window).add_controller(keys);

        window.selector.hovered.connect((i) => { if (_active) move_to(i); });
        window.selector.chosen.connect((i)  => { if (_active) choose(i); });
    }

    // Wayfire consumes Super+P, so each tap arrives as a fresh DBus call: open
    // on the first, advance on the rest.
    public void step() {
        if (!_active) {
            open();
        } else {
            advance();
        }
    }

    private void open() {
        _active    = true;
        saw_super  = false;
        user_moved = false;
        index      = last_index;

        refresh();
        group.hide_mirrors();
        window.grab_keyboard();
        window.set_visible(true);
        arm_dismiss();

        // Async so it never delays the grab; ignored once the user has moved.
        seed_current_mode();
    }

    private void refresh() {
        var icons  = new string[TILE_COUNT];
        var labels = new string[TILE_COUNT];
        for (int i = 0; i < MODES.length; i++) {
            icons[i]  = MODES[i].icon();
            labels[i] = MODES[i].label();
        }
        icons[ABORT_INDEX]  = "window-close-symbolic";
        labels[ABORT_INDEX] = "";

        window.selector.set_items(icons, labels, index);
        window.show_selector_view();
    }

    private void advance() {
        move_to((index + 1) % TILE_COUNT);
    }

    private void move_to(int i) {
        index      = i.clamp(0, TILE_COUNT - 1);
        user_moved = true;
        refresh();
        arm_dismiss();
    }

    private void choose(int i) {
        index      = i.clamp(0, TILE_COUNT - 1);
        user_moved = true;
        commit();
    }

    private void commit() {
        if (!_active) return;
        // The trailing "abort" tile dismisses without applying anything.
        if (index == ABORT_INDEX) { cancel(); return; }
        _active    = false;
        last_index = index;
        cancel_dismiss();

        window.release_keyboard();
        // Hide now; a successful apply calls back into show() with the chip, a
        // failed one leaves the OSD hidden rather than the selector stuck.
        window.set_visible(false);

        // Out-of-process on purpose: DisplayCtl.apply() blocks on Wayland
        // roundtrips through the modeset, which this daemon's main loop must not.
        LumenCommon.Proc.spawn_detached({ "lumen-osdctl", "--display-mode", MODES[index].key() });
    }

    private void cancel() {
        if (!_active) return;
        _active = false;
        cancel_dismiss();
        window.release_keyboard();
        window.set_visible(false);
    }

    private void arm_dismiss() {
        cancel_dismiss();
        dismiss_source = Timeout.add(IDLE_DISMISS_MS, () => {
            dismiss_source = 0;
            cancel();
            return Source.REMOVE;
        });
    }

    private void cancel_dismiss() {
        if (dismiss_source != 0) {
            Source.remove(dismiss_source);
            dismiss_source = 0;
        }
    }

    private bool on_key_pressed(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (!_active) return false;
        switch (keyval) {
            case Gdk.Key.Escape:
                cancel();
                return true;
            case Gdk.Key.Left:
                move_to((index - 1 + TILE_COUNT) % TILE_COUNT);
                return true;
            case Gdk.Key.Right:
                move_to((index + 1) % TILE_COUNT);
                return true;
            case Gdk.Key.Return:
            case Gdk.Key.KP_Enter:
            case Gdk.Key.space:
                commit();
                return true;
            default:
                // P itself never reaches us — Wayfire consumes <super> KEY_P and
                // re-invokes step() instead. Swallow anything else to stay modal.
                return true;
        }
    }

    private void on_key_released(uint keyval, uint keycode, Gdk.ModifierType state) {
        if (!_active) return;
        if (keyval == Gdk.Key.Super_L || keyval == Gdk.Key.Super_R) commit();
    }

    // Some compositors report a held modifier's release only as a state change.
    // Require Super seen held first, or a zero-state at focus-in would commit.
    private bool on_modifiers(Gdk.ModifierType state) {
        if (!_active) return false;
        bool super_now = (state & Gdk.ModifierType.SUPER_MASK) != 0;
        if (super_now) saw_super = true;
        else if (saw_super) commit();
        return false;
    }

    // Raw Subprocess rather than LumenCommon.Proc: this must not block the UI
    // thread while the picker is up, and Proc only offers a synchronous capture.
    private void seed_current_mode() {
        try {
            var sp = new Subprocess(SubprocessFlags.STDOUT_PIPE,
                                    "lumen-osdctl", "--display-current");
            sp.communicate_utf8_async.begin(null, null, (obj, res) => {
                try {
                    string outp;
                    sp.communicate_utf8_async.end(res, out outp, null);
                    if (!_active || user_moved || outp == null) return;
                    var live = DisplayCtl.Mode.parse(outp.strip());
                    if (live == null) return;
                    for (int i = 0; i < MODES.length; i++) {
                        if (MODES[i] == live) { index = i; refresh(); break; }
                    }
                } catch (Error e) {
                    // Best-effort: keep the provisional highlight.
                }
            });
        } catch (Error e) {
            // lumen-osdctl missing / unspawnable: keep the provisional highlight.
        }
    }
}
